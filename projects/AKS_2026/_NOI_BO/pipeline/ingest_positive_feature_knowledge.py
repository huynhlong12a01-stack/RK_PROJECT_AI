#!/usr/bin/env python3
"""Create an atomic, coordinate-free AKS positive-reference knowledge package."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import secrets
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd


def load_module(name: str, path: Path):
    specification = importlib.util.spec_from_file_location(name, path)
    if specification is None or specification.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(specification)
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve().parent
RULES = load_module("aks_positive_reference_contract_ingest", HERE / "positive_reference_contract.py")
EXPECTED_OUTPUT_FILES = {
    "model_card.json",
    "feature_schema.json",
    "positive_temporal_features.csv",
    "positive_feature_domain.json",
    "positive_feature_prototypes.csv",
    "extraction_contract_snapshot.json",
    "knowledge_manifest.json",
}


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    os.close(handle)
    temporary_path = Path(temporary)
    try:
        temporary_path.write_text(text, encoding="utf-8")
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def atomic_json(path: Path, value: dict[str, Any]) -> None:
    atomic_text(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def atomic_csv(path: Path, table: pd.DataFrame) -> None:
    atomic_text(path, table.to_csv(index=False, lineterminator="\n"))


def parse_bool(value: object) -> bool:
    if isinstance(value, (bool, np.bool_)):
        return bool(value)
    if value is None or (isinstance(value, float) and np.isnan(value)):
        return False
    normalized = str(value).strip().lower()
    if normalized in {"true", "t", "1", "yes", "y"}:
        return True
    if normalized in {"false", "f", "0", "no", "n", ""}:
        return False
    raise ValueError(f"Cannot parse boolean value: {value!r}")


def inside(child: Path, parent: Path) -> bool:
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def observed_prototypes(table: pd.DataFrame, bands: list[str], requested: int) -> pd.DataFrame:
    complete = table.loc[table["feature_complete"], bands].astype(float)
    if complete.empty or requested <= 0:
        return pd.DataFrame(columns=["reference_id", "label", "feature_complete", *bands])
    values = complete.to_numpy(dtype=float)
    center = np.nanmedian(values, axis=0)
    scale = np.nanstd(values, axis=0)
    scale[~np.isfinite(scale) | (scale == 0)] = 1.0
    standardized = (values - center) / scale
    first = int(np.argmin(np.sum(standardized**2, axis=1)))
    selected = [first]
    limit = min(int(requested), len(complete))
    while len(selected) < limit:
        distance = np.min(
            np.stack(
                [np.sum((standardized - standardized[index]) ** 2, axis=1) for index in selected],
                axis=1,
            ),
            axis=1,
        )
        distance[selected] = -np.inf
        selected.append(int(np.argmax(distance)))
    result = complete.iloc[selected].reset_index(drop=True)
    result.insert(0, "feature_complete", True)
    result.insert(0, "label", 1)
    result.insert(0, "reference_id", [f"AKS_POS_PROTO_{index + 1:02d}" for index in range(len(result))])
    return result


def multivariate_support(table: pd.DataFrame, bands: list[str]) -> dict[str, Any]:
    complete = table.loc[table["feature_complete"], bands].astype(float)
    if len(complete) < 2:
        raise ValueError("At least two complete reference rows are required for multivariate support")
    values = complete.to_numpy(dtype=float)
    center = np.median(values, axis=0)
    mad = np.median(np.abs(values - center), axis=0) * 1.4826
    fallback = np.std(values, axis=0, ddof=1)
    scale = np.where(np.isfinite(mad) & (mad > 0), mad, fallback)
    scale = np.where(np.isfinite(scale) & (scale > 0), scale, 1.0)
    standardized = (values - center) / scale
    _, singular, right = np.linalg.svd(standardized, full_matrices=False)
    eigenvalues = (singular**2) / max(len(complete) - 1, 1)
    keep = np.isfinite(eigenvalues) & (eigenvalues > np.finfo(float).eps)
    right = right[keep]
    eigenvalues = eigenvalues[keep]
    if not len(eigenvalues):
        raise ValueError("Multivariate support rank is zero")
    variance_ratio = eigenvalues / eigenvalues.sum()
    scores = standardized @ right.T
    squared_distance = np.sum((scores**2) / eigenvalues, axis=1)
    components = []
    for index, (eigenvalue, ratio, loading) in enumerate(zip(eigenvalues, variance_ratio, right)):
        components.append(
            {
                "id": f"PC{index + 1:02d}",
                "eigenvalue": float(eigenvalue),
                "explained_variance_ratio": float(ratio),
                "loadings": {band: float(value) for band, value in zip(bands, loading)},
            }
        )
    return {
        "status": "POSITIVE_CLASS_MULTIVARIATE_SUPPORT_ONLY",
        "not_binary_aoa": True,
        "method": "median_MAD_standardization_plus_full_rank_PCA_distance_v1",
        "n_complete_rows": int(len(complete)),
        "n_features": int(len(bands)),
        "rank": int(len(components)),
        "feature_order": list(bands),
        "robust_center": {band: float(value) for band, value in zip(bands, center)},
        "robust_scale": {band: float(value) for band, value in zip(bands, scale)},
        "components": components,
        "squared_distance_quantiles": {
            "p50": float(np.quantile(squared_distance, 0.50)),
            "p90": float(np.quantile(squared_distance, 0.90)),
            "p95": float(np.quantile(squared_distance, 0.95)),
            "p99": float(np.quantile(squared_distance, 0.99)),
            "max": float(np.max(squared_distance)),
        },
        "warning": "This describes AKS positives only and cannot define a sugarcane/non-sugarcane boundary.",
    }


def _same_optional_number(actual: Any, expected: Any) -> bool:
    if actual is None or expected is None:
        return actual is None and expected is None
    return bool(np.isclose(float(actual), float(expected), rtol=1e-10, atol=1e-12))


def validate_source_package(
    project: Path,
    contract: dict[str, Any],
    card: dict[str, Any],
    schema: dict[str, Any],
    domain: dict[str, Any],
    snapshot: dict[str, Any],
    raw: pd.DataFrame,
    required: dict[str, Path],
) -> list[str]:
    if project.name != contract.get("source_project"):
        raise ValueError("Project directory does not match the knowledge contract source_project")
    RULES.reject_mock_or_synthetic("source model card", card)
    RULES.reject_mock_or_synthetic("source feature domain", domain)
    RULES.reject_mock_or_synthetic("source extraction snapshot", snapshot)
    if card.get("artifact_type") != contract["artifact_semantics"]:
        raise ValueError("Source package is not positive_reference_only")
    if bool(card.get("binary_classifier_trained", False)):
        raise ValueError("A fitted classifier may not be ingested as positive-only knowledge")

    temporal_engine = project / "_NOI_BO" / "pipeline" / "sugarcane_temporal_features.py"
    bands = RULES.validate_extraction_snapshot(contract, schema, temporal_engine, snapshot)
    if len(bands) != 75:
        raise ValueError("AKS knowledge requires exactly 75 ordered predictors")
    expected_columns = [
        "reference_id",
        "lon",
        "lat",
        "label",
        "evaluation_eligible",
        "source_project",
        "label_basis",
        *bands,
        "feature_complete",
    ]
    if list(raw.columns) != expected_columns:
        missing = [column for column in expected_columns if column not in raw.columns]
        extra = [column for column in raw.columns if column not in expected_columns]
        raise ValueError(f"Raw feature columns/order changed; missing={missing}; extra={extra}")

    if not raw["reference_id"].astype(str).is_unique or raw["reference_id"].astype(str).str.strip().eq("").any():
        raise ValueError("Reference identifiers must be non-empty and unique")
    if not pd.to_numeric(raw["label"], errors="coerce").eq(1).all():
        raise ValueError("Knowledge source must contain positive labels only")
    evaluation = raw["evaluation_eligible"].map(parse_bool)
    if evaluation.any():
        raise ValueError("AKS reference rows must be ineligible for calibration/testing")
    if not raw["source_project"].astype(str).eq(contract["source_project"]).all():
        raise ValueError("Raw feature rows contain an unexpected source project")
    if raw["label_basis"].astype(str).str.strip().eq("").any():
        raise ValueError("Every reference row needs label_basis provenance")
    RULES.reject_mock_or_synthetic(
        "raw metadata",
        raw[["reference_id", "source_project", "label_basis"]].astype(str).to_dict(orient="list"),
    )
    lon = pd.to_numeric(raw["lon"], errors="coerce")
    lat = pd.to_numeric(raw["lat"], errors="coerce")
    if not np.isfinite(lon).all() or not np.isfinite(lat).all():
        raise ValueError("Raw local coordinate provenance contains non-finite values")
    if not lon.between(-180, 180).all() or not lat.between(-90, 90).all():
        raise ValueError("Raw local coordinate provenance is outside WGS84 bounds")

    numeric = raw[bands].apply(pd.to_numeric, errors="coerce")
    calculated_complete = numeric.notna().all(axis=1)
    declared_complete = raw["feature_complete"].map(parse_bool)
    if not calculated_complete.equals(declared_complete):
        raise ValueError("feature_complete does not match the exact 75 predictor values")
    complete_fraction = float(calculated_complete.mean()) if len(raw) else 0.0
    if complete_fraction < float(contract["minimum_feature_complete_fraction"]):
        raise ValueError("Complete-feature fraction is below the knowledge contract")

    reference_count = int(card.get("positive_reference", {}).get("n_points", -1))
    library = card.get("positive_feature_library", {})
    counts = {
        "raw": int(len(raw)),
        "reference": reference_count,
        "library_reference": int(library.get("n_reference_points", -1)),
        "library_sampled": int(library.get("n_sampled", -1)),
    }
    if min(counts.values()) <= 0 or len(set(counts.values())) != 1:
        raise ValueError(f"Source feature counts disagree: {counts}")
    if max(counts.values()) > int(contract["maximum_reference_points"]):
        raise ValueError("Reference point cap was exceeded")
    if int(library.get("n_complete", -1)) != int(calculated_complete.sum()):
        raise ValueError("Source complete-row count disagrees with model card")
    if not _same_optional_number(library.get("complete_fraction"), complete_fraction):
        raise ValueError("Source complete fraction disagrees with model card")
    if int(library.get("predictor_band_count", -1)) != len(bands):
        raise ValueError("Source predictor count disagrees with model card")
    if str(library.get("sha256", "")).lower() != sha256_file(required["positive_temporal_features.csv"]):
        raise ValueError("Source feature table hash disagrees with model card")

    if domain.get("status") != "POSITIVE_CLASS_DOMAIN_ONLY" or domain.get("not_binary_aoa") is not True:
        raise ValueError("Source feature domain semantics changed")
    if domain.get("schema_version") != contract["required_schema_version"]:
        raise ValueError("Source feature domain schema version changed")
    if domain.get("feature_schema_sha256") != sha256_file(required["feature_schema.json"]):
        raise ValueError("Source feature domain schema hash changed")
    if list(domain.get("features", {}).keys()) != bands:
        raise ValueError("Source feature-domain predictors/order changed")
    for band in bands:
        values = numeric[band].dropna()
        expected = {
            "n": int(len(values)),
            "p01": float(values.quantile(0.01)) if len(values) else None,
            "median": float(values.median()) if len(values) else None,
            "p99": float(values.quantile(0.99)) if len(values) else None,
        }
        observed = domain["features"][band]
        if int(observed.get("n", -1)) != expected["n"]:
            raise ValueError(f"Domain count mismatch for {band}")
        for statistic in ("p01", "median", "p99"):
            if not _same_optional_number(observed.get(statistic), expected[statistic]):
                raise ValueError(f"Domain {statistic} mismatch for {band}")
    return bands


def replace_output_atomically(staging: Path, output: Path) -> None:
    backup = output.with_name(output.name + ".previous-" + secrets.token_hex(6))
    moved_old = False
    try:
        if output.exists():
            os.replace(output, backup)
            moved_old = True
        os.replace(staging, output)
    except Exception:
        if moved_old and backup.exists() and not output.exists():
            os.replace(backup, output)
        raise
    finally:
        if backup.exists() and output.exists():
            shutil.rmtree(backup)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", required=True)
    parser.add_argument("--knowledge-dir", default="")
    args = parser.parse_args()

    project = Path(args.project_dir).resolve()
    repository = project.parents[1]
    contract_path = project / "_NOI_BO" / "config" / "positive_reference_knowledge_contract.json"
    contract = read_json(contract_path)
    private_root = (repository / "knowledge-private").resolve()
    output = (
        Path(args.knowledge_dir).resolve()
        if args.knowledge_dir
        else (repository / contract["private_package_relative_path"]).resolve()
    )
    if not inside(output, private_root):
        raise ValueError(f"Knowledge output must stay below {private_root}")
    RULES.assert_output_has_no_unexpected_entries(output, EXPECTED_OUTPUT_FILES)

    source = project / "_NOI_BO" / "work" / "field_area" / "reference_package"
    source_names = (
        "model_card.json",
        "feature_schema.json",
        "positive_temporal_features.csv",
        "positive_feature_domain.json",
        "extraction_contract_snapshot.json",
    )
    required = {name: source / name for name in source_names}
    missing = [str(path) for path in required.values() if not path.is_file()]
    if missing:
        raise FileNotFoundError("Reference feature package is incomplete: " + "; ".join(missing))

    card = read_json(required["model_card.json"])
    schema = read_json(required["feature_schema.json"])
    domain = read_json(required["positive_feature_domain.json"])
    snapshot = read_json(required["extraction_contract_snapshot.json"])
    raw = pd.read_csv(required["positive_temporal_features.csv"])
    bands = validate_source_package(project, contract, card, schema, domain, snapshot, raw, required)

    safe = raw[
        [
            "reference_id",
            "label",
            "evaluation_eligible",
            "source_project",
            "label_basis",
            "feature_complete",
            *bands,
        ]
    ].copy()
    safe["reference_id"] = [f"AKS_KNOW_{secrets.token_hex(16)}" for _ in range(len(safe))]
    if not safe["reference_id"].is_unique:
        raise RuntimeError("Generated private knowledge identifiers collided")
    safe["label"] = 1
    safe["evaluation_eligible"] = False
    safe[bands] = safe[bands].apply(pd.to_numeric, errors="coerce")
    safe["feature_complete"] = safe[bands].notna().all(axis=1)
    policy = contract["coordinate_policy"]
    RULES.audit_table_privacy(safe, policy, "sanitized feature table")

    prototypes = observed_prototypes(safe, bands, int(contract["prototype_count"]))
    knowledge_domain = json.loads(json.dumps(domain))
    knowledge_domain["multivariate_support"] = multivariate_support(safe, bands)
    safe_card = {
        "schema_version": card.get("schema_version"),
        "package_id": contract["package_id"],
        "artifact_type": "positive_reference_only",
        "source_project": contract["source_project"],
        "binary_classifier_trained": False,
        "transferable_validated_model": False,
        "coordinates_included": False,
        "geometry_included": False,
        "raw_identifiers_rekeyed": True,
        "direct_inference_allowed": False,
        "calibration_or_test_use_allowed": False,
        "training_augmentation_requires_local_positive_and_negative_labels": True,
        "n_reference_rows": int(len(safe)),
        "n_complete_rows": int(safe["feature_complete"].sum()),
        "n_features": int(len(bands)),
        "allowed_use": contract["allowed_use"],
        "prohibited_use": contract["prohibited_use"],
    }
    for label, value in (
        ("sanitized model card", safe_card),
        ("feature schema", schema),
        ("knowledge domain", knowledge_domain),
        ("extraction snapshot", snapshot),
    ):
        findings = RULES.privacy_findings(value, policy, label)
        if findings:
            raise ValueError("Privacy audit failed before write: " + "; ".join(findings[:20]))

    output.parent.mkdir(parents=True, exist_ok=True)
    staging = output.with_name(output.name + ".building-" + secrets.token_hex(8))
    staging.mkdir(parents=False, exist_ok=False)
    try:
        atomic_json(staging / "model_card.json", safe_card)
        atomic_json(staging / "feature_schema.json", schema)
        atomic_csv(staging / "positive_temporal_features.csv", safe)
        atomic_json(staging / "positive_feature_domain.json", knowledge_domain)
        atomic_csv(staging / "positive_feature_prototypes.csv", prototypes)
        atomic_json(staging / "extraction_contract_snapshot.json", snapshot)
        manifest = {
            "contract_version": contract["contract_version"],
            "created_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
            "package_id": contract["package_id"],
            "artifact_semantics": "positive_reference_only",
            "private_local_knowledge": True,
            "coordinates_included": False,
            "geometry_included": False,
            "raw_identifiers_rekeyed": True,
            "direct_inference_allowed": False,
            "calibration_or_test_use_allowed": False,
            "n_rows": int(len(safe)),
            "n_complete": int(safe["feature_complete"].sum()),
            "n_features": int(len(bands)),
            "n_prototypes": int(len(prototypes)),
            "multivariate_support_included": True,
            "source_hashes": {name: sha256_file(path) for name, path in required.items()},
            "output_hashes": {
                name: sha256_file(staging / name)
                for name in sorted(EXPECTED_OUTPUT_FILES - {"knowledge_manifest.json"})
            },
            "reuse_policy": "TRAIN_ONLY after exact schema, phenology, local-label and environmental-domain gates",
        }
        atomic_json(staging / "knowledge_manifest.json", manifest)
        RULES.audit_output_directory(staging, EXPECTED_OUTPUT_FILES, policy)
        replace_output_atomically(staging, output)
        RULES.audit_output_directory(output, EXPECTED_OUTPUT_FILES, policy)
    finally:
        if staging.exists():
            shutil.rmtree(staging)

    print(
        f"[OK] Private coordinate-free AKS knowledge: {manifest['n_complete']}/{manifest['n_rows']} "
        f"complete, {manifest['n_features']} exact features, {manifest['n_prototypes']} prototypes"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
