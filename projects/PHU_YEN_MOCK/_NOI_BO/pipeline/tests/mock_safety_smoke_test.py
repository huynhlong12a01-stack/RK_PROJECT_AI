"""Static/runtime safety regression test for the PHU_YEN_MOCK fixture."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[3]
QUARANTINE = PROJECT / "02_NOI_SUY_BAN_DO" / "02_KET_QUA" / "MOCK_SYNTHETIC_NOT_FOR_USE"
GATE = QUARANTINE / "MOCK_QA_GATE.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


contract = json.loads((PROJECT / "MOCK_CONTRACT.json").read_text(encoding="utf-8"))
manifest = json.loads((PROJECT / "MOCK_RUN_MANIFEST.json").read_text(encoding="utf-8"))
gate = json.loads(GATE.read_text(encoding="utf-8"))

assert contract["project_id"] == "PHU_YEN_MOCK"
assert contract["non_operational"] is True
assert contract["map_use_prohibited"] is True
assert contract["knowledge_integration_eligible"] is False
assert contract["external_reference_reuse_eligible"] is False
assert contract["sources"]["soil_type"]["path"] == (
    "shared_data/soil_type_vietnam/raw/VN_soil_type.geojson"
)
assert manifest["runtime"]["maps_accepted"] is False
assert gate["maps_accepted"] is False
assert gate["interpretation_prohibited"] is True
assert gate["n_evaluations"] == 8
assert gate["expected_evaluations"] == 8
allowed_statuses = {"QA_FAILED_BLOCKED", "SMOKE_QA_PASSED_NON_OPERATIONAL"}
assert gate["status"] in allowed_statuses
assert manifest["runtime"]["stage2_status"] == gate["status"]

expected = {
    (family, target)
    for family in ("PC_ONLY", "PC_PLUS_SOIL")
    for target in ("pH_H2O", "OM_pct", "P_Olsen_mgkg", "K_available_mgkg")
}
actual = {(row["model_family"], row["target"]) for row in gate["models"]}
assert actual == expected
assert all("all_engine_hard_failures" in row for row in gate["models"])
if gate["status"] == "QA_FAILED_BLOCKED":
    assert gate["n_failed_models"] > 0 or gate["n_global_failures"] > 0
    assert any(not row["accepted"] for row in gate["models"]) or gate["global_failures"]
else:
    assert gate["n_failed_models"] == 0
    assert gate["n_global_failures"] == 0
    assert all(row["accepted"] for row in gate["models"])

normal_files = [
    path
    for category in ("maps", "reports", "tables")
    for path in (PROJECT / "02_NOI_SUY_BAN_DO" / "02_KET_QUA" / category).rglob("*")
    if (PROJECT / "02_NOI_SUY_BAN_DO" / "02_KET_QUA" / category).exists()
    and path.is_file()
]
assert not normal_files, normal_files[:5]

inventory = manifest["output_quarantine"]["artifacts"]
paths = [row["path"] for row in inventory]
assert len(paths) == len(set(paths))
gate_relative = str(GATE.relative_to(PROJECT)).replace("\\", "/")
gate_row = next(row for row in inventory if row["path"] == gate_relative)
assert gate_row["sha256"] == sha256(GATE)
assert manifest["output_quarantine"]["qa_gate_sha256"] == sha256(GATE)
assert manifest["output_quarantine"]["normal_public_map_paths_empty"] is True

bats = sorted(path.relative_to(PROJECT).as_posix() for path in PROJECT.rglob("*.bat"))
assert bats == ["00_CHAY_MOCK_AN_TOAN.bat"], bats
orchestrator_text = (PROJECT / "_NOI_BO" / "run_mock_workflow.ps1").read_text(encoding="utf-8")
assert "$env:RK_PHU_YEN_MOCK_SAFE_RUN = 'orchestrated-v1'" in orchestrator_text
assert "$env:RK_PHU_YEN_MOCK_SAFE_RUN = $previousMockToken" in orchestrator_text
assert "mock_workflow.lock" in orchestrator_text
assert "[IO.FileShare]::None" in orchestrator_text
assert "concurrent writes are blocked" in orchestrator_text
design_runner_text = (PROJECT / "_NOI_BO" / "run_design_workflow.ps1").read_text(encoding="utf-8")
assert "ensure_mock_pca_reference_compat" not in orchestrator_text
assert "ensure_mock_pca_reference_compat" not in design_runner_text
assert not (PROJECT / "_NOI_BO" / "pipeline" / "ensure_mock_pca_reference_compat.py").exists()
for runner_name in ("run_interpolation_workflow.ps1", "run_sensitivity_workflow.ps1"):
    runner_text = (PROJECT / "_NOI_BO" / runner_name).read_text(encoding="utf-8")
    assert "RK_PHU_YEN_MOCK_SAFE_RUN -ne 'orchestrated-v1'" in runner_text, runner_name
assert (PROJECT / "_NOI_BO" / "config" / "raster_manifest.csv").is_file()

blocker = PROJECT / "_NOI_BO" / "pipeline" / "build_positive_feature_library.py"
result = subprocess.run(
    [sys.executable, str(blocker), "--project-dir", str(PROJECT)],
    text=True,
    capture_output=True,
    check=False,
)
assert result.returncode == 2
assert "BLOCKED" in (result.stdout + result.stderr)

print(
    f"[OK] PHU_YEN_MOCK safety: gate={gate['status']}; "
    f"evaluations={gate['n_evaluations']}; artifacts={len(inventory)}"
)
