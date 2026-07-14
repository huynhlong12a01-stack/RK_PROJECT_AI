"""Project wrapper for the true-cLHS/fallback nested sampling engine."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path

import geopandas as gpd
import pandas as pd

from scientific_metadata import covariate_provenance


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "AKS_2026"
INPUT_DIR = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO"
RESULT_DIR = PROJECT / "01_THIET_KE_LAY_MAU" / "02_KET_QUA"
WORK_DIR = PROJECT / "_NOI_BO" / "work" / "design"
QA_DIR = WORK_DIR / "qa"
SETTINGS_FILE = INPUT_DIR / "sampling.yml"
ENGINE_FILE = PROJECT / "_NOI_BO" / "pipeline" / "design_samples_clhs.py"


def setting(name, default, cast):
    if not SETTINGS_FILE.exists():
        return default
    text = SETTINGS_FILE.read_text(encoding="utf-8")
    match = re.search(rf"(?m)^\s*{re.escape(name)}\s*:\s*([^#\r\n]+)", text)
    if not match:
        return default
    raw = match.group(1).strip().strip('"\'')
    if cast is bool:
        if raw.lower() in {"true", "yes", "1"}:
            return True
        if raw.lower() in {"false", "no", "0"}:
            return False
        raise ValueError(f"{name} must be true or false; got {raw!r}.")
    return cast(raw)


project_id = setting("project_id", "AKS_2026", str)
spec = importlib.util.spec_from_file_location("sampling_engine", ENGINE_FILE)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
engine.ROI_FILE = INPUT_DIR / "roi.geojson"
engine.PREDICTOR_DIR = WORK_DIR
engine.SOIL_GROUP_FILE = WORK_DIR / "Soil_Group_Code.tif"
engine.OUTPUT_DIR = WORK_DIR
engine.DIAG_DIR = QA_DIR
engine.CORE_SAMPLES = setting(
    "reduced_core_samples",
    setting("full_core_samples", setting("core_samples", 79, int), int),
    int,
)
engine.INNER_BUFFER_M = setting("inner_buffer_m", 30.0, float)
engine.MIN_FIELD_AREA_HA = setting("minimum_field_area_ha", 0.1, float)
engine.MIN_SPACING_M = setting("minimum_spacing_m", 100.0, float)
engine.MAX_CANDIDATES = setting("clhs_max_candidates", 200_000, int)
engine.INFILL_MAX_FRACTION = setting("spatial_infill_max_fraction", 0.20, float)
engine.SHORT_LAG_FRACTION = setting("short_lag_fraction", 0.10, float)
engine.SHORT_LAG_MIN_M = setting("short_lag_min_m", 100.0, float)
engine.SHORT_LAG_MAX_M = setting("short_lag_max_m", 300.0, float)
engine.SEED = setting("random_seed", 42, int)
engine.CORE_BACKEND = setting("clhs_backend", "auto", str)
engine.R_EXECUTABLE = os.environ.get("RK_RSCRIPT", "Rscript")
engine.TRUE_CLHS_SCRIPT = Path(__file__).with_name("run_true_clhs.R")
engine.CLHS_ITERATIONS = setting("clhs_iterations", 20_000, int)
engine.CLHS_RESTARTS = setting("clhs_restarts", 4, int)
engine.CLHS_USE_CPP = setting("clhs_use_cpp", True, bool)
engine.CLHS_AUTO_INSTALL = setting("clhs_auto_install", True, bool)
engine.CLHS_REPOSITORY = setting(
    "clhs_repository", "https://cloud.r-project.org", str
)
engine.CLHS_WEIGHTS = {
    "numeric": setting("clhs_weight_numeric", 1.0, float),
    "factor": setting("clhs_weight_factor", 1.0, float),
    "correlation": setting("clhs_weight_correlation", 1.0, float),
}

soil_summary_file = QA_DIR / "soil_group_summary.json"
if soil_summary_file.exists():
    soil_summary = json.loads(soil_summary_file.read_text(encoding="utf-8"))
    engine.SOIL_LABELS = {
        int(k): v for k, v in soil_summary.get("code_labels", {"1": "All"}).items()
    }

required = [engine.ROI_FILE, engine.SOIL_GROUP_FILE] + [
    engine.PREDICTOR_DIR / f"PC{i}.tif" for i in range(1, 6)
]
missing = [str(path) for path in required if not path.exists()]
if missing:
    raise FileNotFoundError("Missing sampling asset(s): " + ", ".join(missing))
if os.environ.get("PROJECT_VALIDATE_ONLY") == "1":
    print("Sampling assets and backend configuration are valid.")
    raise SystemExit(0)

engine.main()
engine_summary_file = QA_DIR / "proposal_spatial_clhs_v2_summary.json"
if not engine_summary_file.exists():
    raise RuntimeError("Sampling engine did not write its scientific summary.")
engine_summary = json.loads(engine_summary_file.read_text(encoding="utf-8"))
method_id = engine_summary["method_id"]
method_metadata = {
    key: engine_summary.get(key)
    for key in (
        "method_id",
        "method_family",
        "method_label",
        "backend_used",
        "is_clhs_like",
        "is_original_clhs_optimizer",
        "is_original_clhs_optimizer_core",
        "is_pure_original_clhs_design",
        "original_clhs_applies_to_roles",
        "spatial_augmentation_is_direct_clhs_output",
        "selection_objective",
        "scientific_scope",
        "package",
        "compatibility_note",
    )
    if key in engine_summary
}

generated_csv = WORK_DIR / "proposal_spatial_clhs_v2.csv"
full = pd.read_csv(generated_csv)
core_role = full.design_role.isin(["clhs_core", "lhs_core"])
if int(core_role.sum()) != engine.CORE_SAMPLES:
    raise RuntimeError("Sampling engine core size does not match configuration.")
full["sampling_method_id"] = method_id
full["sampling_backend"] = engine_summary["backend_used"]
full["plan"] = "FULL"
full["included_in_REDUCED"] = core_role
full["priority"] = core_role.map({True: 1, False: 2})
reduced = full[full.included_in_REDUCED].copy()
reduced["plan"] = "REDUCED"
reduced["priority"] = 1

RESULT_DIR.mkdir(parents=True, exist_ok=True)
QA_DIR.mkdir(parents=True, exist_ok=True)
full_csv = RESULT_DIR / "sample_cLHS_FULL.csv"
reduced_csv = RESULT_DIR / "sample_cLHS_REDUCED.csv"
full.to_csv(full_csv, index=False)
reduced.to_csv(reduced_csv, index=False)
for frame, name in (
    (full, "sample_cLHS_FULL.geojson"),
    (reduced, "sample_cLHS_REDUCED.geojson"),
):
    geo = gpd.GeoDataFrame(
        frame,
        geometry=gpd.points_from_xy(frame.Longitude, frame.Latitude),
        crs="EPSG:4326",
    )
    geo.to_file(RESULT_DIR / name, driver="GeoJSON")


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


pca_summary = read_json(QA_DIR / "pca_summary.json")
raw_coverage = read_json(QA_DIR / "raw_covariate_coverage.json")
pca_reconstruction = read_json(QA_DIR / "pca_reconstruction_check.json")
archive_dir = (
    PROJECT / "_NOI_BO" / "work" / "archive" / "design_pre_science_correction_20260713"
)
migration_note = {
    "historical_plan_preserved": archive_dir.exists(),
    "archive_path": str(archive_dir.relative_to(PROJECT)).replace("\\", "/"),
    "archived_files": (
        sorted(path.name for path in archive_dir.iterdir() if path.is_file())
        if archive_dir.exists()
        else []
    ),
    "reason": (
        "Historical outputs are preserved; the current run records the backend "
        "that actually selected the core."
    ),
}
provenance = covariate_provenance(
    project_id=project_id,
    crs=f"EPSG:{setting('crs_epsg', 32649, int)}",
    computational_grid_m=setting("resolution_m", 10.0, float),
    start_date=setting("start_date", "2026-01-01", str),
    end_date=setting("end_date", "2026-04-01", str),
)
provenance["materialization_and_coverage"] = raw_coverage
provenance["pca_reconstruction_check"] = {
    "file": "../../_NOI_BO/work/design/qa/pca_reconstruction_check.json",
    "summary": pca_reconstruction,
}
provenance_text = json.dumps(provenance, ensure_ascii=False, indent=2)
provenance_hash = hashlib.sha256(provenance_text.encode("utf-8")).hexdigest()
for path in (QA_DIR / "covariate_provenance.json", RESULT_DIR / "covariate_provenance.json"):
    path.write_text(provenance_text, encoding="utf-8")

equivalence_disclaimer = (
    "REDUCED is a lower-resource nested subset. It is not guaranteed to provide "
    "feature coverage, variogram support, prediction accuracy, or uncertainty "
    "equivalent to FULL."
)
diagnostic_disclaimer = (
    "Feature-space and spatial metrics are design diagnostics, not independent "
    "validation of nutrient-map accuracy."
)


def counts(frame):
    return {str(k): int(v) for k, v in frame.design_role.value_counts().items()}


def plan_qa(plan, frame, output_file):
    return {
        "schema_version": "3.0.0",
        "project_id": project_id,
        "plan": plan,
        "output_file": output_file,
        "count": int(len(frame)),
        "method": method_metadata,
        "backend_provenance": engine_summary.get("core_backend"),
        "design_role_counts": counts(frame),
        "nested_design": True,
        "reduced_is_subset_of_full": True,
        "sampling_constraints": {
            "minimum_spacing_target_m": engine.MIN_SPACING_M,
            "inner_buffer_m": engine.INNER_BUFFER_M,
            "random_seed": engine.SEED,
        },
        "pca": {
            key: pca_summary.get(key)
            for key in (
                "n_input",
                "n_retained",
                "dimension_reduction_applied",
                "reference_frozen",
                "reference_version",
                "reference_hash_algorithm",
                "reference_hash",
            )
        },
        "covariate_provenance": {
            "file": "covariate_provenance.json",
            "sha256": provenance_hash,
            "computational_grid_m": provenance["output_grid"]["computational_grid_m"],
            "native_or_effective_scale_warning": provenance["interpretation_warning"],
        },
        "raw_covariate_coverage": raw_coverage.get("raw_covariates", {}),
        "migration": migration_note,
        "metrics": engine_summary.get("plan_metrics", {}).get(plan, {}),
        "diagnostic_disclaimer": diagnostic_disclaimer,
        "full_reduced_equivalence_disclaimer": equivalence_disclaimer,
    }


full_qa = plan_qa("FULL", full, full_csv.name)
reduced_qa = plan_qa("REDUCED", reduced, reduced_csv.name)
(RESULT_DIR / "sampling_QA_FULL.json").write_text(
    json.dumps(full_qa, ensure_ascii=False, indent=2), encoding="utf-8"
)
(RESULT_DIR / "sampling_QA_REDUCED.json").write_text(
    json.dumps(reduced_qa, ensure_ascii=False, indent=2), encoding="utf-8"
)
qa = {
    "schema_version": "3.0.0",
    "project_id": project_id,
    "method_id": method_id,
    "method": method_metadata.get("method_label"),
    "method_metadata": method_metadata,
    "backend_requested": engine_summary.get("backend_requested"),
    "backend_used": engine_summary.get("backend_used"),
    "backend_provenance": engine_summary.get("core_backend"),
    "nested_design": True,
    "reduced_is_subset_of_full": True,
    "FULL_count": int(len(full)),
    "REDUCED_count": int(len(reduced)),
    "FULL_role_counts": counts(full),
    "REDUCED_role_counts": counts(reduced),
    "minimum_spacing_m": engine.MIN_SPACING_M,
    "inner_buffer_m": engine.INNER_BUFFER_M,
    "random_seed": engine.SEED,
    "pca_summary_file": "../../_NOI_BO/work/design/qa/pca_summary.json",
    "covariate_provenance_file": "covariate_provenance.json",
    "covariate_provenance_sha256": provenance_hash,
    "plan_qa_files": {
        "FULL": "sampling_QA_FULL.json",
        "REDUCED": "sampling_QA_REDUCED.json",
    },
    "raw_covariate_coverage": raw_coverage,
    "pca_reconstruction_check": pca_reconstruction,
    "migration": migration_note,
    "engine_summary": engine_summary,
    "warnings": [equivalence_disclaimer, diagnostic_disclaimer],
}
(RESULT_DIR / "sampling_QA.json").write_text(
    json.dumps(qa, ensure_ascii=False, indent=2), encoding="utf-8"
)
backend_label = engine_summary.get("backend_used")
(RESULT_DIR / "README_KET_QUA.md").write_text(
    "# Kết quả thiết kế lấy mẫu\n\n"
    f"- Backend thực tế: `{backend_label}`.\n"
    f"- FULL: {len(full)} điểm; REDUCED: {len(reduced)} điểm.\n"
    "- REDUCED là lõi; FULL giữ nguyên lõi và thêm spatial infill/short-lag.\n"
    "- Chỉ các điểm `clhs_core` mới là đầu ra trực tiếp của CRAN clhs.\n"
    "- REDUCED không được bảo đảm chất lượng tương đương FULL.\n",
    encoding="utf-8",
)
print(
    f"Sampling plans ready: FULL={len(full)}, REDUCED={len(reduced)}, "
    f"backend={backend_label}"
)
