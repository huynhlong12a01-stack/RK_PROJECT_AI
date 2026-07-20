"""Apply project-local, deterministic settings for the PHU_YEN_MOCK fixture."""

from __future__ import annotations

import json
import re
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
SAMPLING = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO" / "sampling.yml"
INTERPRETATION = PROJECT / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO" / "interpretation.yml"
MANIFEST = PROJECT / "MOCK_RUN_MANIFEST.json"


def set_scalar(text: str, name: str, value: str) -> str:
    pattern = rf"(?m)^(\s*{re.escape(name)}\s*:\s*).*$"
    updated, count = re.subn(pattern, rf"\g<1>{value}", text)
    if count != 1:
        raise ValueError(f"Expected exactly one {name} setting, found {count}")
    return updated


def main() -> None:
    sampling = SAMPLING.read_text(encoding="utf-8")
    for name, value in {
        "resolution_m": "30",
        "start_date": '"2025-01-01"',
        "end_date": '"2026-01-01"',
        "random_seed": "20260715",
    }.items():
        sampling = set_scalar(sampling, name, value)
    SAMPLING.write_text(sampling, encoding="utf-8")

    interpretation = INTERPRETATION.read_text(encoding="utf-8")
    for name, value in {
        "mode": "provided",
        "resolution_m": "30",
        "feature_end_date_exclusive": '"2026-01-01"',
        "crop_calendar_note": '"MOCK ONLY: classification bypassed; no local calendar validation."',
    }.items():
        interpretation = set_scalar(interpretation, name, value)
    INTERPRETATION.write_text(interpretation, encoding="utf-8")

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    manifest["configuration_applied"] = True
    MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("PHU_YEN_MOCK configuration applied: 30 m, full calendar year 2025.")


if __name__ == "__main__":
    main()
