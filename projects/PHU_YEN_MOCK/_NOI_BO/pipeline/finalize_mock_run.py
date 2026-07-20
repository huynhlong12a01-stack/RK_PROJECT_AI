"""Fail-closed PHU_YEN_MOCK finalizer: quarantine, QA gate and hash inventory."""

from __future__ import annotations

import hashlib
import json
import math
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PROJECT = Path(__file__).resolve().parents[2]
INTERNAL = PROJECT / "_NOI_BO"
RESULT = PROJECT / "02_NOI_SUY_BAN_DO" / "02_KET_QUA"
PREFIX = "MOCK_SYNTHETIC_NOT_FOR_USE"
QUARANTINE = RESULT / PREFIX
MANIFEST = PROJECT / "MOCK_RUN_MANIFEST.json"
MANIFEST_TEMPLATE = PROJECT / "MOCK_RUN_MANIFEST_TEMPLATE.json"
CONTRACT = PROJECT / "MOCK_CONTRACT.json"
GATE_PATH = QUARANTINE / "MOCK_QA_GATE.json"
TARGETS = ("pH_H2O", "OM_pct", "P_Olsen_mgkg", "K_available_mgkg")
MODELS = ("PC_ONLY", "PC_PLUS_SOIL")
SIDECAR_NAMES = {
    "README_MOCK_SYNTHETIC_NOT_FOR_USE.md",
    "_MOCK_SAFETY.json",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def assert_inside_project(path: Path) -> Path:
    resolved = path.resolve(strict=False)
    project = PROJECT.resolve()
    if resolved != project and project not in resolved.parents:
        raise ValueError(f"Unsafe path outside PHU_YEN_MOCK: {resolved}")
    return resolved


def as_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        values = value
    elif isinstance(value, str):
        values = [value]
    else:
        values = [value]
    return [str(item).strip() for item in values if str(item).strip()]


def unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(values))


def finite_float(value: Any) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return math.nan
    return number if math.isfinite(number) else math.nan


def conflict_destination(run_id: str, category: str, relative: Path) -> Path:
    base = QUARANTINE / "_partial_runs" / run_id / category / relative
    candidate = base
    index = 1
    while candidate.exists():
        candidate = base.with_name(f"{base.stem}_{index}{base.suffix}")
        index += 1
    return candidate


def quarantine_outputs(run_id: str) -> dict[str, int]:
    """Move every normal output under the labelled quarantine, without overwriting."""
    assert_inside_project(QUARANTINE).mkdir(parents=True, exist_ok=True)
    moved = 0
    duplicate = 0
    conflicts = 0
    for category in ("maps", "reports", "tables"):
        source = assert_inside_project(RESULT / category)
        if not source.exists():
            continue
        files = [path for path in source.rglob("*") if path.is_file()]
        for path in files:
            relative = path.relative_to(source)
            destination = assert_inside_project(QUARANTINE / category / relative)
            if destination.exists():
                if path.stat().st_size == destination.stat().st_size and sha256(path) == sha256(destination):
                    path.unlink()
                    duplicate += 1
                    continue
                destination = assert_inside_project(
                    conflict_destination(run_id, category, relative)
                )
                conflicts += 1
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(path), str(destination))
            moved += 1
        shutil.rmtree(source)
    return {"moved": moved, "duplicates_removed": duplicate, "conflicts_preserved": conflicts}


def evaluation_candidates(model_family: str) -> list[Path]:
    # Prefer quarantined public reports. They remain available after runtime cleanup.
    quarantined = sorted(
        (QUARANTINE / "reports").glob(
            f"*/{model_family}/json/evaluation_*.json"
        )
    )
    work = sorted(
        (INTERNAL / "work" / "models" / model_family).glob(
            "PHU_YEN_MOCK_*/06_report/json/evaluation_*.json"
        )
    )
    return quarantined + work


def evaluate(path: Path, model_family: str) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    cv = data.get("cross_validation") or {}
    metrics = cv.get("metrics") or {}
    observed = data.get("data_quality") or {}
    extrapolation = data.get("extrapolation") or {}
    clipping = data.get("clipping") or {}
    variogram = data.get("variogram") or {}
    governance = data.get("product_governance") or {}

    rmse = finite_float(metrics.get("RMSE"))
    r2 = finite_float(metrics.get("R2_pred"))
    minimum = finite_float(observed.get("min"))
    maximum = finite_float(observed.get("max"))
    observed_range = maximum - minimum if math.isfinite(minimum) and math.isfinite(maximum) else math.nan
    outside_aoa = finite_float(extrapolation.get("outside_aoa_percent"))
    clipped = finite_float(clipping.get("total_clipped_percent"))

    top_level = as_list(data.get("hard_failures"))
    variogram_failures = as_list(variogram.get("hard_failures"))
    cv_failures = as_list(cv.get("hard_failures"))
    governance_failures = as_list(governance.get("hard_failures"))
    all_engine = unique(top_level + variogram_failures + cv_failures + governance_failures)
    failures = list(all_engine)
    if not math.isfinite(rmse) or not math.isfinite(r2):
        failures.append("non-finite outer CV metric")
    if math.isfinite(r2) and r2 <= 0:
        failures.append("outer spatial CV R2_pred is not positive")
    if math.isfinite(rmse) and math.isfinite(observed_range) and observed_range > 0 and rmse > 2 * observed_range:
        failures.append("outer spatial CV RMSE exceeds twice the observed range")
    if math.isfinite(outside_aoa) and outside_aoa > 20:
        failures.append("more than 20 percent of prediction domain lies outside AOA")
    if math.isfinite(clipped) and clipped > 5:
        failures.append("more than 5 percent of final raster required clamping")
    failures = unique(failures)

    return {
        "path": str(path.relative_to(PROJECT)).replace("\\", "/"),
        "target": data.get("target_field"),
        "model_family": model_family,
        "outer_method": cv.get("method"),
        "outer_rmse": rmse,
        "outer_r2_pred": r2,
        "observed_range": observed_range,
        "outside_aoa_percent": outside_aoa,
        "clipped_percent": clipped,
        "engine_hard_failures_top_level": top_level,
        "variogram_hard_failures": variogram_failures,
        "cross_validation_hard_failures": cv_failures,
        "product_governance_hard_failures": governance_failures,
        "all_engine_hard_failures": all_engine,
        "gate_failures": failures,
        "accepted": not failures,
    }


def collect_evaluations() -> tuple[list[dict[str, Any]], list[str]]:
    selected: dict[tuple[str, str], dict[str, Any]] = {}
    duplicates: list[str] = []
    for family in MODELS:
        for path in evaluation_candidates(family):
            row = evaluate(path, family)
            key = (family, str(row["target"]))
            if key in selected:
                # Quarantined reports are listed first and are the durable audit source.
                duplicates.append(f"{family}/{row['target']}: {row['path']}")
                continue
            selected[key] = row
    rows = [selected[key] for key in sorted(selected)]
    return rows, duplicates


def normal_output_files() -> list[Path]:
    return [
        path
        for category in ("maps", "reports", "tables")
        for path in (RESULT / category).rglob("*")
        if (RESULT / category).exists() and path.is_file()
    ]


def write_root_safety_sidecars() -> None:
    # One root sidecar pair is sufficient because every artifact is below PREFIX.
    for path in QUARANTINE.rglob("*"):
        if path.is_file() and path.name in SIDECAR_NAMES and path.parent != QUARANTINE:
            assert_inside_project(path).unlink()
    safety = {
        "schema_version": 1,
        "project_id": "PHU_YEN_MOCK",
        "label": PREFIX,
        "non_operational": True,
        "map_use_prohibited": True,
        "source": "synthetic field, labels and formula-generated laboratory fixtures",
        "stage0_accuracy_tested": False,
        "fertilizer_recommendation": False,
    }
    text = (
        "# MOCK / SYNTHETIC / NOT FOR USE\n\n"
        "All files below this directory are non-operational software-test artifacts. "
        "They are prohibited for production, agronomic decisions, fertilizer "
        "recommendations, training, validation or cross-project transfer.\n"
    )
    (QUARANTINE / "README_MOCK_SYNTHETIC_NOT_FOR_USE.md").write_text(text, encoding="utf-8")
    (QUARANTINE / "_MOCK_SAFETY.json").write_text(
        json.dumps(safety, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def inventory() -> list[dict[str, Any]]:
    rows = []
    for path in sorted(QUARANTINE.rglob("*"), key=lambda item: str(item)):
        if path.is_file():
            rows.append(
                {
                    "path": str(path.relative_to(PROJECT)).replace("\\", "/"),
                    "size_bytes": path.stat().st_size,
                    "sha256": sha256(path),
                    "suffix": path.suffix.lower(),
                    "non_operational": True,
                    "map_use_prohibited": True,
                }
            )
    return rows


def main() -> int:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if not (
        contract.get("project_id") == "PHU_YEN_MOCK"
        and contract.get("non_operational") is True
        and contract.get("map_use_prohibited") is True
        and contract.get("knowledge_integration_eligible") is False
    ):
        raise ValueError("Static mock contract safety flags are incomplete")
    if not MANIFEST.exists():
        shutil.copyfile(MANIFEST_TEMPLATE, MANIFEST)
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if not (manifest.get("non_operational") is True and manifest.get("map_use_prohibited") is True):
        raise ValueError("Runtime manifest safety flags are incomplete")

    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    quarantine_stats = quarantine_outputs(run_id)
    rows, duplicate_sources = collect_evaluations()
    expected = {(family, target) for family in MODELS for target in TARGETS}
    present = {(str(row["model_family"]), str(row["target"])) for row in rows}
    missing = sorted(f"{family}/{target}" for family, target in expected - present)
    unexpected = sorted(f"{family}/{target}" for family, target in present - expected)
    missing_maps = sorted(
        f"{family}/{target}"
        for family, target in expected
        if not list((QUARANTINE / "maps" / target / family).glob("*.tif"))
    )
    global_failures = []
    if missing:
        global_failures.append(f"missing expected evaluations: {missing}")
    if unexpected:
        global_failures.append(f"unexpected evaluations: {unexpected}")
    if duplicate_sources:
        # Duplicate source copies are expected when durable reports and runtime work coexist.
        # They are recorded, but not a scientific failure if they represent the same key.
        pass
    if missing_maps:
        global_failures.append(f"missing quarantined map families: {missing_maps}")
    failed_models = [row for row in rows if not row["accepted"]]
    status = (
        "QA_FAILED_BLOCKED"
        if failed_models or global_failures
        else "SMOKE_QA_PASSED_NON_OPERATIONAL"
    )
    gate = {
        "schema_version": 2,
        "created_utc": utc_now(),
        "project_id": "PHU_YEN_MOCK",
        "non_operational": True,
        "map_use_prohibited": True,
        "validation_strength": "reduced nested-spatial smoke; not production validation",
        "status": status,
        "maps_accepted": False,
        "interpretation_prohibited": True,
        "expected_evaluations": len(expected),
        "n_evaluations": len(rows),
        "n_failed_models": len(failed_models),
        "n_global_failures": len(global_failures),
        "missing_evaluations": missing,
        "missing_map_families": missing_maps,
        "global_failures": global_failures,
        "duplicate_evaluation_sources_ignored": duplicate_sources,
        "partial_stage2_output_quarantined": bool(
            quarantine_stats["moved"] and (missing or missing_maps)
        ),
        "models": rows,
        "critical_note": (
            "Clamped maps never override top-level, variogram, outer spatial CV, "
            "AOA or numerical-instability failures. Mock maps are never accepted."
        ),
    }
    QUARANTINE.mkdir(parents=True, exist_ok=True)
    GATE_PATH.write_text(json.dumps(gate, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_root_safety_sidecars()

    remaining = normal_output_files()
    if remaining:
        raise ValueError(f"Unquarantined outputs remain: {remaining[:5]}")

    artifacts = inventory()
    gate_hash = sha256(GATE_PATH)
    manifest.setdefault("runtime", {})["stage2_status"] = status
    manifest["runtime"]["maps_accepted"] = False
    manifest["runtime"]["completed_utc"] = utc_now()
    manifest["runtime"]["finalization_status"] = "FAIL_CLOSED_COMPLETE"
    manifest["runtime"]["stage2_partial_output_quarantined"] = gate[
        "partial_stage2_output_quarantined"
    ]
    manifest["stage0_scope"] = contract["stage0_test_scope"]
    manifest["scientific_qa_gate"] = gate
    manifest["output_quarantine"] = {
        "prefix": PREFIX,
        "path": str(QUARANTINE.relative_to(PROJECT)).replace("\\", "/"),
        "normal_public_map_paths_empty": True,
        "targets": list(TARGETS),
        "models": list(MODELS),
        "artifact_count": len(artifacts),
        "qa_gate_path": str(GATE_PATH.relative_to(PROJECT)).replace("\\", "/"),
        "qa_gate_sha256": gate_hash,
        "quarantine_operation": quarantine_stats,
        "artifacts": artifacts,
    }
    manifest.setdefault("sources", {}).setdefault("soil_type", {})["path"] = (
        contract["sources"]["soil_type"]["path"]
    )
    manifest["knowledge_integration_eligible"] = False
    manifest["reference_reuse_eligible"] = False
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"Mock finalizer: {status}; evaluations={len(rows)}/{len(expected)}; "
        f"failed_models={len(failed_models)}; artifacts={len(artifacts)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
