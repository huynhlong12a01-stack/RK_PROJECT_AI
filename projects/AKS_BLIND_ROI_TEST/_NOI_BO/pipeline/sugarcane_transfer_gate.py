#!/usr/bin/env python3
"""Model/reference transfer and environmental-domain gates for crop mapping."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import pandas as pd


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def compare_feature_schema(source: dict[str, Any], target: dict[str, Any]) -> dict[str, Any]:
    checks = {
        "method_id": source.get("method_id") == target.get("method_id"),
        "s2_collection": source.get("sentinel_2", {}).get("collection")
        == target.get("sentinel_2", {}).get("collection"),
        "s2_quality_collection": source.get("sentinel_2", {}).get("quality_collection")
        == target.get("sentinel_2", {}).get("quality_collection"),
        "s1_collection": source.get("sentinel_1", {}).get("collection")
        == target.get("sentinel_1", {}).get("collection"),
        "s1_unit": source.get("sentinel_1", {}).get("input_unit")
        == target.get("sentinel_1", {}).get("input_unit") == "dB",
        "s1_no_extra_log": source.get("sentinel_1", {}).get("additional_log_transform") is False
        and target.get("sentinel_1", {}).get("additional_log_transform") is False,
        "period_definition": source.get("temporal", {}).get("period_definition")
        == target.get("temporal", {}).get("period_definition"),
        "relative_period_count": source.get("temporal", {}).get("n_periods")
        == target.get("temporal", {}).get("n_periods"),
        "missing_data_policy": source.get("missing_data_policy") == target.get("missing_data_policy"),
    }
    return {"checks": checks, "pass": all(checks.values())}


def evaluate_transfer(
    source_card: dict[str, Any],
    source_schema: dict[str, Any],
    target_schema: dict[str, Any],
    target_has_local_positive: bool,
    target_has_local_negative: bool,
    target_phenology_confirmed: bool,
) -> dict[str, Any]:
    schema = compare_feature_schema(source_schema, target_schema)
    artifact_type = source_card.get("artifact_type")
    if artifact_type == "positive_reference_only":
        allowed = schema["pass"] and target_has_local_positive and target_has_local_negative and target_phenology_confirmed
        return {
            "source_artifact_type": artifact_type,
            "direct_inference_allowed": False,
            "training_augmentation_allowed": allowed,
            "source_rows_evaluation_eligible": False,
            "schema_gate": schema,
            "status": "TRAINING_AUGMENTATION_ONLY" if allowed else "BLOCKED_LOCAL_LABEL_OR_SCHEMA_GATE",
            "reason": (
                "Positive references may enter training only after re-confirmation; they cannot enter threshold/test folds."
            ),
        }
    classifier = bool(source_card.get("binary_classifier_trained"))
    local_validation = source_card.get("model_status") == "LOCALLY_SPATIAL_HOLDOUT_PASSED"
    allowed = (
        classifier
        and local_validation
        and schema["pass"]
        and target_has_local_positive
        and target_has_local_negative
        and target_phenology_confirmed
    )
    return {
        "source_artifact_type": artifact_type or "binary_model_package",
        "direct_inference_allowed": False,
        "training_augmentation_allowed": allowed,
        "source_rows_evaluation_eligible": False,
        "schema_gate": schema,
        "status": "RETRAIN_WITH_LOCAL_OUTER_TEST" if allowed else "BLOCKED_LOCAL_LABEL_OR_SCHEMA_GATE",
        "reason": "Cross-region direct inference is not authorized; retrain and assess on local spatial holdout data.",
    }


def environmental_range_fraction(
    table: pd.DataFrame, domain: dict[str, Any]
) -> tuple[pd.Series, list[str]]:
    """Fraction of available predictors within source p01-p99 bounds.

    This is a transparent range diagnostic, not a calibrated Area of
    Applicability distance.  For positive-only sources it describes similarity
    to known positives and must never be reported as binary-model AOA.
    """
    usable = []
    flags = []
    for name, stats in domain.get("features", {}).items():
        if name not in table.columns or stats.get("p01") is None or stats.get("p99") is None:
            continue
        values = pd.to_numeric(table[name], errors="coerce")
        usable.append(name)
        flags.append(values.between(float(stats["p01"]), float(stats["p99"]), inclusive="both"))
    if not flags:
        return pd.Series([float("nan")] * len(table), index=table.index), []
    matrix = pd.concat(flags, axis=1)
    return matrix.mean(axis=1), usable


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-card", required=True)
    parser.add_argument("--source-schema", required=True)
    parser.add_argument("--target-schema", required=True)
    args = parser.parse_args()
    result = evaluate_transfer(
        read_json(Path(args.source_card)),
        read_json(Path(args.source_schema)),
        read_json(Path(args.target_schema)),
        target_has_local_positive=False,
        target_has_local_negative=False,
        target_phenology_confirmed=False,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["training_augmentation_allowed"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
