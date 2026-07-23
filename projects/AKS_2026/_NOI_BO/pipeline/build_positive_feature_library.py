#!/usr/bin/env python3
"""Extract the guarded 75-band AKS positive-class feature library.

This core intentionally refuses standalone execution.  The atomic consent gate
must provide an in-memory authorization context containing the exact validated
GeoDataFrame, count, hash, GEE project, temporal window and ordered band list.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import geopandas as gpd
import pandas as pd


AUTHORIZED_TRANSFER_CONTEXT: dict | None = None


def load_module(name: str, path: Path):
    specification = importlib.util.spec_from_file_location(name, path)
    if specification is None or specification.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(specification)
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve().parent
RULES = load_module("aks_positive_reference_contract_extractor", HERE / "positive_reference_contract.py")


def load_core(path: Path):
    return load_module("field_area_core_for_features", path)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_csv(path: Path, table: pd.DataFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    os.close(handle)
    temporary_path = Path(temporary)
    try:
        table.to_csv(temporary_path, index=False, encoding="utf-8", lineterminator="\n")
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def require_authorized_context(project: Path, reference_path: Path, references: gpd.GeoDataFrame) -> dict:
    context = AUTHORIZED_TRANSFER_CONTEXT
    if not isinstance(context, dict) or context.get("status") != "AUTHORIZED_IN_MEMORY_BY_ATOMIC_GATE":
        raise RuntimeError(
            "External transfer blocked: use 00_TAO_THU_VIEN_AKS_1000_DIEM_AN_TOAN.bat; "
            "the extractor cannot run directly"
        )
    if Path(context.get("project_dir", "")).resolve() != project:
        raise RuntimeError("Atomic authorization belongs to another project")
    if Path(context.get("reference_path", "")).resolve() != reference_path.resolve():
        raise RuntimeError("Atomic authorization belongs to another reference file")
    actual_hash = sha256_file(reference_path)
    if actual_hash != context.get("reference_sha256"):
        raise RuntimeError("Reference file changed after atomic authorization")
    guarded = context.get("guarded_file_hashes", {})
    if not isinstance(guarded, dict) or not guarded:
        raise RuntimeError("Atomic authorization is missing guarded file hashes")
    for relative, expected_hash in guarded.items():
        guarded_path = (project / relative).resolve()
        try:
            guarded_path.relative_to(project)
        except ValueError as error:
            raise RuntimeError("Guarded path escapes the authorized project") from error
        if not guarded_path.is_file() or sha256_file(guarded_path) != expected_hash:
            raise RuntimeError(f"Guarded input changed after atomic authorization: {relative}")
    actual_count = int(len(references))
    if actual_count != int(context.get("reference_count", -1)):
        raise RuntimeError("Reference count changed after atomic authorization")
    maximum = int(context.get("maximum_reference_points", -1))
    if maximum != 1000 or actual_count <= 0 or actual_count > maximum:
        raise RuntimeError("Atomic 1,000-point consent boundary is invalid")
    expected_bands = list(context.get("expected_predictor_bands", []))
    if len(expected_bands) != 75 or len(set(expected_bands)) != 75:
        raise RuntimeError("Atomic authorization does not contain the exact 75-band schema")
    return context


def materialize_authorized_rows(
    references: gpd.GeoDataFrame,
    by_identifier: dict[str, dict],
    bands: list[str],
    local_coordinates: dict[str, tuple[float, float]],
) -> tuple[pd.DataFrame, list[str]]:
    """Keep every authorized reference; represent GEE-masked rows as NA, never zero."""
    expected_ids = references["reference_id"].astype(str).tolist()
    unexpected = sorted(set(by_identifier).difference(expected_ids))
    if unexpected:
        raise RuntimeError(f"GEE returned unauthorized reference identifiers: {unexpected[:3]}")
    missing_ids = sorted(set(expected_ids).difference(by_identifier))
    metadata = references.set_index("reference_id", drop=False)
    rows: list[dict] = []
    for identifier in expected_ids:
        if identifier in by_identifier:
            row = dict(by_identifier[identifier])
        else:
            source = metadata.loc[identifier]
            lon, lat = local_coordinates[identifier]
            row = {
                "reference_id": identifier,
                "lon": lon,
                "lat": lat,
                "label": 1,
                "evaluation_eligible": False,
                "source_project": source.get("source_project", "AKS_2026"),
                "label_basis": source.get("label_basis", "inside_confirmed_field_area"),
                **{band: None for band in bands},
            }
        rows.append(row)
    table = pd.DataFrame(rows)
    table[bands] = table[bands].apply(pd.to_numeric, errors="coerce")
    table["feature_complete"] = table[bands].notna().all(axis=1)
    return table, missing_ids


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", required=True)
    args = parser.parse_args()
    project = Path(args.project_dir).resolve()
    internal = project / "_NOI_BO"
    core = load_core(internal / "pipeline" / "interpret_sugarcane_area.py")
    paths = core.ProjectPaths.from_project(project)
    config, config_path = core.config_for(paths)
    package = paths.work / "reference_package"
    reference_path = package / "positive_reference.geojson"
    card_path = package / "model_card.json"
    schema_path = package / "feature_schema.json"
    contract_path = internal / "config" / "positive_reference_knowledge_contract.json"
    temporal_engine = internal / "pipeline" / "sugarcane_temporal_features.py"
    for path in (reference_path, card_path, schema_path, contract_path, temporal_engine):
        if not path.is_file():
            raise FileNotFoundError(f"Guarded reference input is missing: {path}")

    card = json.loads(card_path.read_text(encoding="utf-8"))
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    RULES.reject_mock_or_synthetic("source model card", card)
    if card.get("artifact_type") != "positive_reference_only":
        raise ValueError("This extractor is restricted to a positive_reference_only package")
    if bool(card.get("binary_classifier_trained", False)):
        raise ValueError("A fitted classifier cannot enter positive-only extraction")

    references = gpd.read_file(reference_path).to_crs(4326)
    context = require_authorized_context(project, reference_path, references)
    feature_gate = RULES.validate_feature_schema(contract, schema, temporal_engine)
    if feature_gate["predictor_bands"] != context["expected_predictor_bands"]:
        raise RuntimeError("Schema changed after atomic authorization")
    config.update(context["runtime_overrides"])
    if str(config.get("gee_project_id", "")).strip() != context["gee_project_id"]:
        raise RuntimeError("GEE project changed after atomic authorization")

    references = references.copy()
    references["reference_id"] = [f"AKS_POS_{index + 1:04d}" for index in range(len(references))]
    references["label"] = 1
    references["evaluation_eligible"] = False
    local_coordinates = {
        row.reference_id: (float(row.geometry.x), float(row.geometry.y))
        for row in references[["reference_id", "geometry"]].itertuples(index=False)
    }
    transfer_columns = [
        "reference_id",
        "label",
        "evaluation_eligible",
        "source_project",
        "label_basis",
        "geometry",
    ]
    transfer = references[transfer_columns].copy()

    # No Earth Engine import, initialization or private geometry conversion occurs
    # before every atomic and exact-feature contract check above has passed.
    import ee

    ee.Initialize(project=context["gee_project_id"])
    reference_fc = core.gdf_to_ee(transfer)
    extraction_bounds = reference_fc.geometry().bounds()
    stack, bands, scene_counts = core.gee_feature_stack(config, extraction_bounds)
    if list(bands) != context["expected_predictor_bands"]:
        raise RuntimeError("Runtime GEE stack does not match the authorized 75-band order")
    snapshot = RULES.build_extraction_snapshot(
        contract,
        schema,
        temporal_engine,
        list(bands),
        {key: config[key] for key in context["runtime_overrides"]},
        scene_counts,
    )

    sampled = stack.sampleRegions(
        collection=reference_fc,
        properties=["reference_id", "label", "evaluation_eligible", "source_project", "label_basis"],
        scale=int(config["resolution_m"]),
        geometries=False,
        tileScale=8,
    )
    payload = sampled.getInfo()
    by_identifier: dict[str, dict] = {}
    for feature in payload.get("features", []):
        props = feature.get("properties", {})
        identifier = str(props.get("reference_id", ""))
        if identifier not in local_coordinates:
            raise RuntimeError(f"GEE returned an unknown reference identifier: {identifier!r}")
        if identifier in by_identifier:
            raise RuntimeError(f"GEE returned a duplicate reference identifier: {identifier}")
        lon, lat = local_coordinates[identifier]
        row = {
            "reference_id": identifier,
            "lon": lon,
            "lat": lat,
            "label": 1,
            "evaluation_eligible": False,
            "source_project": props.get("source_project", project.name),
            "label_basis": props.get("label_basis", "inside_confirmed_field_area"),
        }
        for band in bands:
            row[band] = props.get(band)
        by_identifier[identifier] = row

    table, missing_ids = materialize_authorized_rows(
        references,
        by_identifier,
        list(bands),
        local_coordinates,
    )
    complete = table["feature_complete"]
    complete_fraction = float(complete.mean()) if len(complete) else 0.0
    minimum_complete = float(contract.get("minimum_feature_complete_fraction", 1.0))
    if complete_fraction < minimum_complete:
        raise RuntimeError(
            f"Only {complete_fraction:.1%} references have all 75 predictors; required {minimum_complete:.1%}"
        )

    output_path = package / "positive_temporal_features.csv"
    atomic_csv(output_path, table)
    summaries = {}
    for band in bands:
        values = pd.to_numeric(table[band], errors="coerce").dropna()
        summaries[band] = {
            "n": int(len(values)),
            "p01": float(values.quantile(0.01)) if len(values) else None,
            "median": float(values.median()) if len(values) else None,
            "p99": float(values.quantile(0.99)) if len(values) else None,
        }
    domain_path = package / "positive_feature_domain.json"
    domain = {
        "schema_version": core.SCHEMA_VERSION,
        "status": "POSITIVE_CLASS_DOMAIN_ONLY",
        "not_binary_aoa": True,
        "feature_schema_sha256": sha256_file(schema_path),
        "feature_schema_semantic_sha256": feature_gate["feature_schema_semantic_sha256"],
        "target_year": int(config["target_year"]),
        "scene_counts": scene_counts,
        "features": summaries,
        "n_authorized_references": int(len(references)),
        "n_masked_or_unsampled": int(len(missing_ids)),
        "missing_predictor_policy": "NA; never filled with zero",
    }
    snapshot_path = package / "extraction_contract_snapshot.json"
    core.write_json(domain_path, domain)
    core.write_json(snapshot_path, snapshot)

    card["positive_feature_library"] = {
        "status": "POSITIVE_CLASS_TEMPORAL_FEATURES_EXTRACTED_EXACT_CONTRACT",
        "path": str(output_path.resolve()),
        "sha256": sha256_file(output_path),
        "n_reference_points": int(len(references)),
        "n_sampled": int(len(table)),
        "n_complete": int(complete.sum()),
        "complete_fraction": complete_fraction,
        "predictor_band_count": len(bands),
        "feature_schema_semantic_sha256": feature_gate["feature_schema_semantic_sha256"],
        "target_year": int(config["target_year"]),
        "scene_counts": scene_counts,
        "evaluation_eligible": False,
        "binary_classifier_trained": False,
        "warning": "Positive features alone cannot estimate a sugarcane/non-sugarcane decision boundary.",
    }
    core.write_json(card_path, card)
    qa = {
        "schema_version": core.SCHEMA_VERSION,
        "created_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "status": "POSITIVE_FEATURE_LIBRARY_READY_EXACT_CONTRACT",
        "artifact_semantics": "positive_reference_only",
        "binary_classifier_trained": False,
        "transferable_validated_model": False,
        "input_reference_sha256": sha256_file(reference_path),
        "config_sha256": sha256_file(config_path),
        "feature_table_sha256": sha256_file(output_path),
        "extraction_contract_snapshot_sha256": sha256_file(snapshot_path),
        "n_reference_points": int(len(references)),
        "n_rows": int(len(table)),
        "n_complete": int(complete.sum()),
        "n_masked_or_unsampled": int(len(missing_ids)),
        "missing_predictor_policy": "NA; never filled with zero",
        "complete_fraction": complete_fraction,
        "predictor_band_count": len(bands),
        "scene_counts": scene_counts,
        "next_requirement": "verified local non-sugarcane and sugarcane labels in the new project",
    }
    core.write_json(paths.result / "positive_feature_library_QA.json", qa)
    print(
        f"[OK] Positive temporal feature library: {qa['n_complete']}/{qa['n_rows']} complete, "
        "75 exact predictors, no binary classifier trained"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
