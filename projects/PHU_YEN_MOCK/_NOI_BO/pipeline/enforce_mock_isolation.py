"""Block reference export and stamp synthetic model/reference packages."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
INTERNAL = PROJECT / "_NOI_BO"
BLOCKER = INTERNAL / "run_positive_reference_features_safe.ps1"
MANIFEST = PROJECT / "MOCK_RUN_MANIFEST.json"
CONTRACT = PROJECT / "MOCK_CONTRACT.json"


def card() -> dict[str, object]:
    return {
        "schema_version": 1,
        "project_id": "PHU_YEN_MOCK",
        "created_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "mock_only": True,
        "synthetic_fixture": True,
        "training_eligible": False,
        "evaluation_eligible": False,
        "reuse_eligible": False,
        "knowledge_integration_eligible": False,
        "direct_external_transfer": False,
        "transferable_validated_model": False,
        "scientific_reason": (
            "Synthetic field geometry, labels and laboratory values are software-test "
            "fixtures and cannot constitute training, validation or transfer evidence."
        ),
    }


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if contract.get("non_operational") is not True:
        raise ValueError("Mock contract safety flag is missing")
    blocker = """$ErrorActionPreference = 'Stop'
[Console]::Error.WriteLine('BLOCKED: PHU_YEN_MOCK is synthetic and cannot create/export a reference or knowledge package.')
exit 2
"""
    BLOCKER.write_text(blocker, encoding="utf-8")
    for package in (
        INTERNAL / "work" / "field_area" / "reference_package",
        INTERNAL / "work" / "model_package",
    ):
        package.mkdir(parents=True, exist_ok=True)
        (package / "model_card.json").write_text(
            json.dumps(card(), ensure_ascii=False, indent=2), encoding="utf-8"
        )
    if MANIFEST.exists():
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        manifest["isolation"] = card()
        manifest["isolation"]["reference_command_blocked"] = True
        MANIFEST.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    print("Mock isolation enforced: reference/reuse/knowledge are blocked.")


if __name__ == "__main__":
    main()
