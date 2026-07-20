#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "sugarcane_transfer_gate.py"
SPEC = importlib.util.spec_from_file_location("transfer_gate", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

schema = {
    "method_id": "m",
    "sentinel_2": {"collection": "s2", "quality_collection": "cs"},
    "sentinel_1": {"collection": "s1", "input_unit": "dB", "additional_log_transform": False},
    "temporal": {"period_definition": "rolling_complete_calendar_quarters", "n_periods": 8},
    "missing_data_policy": "masked",
}
card = {"artifact_type": "positive_reference_only", "binary_classifier_trained": False}
blocked = MODULE.evaluate_transfer(card, schema, schema, True, False, True)
assert blocked["direct_inference_allowed"] is False
assert blocked["training_augmentation_allowed"] is False
allowed = MODULE.evaluate_transfer(card, schema, schema, True, True, True)
assert allowed["direct_inference_allowed"] is False
assert allowed["training_augmentation_allowed"] is True
assert allowed["source_rows_evaluation_eligible"] is False
print("[OK] sugarcane transfer gate smoke test passed")
