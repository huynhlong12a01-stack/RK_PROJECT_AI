#!/usr/bin/env python3
"""Ensure missing predictor support is not converted to non-cane."""

from pathlib import Path


CORE = Path(__file__).resolve().parents[1] / "interpret_sugarcane_area.py"
text = CORE.read_text(encoding="utf-8")
candidate_block = text.split("candidate = (", 1)[1].split("probability_path =", 1)[0]
assert ".unmask(0)" not in candidate_block
assert '.rename("cane_candidate")' in candidate_block
assert '"candidate_missing_predictors_preserved_as_nodata": True' in text
assert '"performed_after_outer_assessment": True' in text
assert '"uses_all_local_labels": True' in text
polygon_block = text.split("def polygonize_candidate", 1)[1].split("def run_supervised", 1)[0]
assert "valid = values == 1" in polygon_block
assert "if int(value) == 1" in polygon_block
print("[OK] candidate nodata and final-refit provenance guards passed")
