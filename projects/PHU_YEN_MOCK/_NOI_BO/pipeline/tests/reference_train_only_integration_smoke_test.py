#!/usr/bin/env python3
"""Guard against external reference leakage into calibration/test folds."""

from pathlib import Path


CORE = Path(__file__).resolve().parents[1] / "interpret_sugarcane_area.py"
text = CORE.read_text(encoding="utf-8")
assert "train_samples = train_samples.merge(external_train_only_fc)" in text
assert "final_training = final_training.merge(external_train_only_fc)" in text
assert "calibration_samples = calibration_samples.merge" not in text
assert "test_samples = test_samples.merge" not in text
assert '"calibration_or_test_use_allowed": False' in text
assert '"merge_role": "TRAIN_ONLY_EXTERNAL_REFERENCE"' in text
assert '"reference_reuse": reference_reuse_qa' in text
print("[OK] reference integration is TRAIN-only; calibration/test remain local")
