#!/usr/bin/env python3
"""Prepare cross-project sugarcane references for TRAIN-ONLY augmentation.

The module never authorizes direct inference.  It checks source semantics,
feature schema, local labels, phenology alignment and environmental similarity,
then returns sanitized feature rows with an immutable TRAIN_ONLY role.  The
caller must merge these rows only into the training FeatureCollection after the
local calibration/test folds have been separated.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd


HERE = Path(__file__).resolve().parent


def load_transfer_module():
    path = HERE / "sugarcane_transfer_gate.py"
    spec = importlib.util.spec_from_file_location("sugarcane_transfer_for_reuse", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


TRANSFER = load_transfer_module()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_package(path_value: str | Path) -> Path:
    package = Path(path_value).expanduser().resolve()
    required = [
        package / "model_card.json",
        package / "feature_schema.json",
        package / "positive_temporal_features.csv",
        package / "positive_feature_domain.json",
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError("Reference package is incomplete: " + "; ".join(missing))
    return package


def reference_reuse_preflight(
    package_path: str | Path,
    target_schema: dict[str, Any],
    target_has_local_positive: bool,
    target_has_local_negative: bool,
    target_phenology_confirmed: bool,
) -> dict[str, Any]:
    try:
        package = resolve_package(package_path)
    except (FileNotFoundError, ValueError) as exc:
        return {
            "status": "BLOCKED_REFERENCE_PACKAGE_INCOMPLETE",
            "training_augmentation_allowed": False,
            "direct_inference_allowed": False,
            "reason": str(exc),
        }
    card = read_json(package / "model_card.json")
    schema = read_json(package / "feature_schema.json")
    transfer = TRANSFER.evaluate_transfer(
        card,
        schema,
        target_schema,
        target_has_local_positive,
        target_has_local_negative,
        target_phenology_confirmed,
    )
    result = {
        **transfer,
        "package": str(package),
        "package_hashes": {
            name: sha256_file(package / name)
            for name in (
                "model_card.json",
                "feature_schema.json",
                "positive_temporal_features.csv",
                "positive_feature_domain.json",
            )
        },
        "required_merge_role": "TRAIN_ONLY_EXTERNAL_REFERENCE",
        "calibration_or_test_use_allowed": False,
    }
    return result


def target_domain_gate(
    target_local_training_features: pd.DataFrame,
    package_path: str | Path,
    minimum_row_fraction: float = 0.80,
    minimum_predictor_fraction: float = 0.90,
) -> dict[str, Any]:
    package = resolve_package(package_path)
    domain = read_json(package / "positive_feature_domain.json")
    fractions, predictors = TRANSFER.environmental_range_fraction(target_local_training_features, domain)
    valid = fractions.dropna()
    if not predictors or valid.empty:
        return {
            "status": "BLOCKED_DOMAIN_NOT_COMPUTABLE",
            "pass": False,
            "reason": "No common predictors with a finite positive-reference domain.",
        }
    row_pass = valid >= minimum_predictor_fraction
    row_fraction = float(row_pass.mean())
    return {
        "status": "PASS" if row_fraction >= minimum_row_fraction else "BLOCKED_ENVIRONMENTAL_DOMAIN_MISMATCH",
        "pass": row_fraction >= minimum_row_fraction,
        "diagnostic_type": "fraction_of_predictors_inside_source_positive_p01_p99",
        "not_binary_model_aoa": bool(domain.get("not_binary_aoa", False)),
        "n_target_rows": int(len(valid)),
        "n_common_predictors": int(len(predictors)),
        "minimum_predictor_fraction_per_row": minimum_predictor_fraction,
        "minimum_passing_row_fraction": minimum_row_fraction,
        "observed_passing_row_fraction": row_fraction,
        "median_feature_range_fraction": float(valid.median()),
    }


def sanitized_train_only_rows(package_path: str | Path, bands: list[str]) -> pd.DataFrame:
    package = resolve_package(package_path)
    table = pd.read_csv(package / "positive_temporal_features.csv")
    missing = [band for band in bands if band not in table.columns]
    if missing:
        raise ValueError("Reference feature table missing model bands: " + ", ".join(missing))
    table = table[table.get("feature_complete", True).astype(bool)].copy()
    numeric = table[bands].apply(pd.to_numeric, errors="coerce")
    keep = numeric.notna().all(axis=1)
    table = table.loc[keep].copy()
    table[bands] = numeric.loc[keep]
    table["label"] = 1
    table["spatial_fold"] = -1
    table["evaluation_eligible"] = False
    table["reference_role"] = "TRAIN_ONLY_EXTERNAL_REFERENCE"
    return table[["reference_id", "label", "spatial_fold", "evaluation_eligible", "reference_role", *bands]]


def dataframe_to_ee_train_only(table: pd.DataFrame, bands: list[str]) -> Any:
    import ee

    required = {"label", "spatial_fold", "evaluation_eligible", "reference_role", *bands}
    missing = required - set(table.columns)
    if missing:
        raise ValueError(f"TRAIN_ONLY reference rows missing: {sorted(missing)}")
    if (table["spatial_fold"] != -1).any() or table["evaluation_eligible"].astype(bool).any():
        raise ValueError("External reference rows may not be evaluation eligible or assigned a local fold")
    features = []
    for row in table.to_dict(orient="records"):
        props = {key: (value.item() if hasattr(value, "item") else value) for key, value in row.items()}
        features.append(ee.Feature(None, props))
    return ee.FeatureCollection(features)


def integration_contract() -> dict[str, Any]:
    return {
        "insertion_point": "after local stack.sampleRegions and after calibration/test folds are separated",
        "allowed_operation": "train_samples = train_samples.merge(external_train_only_fc)",
        "prohibited_operations": [
            "merge external rows into samples before fold separation",
            "merge external rows into calibration_samples",
            "merge external rows into test_samples",
            "report external references as independent validation",
            "use positive-reference domain diagnostic as binary classifier AOA",
        ],
    }
