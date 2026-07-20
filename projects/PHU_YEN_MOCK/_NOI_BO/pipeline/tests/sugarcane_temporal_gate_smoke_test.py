#!/usr/bin/env python3

from datetime import date
import importlib.util
import sys
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "sugarcane_temporal_features.py"
SPEC = importlib.util.spec_from_file_location("temporal_gate", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

periods, provenance = MODULE.rolling_periods(
    {"feature_end_date_exclusive": "2026-07-01", "temporal_quarters": 8}, date(2026, 7, 14)
)
assert periods[0] == {"id": "T01", "start": "2024-07-01", "end_exclusive": "2024-10-01"}
assert periods[-1] == {"id": "T08", "start": "2026-04-01", "end_exclusive": "2026-07-01"}
assert provenance["future_or_partial_periods_included"] is False
try:
    MODULE.rolling_periods(
        {"feature_end_date_exclusive": "2026-10-01", "temporal_quarters": 8}, date(2026, 7, 14)
    )
except ValueError as exc:
    assert "future/incomplete" in str(exc)
else:
    raise AssertionError("Future quarter was not blocked")
assert MODULE.phenology_gate({"phenology_alignment_confirmed": False})["pass"] is False
assert MODULE.phenology_gate(
    {"phenology_alignment_confirmed": True, "crop_calendar_source": "local agronomy record"}
)["pass"] is True
print("[OK] sugarcane temporal/phenology gates passed")
