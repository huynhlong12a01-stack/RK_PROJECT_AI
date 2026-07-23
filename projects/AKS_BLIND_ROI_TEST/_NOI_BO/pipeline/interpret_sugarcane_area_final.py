#!/usr/bin/env python3
"""Final entry point for the gated sugarcane field-area workflow.

This entry point replaces calendar-year features with rolling completed
quarters, normalizes the feature schema, enforces crop-calendar confirmation,
and blocks a requested reference reuse unless its TRAIN-only package passes the
source/schema/local-label gates.  The core engine keeps calibration and outer
test folds local.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


TEMPORAL = load("sugarcane_temporal_final", HERE / "sugarcane_temporal_features.py")
REUSE = load("sugarcane_reference_reuse_final", HERE / "sugarcane_reference_reuse.py")
POSITIVE_SCREEN = load("sugarcane_positive_screen_final", HERE / "positive_only_screening.py")
CORE = load("sugarcane_field_area_core_final", HERE / "interpret_sugarcane_area.py")
CORE.DEFAULTS.update(
    {
        "feature_end_date_exclusive": "",
        "temporal_quarters": 8,
        "phenology_alignment_confirmed": False,
        "crop_calendar_source": "",
        "crop_calendar_note": "",
        "allow_positive_only_screening": False,
        "positive_screening_min_points": 30,
        "positive_screening_min_complete_fraction": 0.80,
        "positive_screening_prototypes": 12,
        "positive_screening_distance_quantile": 0.95,
    }
)
CORE.METHOD_ID = "sentinel1_sentinel2_rolling_temporal_random_forest_spatial_holdout_v2"
CORE.gee_feature_stack = TEMPORAL.build_temporal_stack
_original_schema = CORE.feature_schema_for
_original_supervised = CORE.run_supervised


def feature_schema(config):
    schema = _original_schema(config)
    legacy_year = schema.pop("target_year", None)
    schema.pop("temporal_window", None)
    _, temporal = TEMPORAL.rolling_periods(config)
    schema["method_id"] = "sentinel1_sentinel2_rolling_temporal_random_forest_spatial_holdout_v2"
    schema["reference_extraction_configuration_year"] = legacy_year
    schema["temporal"] = temporal
    schema["sentinel_2"]["period_features"] = schema["sentinel_2"].pop("quarterly_features", [])
    schema["sentinel_1"]["period_features"] = schema["sentinel_1"].pop("quarterly_features", [])
    schema["phenology_alignment"] = TEMPORAL.phenology_gate(config)
    return schema


def blocked(paths, status, **details):
    qa = {
        "schema_version": CORE.SCHEMA_VERSION,
        "created_utc": CORE.utc_now(),
        "status": status,
        **details,
    }
    CORE.write_json(paths.result / "field_area_QA.json", qa)
    return qa


def run_supervised(paths, roi_path, label_path, config, config_path, preflight_only):
    _, temporal = TEMPORAL.rolling_periods(config)
    phenology = TEMPORAL.phenology_gate(config)
    if not phenology["pass"]:
        return blocked(
            paths,
            "BLOCKED_PHENOLOGY_ALIGNMENT_NOT_CONFIRMED",
            phenology_alignment=phenology,
            temporal_provenance=temporal,
            required_action="Confirm the local crop calendar and document crop_calendar_source.",
        )
    labels = CORE.read_labels(
        Path(label_path),
        int(config["crs_epsg"]),
        float(config["spatial_block_m"]),
        int(config["spatial_folds"]),
        int(config["random_seed"]),
    )
    local_classes = set(labels["label"].unique())
    if local_classes == {1} and bool(config.get("allow_positive_only_screening", False)):
        if bool(config.get("reuse_reference_positive", False)):
            return blocked(
                paths,
                "BLOCKED_REFERENCE_DIRECT_SCREENING_PROHIBITED",
                direct_inference_allowed=False,
                required_action="Use only local positive observations for positive-only screening.",
            )
        return POSITIVE_SCREEN.run(
            CORE,
            paths,
            Path(roi_path),
            Path(label_path),
            labels,
            config,
            config_path,
            preflight_only,
        )
    if bool(config.get("reuse_reference_positive", False)):
        package = str(config.get("reference_package", "")).strip()
        if not package:
            return blocked(
                paths,
                "BLOCKED_REFERENCE_PACKAGE_PATH_REQUIRED",
                direct_inference_allowed=False,
                required_role="TRAIN_ONLY_EXTERNAL_REFERENCE",
            )

        transfer = REUSE.reference_reuse_preflight(
            package,
            feature_schema(config),
            1 in local_classes,
            0 in local_classes,
            phenology["pass"],
        )
        if not transfer.get("training_augmentation_allowed", False):
            return blocked(
                paths,
                transfer.get("status", "BLOCKED_REFERENCE_REUSE_GATE"),
                reference_reuse=transfer,
                direct_inference_allowed=False,
            )
        # The core's integration contract merges sanitized rows into TRAIN only.
        # A ready package is recorded here; calibration/test rows remain local.
        config["_reference_reuse_preflight"] = transfer
    return _original_supervised(paths, roi_path, label_path, config, config_path, preflight_only)


CORE.feature_schema_for = feature_schema
CORE.run_supervised = run_supervised


if __name__ == "__main__":
    raise SystemExit(CORE.main())
