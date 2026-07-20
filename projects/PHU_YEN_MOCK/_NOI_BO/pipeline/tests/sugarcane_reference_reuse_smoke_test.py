#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import sys
import contextlib
from pathlib import Path

import pandas as pd


SCRIPT = Path(__file__).resolve().parents[1] / "sugarcane_reference_reuse.py"
SPEC = importlib.util.spec_from_file_location("reference_reuse", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def schema():
    return {
        "method_id": "m",
        "sentinel_2": {"collection": "s2", "quality_collection": "cs"},
        "sentinel_1": {"collection": "s1", "input_unit": "dB", "additional_log_transform": False},
        "temporal": {"period_definition": "rolling_complete_calendar_quarters", "n_periods": 8},
        "missing_data_policy": "masked",
    }


test_tmp = Path.cwd() / ".tmp"
test_tmp.mkdir(parents=True, exist_ok=True)
test_root = test_tmp / "reference_reuse_smoke"
test_root.mkdir(parents=True, exist_ok=True)
with contextlib.nullcontext(str(test_root)) as raw:
    package = Path(raw)
    (package / "model_card.json").write_text(
        json.dumps({"artifact_type": "positive_reference_only", "binary_classifier_trained": False}), encoding="utf-8"
    )
    (package / "feature_schema.json").write_text(json.dumps(schema()), encoding="utf-8")
    pd.DataFrame(
        {
            "reference_id": ["R1", "R2"],
            "F1": [0.25, 0.75],
            "F2": [10.0, 20.0],
            "feature_complete": [True, True],
        }
    ).to_csv(package / "positive_temporal_features.csv", index=False)
    (package / "positive_feature_domain.json").write_text(
        json.dumps(
            {
                "not_binary_aoa": True,
                "features": {
                    "F1": {"p01": 0.2, "p99": 0.8},
                    "F2": {"p01": 9.0, "p99": 21.0},
                },
            }
        ),
        encoding="utf-8",
    )
    ready = MODULE.reference_reuse_preflight(package, schema(), True, True, True)
    assert ready["training_augmentation_allowed"] is True
    assert ready["direct_inference_allowed"] is False
    rows = MODULE.sanitized_train_only_rows(package, ["F1", "F2"])
    assert (rows["spatial_fold"] == -1).all()
    assert not rows["evaluation_eligible"].any()
    assert set(rows["reference_role"]) == {"TRAIN_ONLY_EXTERNAL_REFERENCE"}
    domain = MODULE.target_domain_gate(pd.DataFrame({"F1": [0.3, 0.7], "F2": [11.0, 19.0]}), package)
    assert domain["pass"] is True and domain["not_binary_model_aoa"] is True

print("[OK] sugarcane reference reuse smoke test passed")
