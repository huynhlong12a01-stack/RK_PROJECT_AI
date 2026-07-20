"""Nested sampling design with a true CRAN-clhs core and explicit fallback.

REDUCED is the conditioned-LHS core. FULL contains that exact core plus
spatial-infill and short-lag points. The augmentation supports spatial coverage
and variogram estimation but is never labelled as direct output from clhs.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio
from rasterio.features import rasterize
from scipy.spatial import cKDTree
from shapely.geometry import mapping

from candidate_population import sample_valid_candidates
from design_samples import allocate_quotas, select_lhs_for_group
from sampling_diagnostics import plan_diagnostics
from true_clhs_backend import fallback_metadata, method_metadata, select_true_clhs_core


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "PHU_YEN_MOCK"
ROI_FILE = PROJECT / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO" / "roi_field_area.geojson"
PREDICTOR_DIR = PROJECT / "_NOI_BO" / "work" / "design"
SOIL_GROUP_FILE = PREDICTOR_DIR / "Soil_Group_Code.tif"
OUTPUT_DIR = PREDICTOR_DIR
DIAG_DIR = PREDICTOR_DIR / "qa"

CORE_SAMPLES = 79
INNER_BUFFER_M = 30.0
MIN_FIELD_AREA_HA = 0.1
MIN_SPACING_M = 100.0
MAX_CANDIDATES = 200_000
INFILL_MAX_FRACTION = 0.20
SHORT_LAG_FRACTION = 0.10
SHORT_LAG_MIN_M = 100.0
SHORT_LAG_MAX_M = 300.0
SEED = 42
SOIL_LABELS = {1: "Xa", 2: "Fa", 3: "Other"}

CORE_BACKEND = "auto"
R_EXECUTABLE = "Rscript"
TRUE_CLHS_SCRIPT = Path(__file__).with_name("run_true_clhs.R")
CLHS_ITERATIONS = 20_000
CLHS_RESTARTS = 4
CLHS_USE_CPP = True
CLHS_AUTO_INSTALL = True
CLHS_REPOSITORY = "https://cloud.r-project.org"
CLHS_WEIGHTS = {"numeric": 1.0, "factor": 1.0, "correlation": 1.0}


def _build_candidates(rng):
    pc_files = [PREDICTOR_DIR / f"PC{i}.tif" for i in range(1, 6)]
    required = [ROI_FILE, SOIL_GROUP_FILE] + pc_files
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError("Missing sampling asset(s): " + ", ".join(missing))

    sources = [rasterio.open(path) for path in pc_files]
    soil_src = rasterio.open(SOIL_GROUP_FILE)
    try:
        template = sources[0]
        roi = gpd.read_file(ROI_FILE).to_crs(template.crs)
        roi = roi[roi.geometry.notna() & ~roi.geometry.is_empty].copy()
        area_ha = roi.geometry.area / 10_000.0
        roi = roi[area_ha >= MIN_FIELD_AREA_HA].copy()
        core_geom = roi.geometry.buffer(-INNER_BUFFER_M)
        core_geom = core_geom[~core_geom.is_empty]
        if core_geom.empty:
            raise RuntimeError("The inner sampling core is empty.")

        core_mask = rasterize(
            [(mapping(geom), 1) for geom in core_geom],
            out_shape=(template.height, template.width),
            transform=template.transform,
            fill=0,
            all_touched=False,
            dtype="uint8",
        )
        features, coords, soils, candidate_metadata = sample_valid_candidates(
            sources=sources,
            soil_src=soil_src,
            core_mask=core_mask,
            transform=template.transform,
            max_candidates=MAX_CANDIDATES,
            rng=rng,
        )
        if len(features) < CORE_SAMPLES * 10:
            raise RuntimeError("Too few valid sampling-core candidates.")
        return features, coords, soils, roi, template.crs, candidate_metadata
    finally:
        for src in sources:
            src.close()
        soil_src.close()


def _fallback_core(features, coords, soils, rng, reason):
    quotas = allocate_quotas(soils, CORE_SAMPLES)
    selected = []
    for group, quota in sorted(quotas.items()):
        ids = np.where(soils == group)[0]
        selected.extend(
            select_lhs_for_group(
                features,
                coords,
                ids,
                quota,
                coords[selected] if selected else [],
                rng,
                minimum_spacing_m=MIN_SPACING_M,
            )
        )
    if len(selected) < CORE_SAMPLES:
        raise RuntimeError(f"Only selected {len(selected)}/{CORE_SAMPLES} core samples.")
    return selected, fallback_metadata(
        seed=SEED, quotas=quotas, soil_labels=SOIL_LABELS, reason=reason
    )


def _select_core(features, coords, soils, rng):
    requested = str(CORE_BACKEND).strip().lower()
    allowed = {"auto", "r_clhs", "python_clhs_like"}
    if requested not in allowed:
        raise ValueError(f"CORE_BACKEND must be one of {sorted(allowed)}; got {requested!r}.")
    if requested == "python_clhs_like":
        selected, metadata = _fallback_core(
            features, coords, soils, rng, "explicit_backend_request"
        )
        return selected, metadata, requested
    try:
        selected, metadata = select_true_clhs_core(
            features=features,
            coords=coords,
            soils=soils,
            soil_labels=SOIL_LABELS,
            sample_size=CORE_SAMPLES,
            seed=SEED,
            minimum_spacing_m=MIN_SPACING_M,
            iterations=CLHS_ITERATIONS,
            restarts=CLHS_RESTARTS,
            use_cpp=CLHS_USE_CPP,
            auto_install=CLHS_AUTO_INSTALL,
            repository=CLHS_REPOSITORY,
            weights=CLHS_WEIGHTS,
            r_executable=R_EXECUTABLE,
            r_script=TRUE_CLHS_SCRIPT,
            work_dir=OUTPUT_DIR,
            qa_dir=DIAG_DIR,
            root=ROOT,
        )
        return selected, metadata, requested
    except Exception as exc:
        if requested == "r_clhs":
            raise
        print(f"[WARN] Official CRAN clhs unavailable; declared fallback used: {exc}")
        selected, metadata = _fallback_core(features, coords, soils, rng, str(exc))
        return selected, metadata, requested


def _core_spacing_metrics(indices, coords):
    index = np.asarray(indices, dtype=int)
    if len(index) < 2:
        raise RuntimeError("At least two core samples are required for spacing QA.")
    points = coords[index]
    delta = points[:, None, :] - points[None, :, :]
    distances = np.sqrt(np.sum(delta * delta, axis=2))
    upper = distances[np.triu_indices(len(points), k=1)]
    tolerance_m = max(1e-9, abs(float(MIN_SPACING_M)) * 1e-12)
    violations = int(np.sum(upper < (float(MIN_SPACING_M) - tolerance_m)))
    return {
        "minimum_spacing_target_m": float(MIN_SPACING_M),
        "minimum_pair_distance_m": float(np.min(upper)),
        "spacing_violation_pairs": violations,
        "minimum_spacing_target_met": violations == 0,
        "numerical_tolerance_m": tolerance_m,
    }


def _augment_core(selected, coords, roi, rng):
    selected = list(selected)
    roles = ["clhs_core"] * len(selected)
    roi_area_m2 = float(roi.geometry.area.sum())
    dynamic_dmax = 1.5 * math.sqrt(roi_area_m2 / CORE_SAMPLES)
    eval_ids = rng.choice(len(coords), min(50_000, len(coords)), replace=False)
    max_infill = int(math.ceil(CORE_SAMPLES * INFILL_MAX_FRACTION))
    for _ in range(max_infill):
        tree = cKDTree(coords[selected])
        distances, _ = tree.query(coords[eval_ids])
        farthest = int(np.argmax(distances))
        if distances[farthest] <= dynamic_dmax:
            break
        idx = int(eval_ids[farthest])
        if idx in selected:
            break
        selected.append(idx)
        roles.append("spatial_infill")

    n_short = max(1, int(round(len(selected) * SHORT_LAG_FRACTION)))
    candidate_tree = cKDTree(coords)
    base_ids = rng.permutation(len(selected))
    for base_pos in base_ids:
        if roles.count("short_lag") >= n_short:
            break
        base = coords[selected[int(base_pos)]]
        near = candidate_tree.query_ball_point(base, SHORT_LAG_MAX_M)
        near = [
            idx
            for idx in near
            if idx not in selected
            and SHORT_LAG_MIN_M <= np.linalg.norm(coords[idx] - base) <= SHORT_LAG_MAX_M
            and np.min(np.linalg.norm(coords[selected] - coords[idx], axis=1)) >= MIN_SPACING_M
        ]
        rng.shuffle(near)
        if near:
            selected.append(int(near[0]))
            roles.append("short_lag")
    augmentation = {
        "spatial_infill_requested_max": max_infill,
        "spatial_infill_actual": roles.count("spatial_infill"),
        "short_lag_requested": n_short,
        "short_lag_actual": roles.count("short_lag"),
        "requested_full_count": CORE_SAMPLES + max_infill + n_short,
        "actual_full_count": len(selected),
    }
    return selected, roles, eval_ids, roi_area_m2, dynamic_dmax, augmentation


def main():
    rng = np.random.default_rng(SEED)
    features, coords, soils, roi, output_crs, candidate_metadata = _build_candidates(rng)
    core, backend, backend_requested = _select_core(features, coords, soils, rng)
    core_spacing = _core_spacing_metrics(core, coords)
    if not core_spacing["minimum_spacing_target_met"]:
        raise RuntimeError(
            "Selected sampling core violates minimum_spacing_m; no plan is published."
        )
    true_clhs_used = backend.get("backend_used") == "r_clhs_cran"
    selected, roles, eval_ids, roi_area_m2, dynamic_dmax, augmentation = (
        _augment_core(core, coords, roi, rng)
    )
    if not true_clhs_used:
        roles[: len(core)] = ["lhs_core"] * len(core)

    selected_array = np.asarray(selected, dtype=int)
    out = pd.DataFrame(
        {
            "Point_ID": [f"V2_{i + 1:03d}" for i in range(len(selected_array))],
            "X_UTM": coords[selected_array, 0],
            "Y_UTM": coords[selected_array, 1],
            "design_role": roles,
            "soil_group_code": soils[selected_array],
            "soil_group": [SOIL_LABELS.get(int(x), "Unknown") for x in soils[selected_array]],
            "inner_buffer_m": INNER_BUFFER_M,
        }
    )
    points = gpd.GeoDataFrame(
        out,
        geometry=gpd.points_from_xy(out.X_UTM, out.Y_UTM),
        crs=output_crs,
    )
    wgs = points.to_crs(4326)
    out.insert(1, "Longitude", wgs.geometry.x)
    out.insert(2, "Latitude", wgs.geometry.y)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    DIAG_DIR.mkdir(parents=True, exist_ok=True)
    out.to_csv(OUTPUT_DIR / "proposal_spatial_clhs_v2.csv", index=False)
    points.to_crs(4326).to_file(
        OUTPUT_DIR / "proposal_spatial_clhs_v2.geojson", driver="GeoJSON"
    )
    core_array = np.asarray(core, dtype=int)
    plan_metrics = {
        "FULL": plan_diagnostics(
            features, coords, soils, selected_array, eval_ids, SOIL_LABELS
        ),
        "REDUCED": plan_diagnostics(
            features, coords, soils, core_array, eval_ids, SOIL_LABELS
        ),
    }
    identity = method_metadata(backend)
    summary = {
        "schema_version": "3.0.0",
        "status": "proposal_only_not_field_plan",
        **identity,
        "backend_requested": backend_requested,
        "backend_used": backend.get("backend_used"),
        "core_backend": backend,
        "candidate_population": candidate_metadata,
        "augmentation_request_and_actual": augmentation,
        "candidate_count": int(len(features)),
        "core_requested": CORE_SAMPLES,
        "total_output": int(len(out)),
        "roles": out.design_role.value_counts().to_dict(),
        "roi_area_ha_after_0_1ha_filter": roi_area_m2 / 10_000.0,
        "dynamic_dmax_m": dynamic_dmax,
        "minimum_spacing_m": MIN_SPACING_M,
        "minimum_spacing_target_m": MIN_SPACING_M,
        "minimum_spacing_target_met": True,
        "core_spacing": core_spacing,
        "inner_buffer_m": INNER_BUFFER_M,
        "random_seed": SEED,
        "nested_design": True,
        "reduced_is_exact_subset_of_full": True,
        "plan_metrics": plan_metrics,
        "diagnostic_scope": (
            "Feature/spatial metrics describe plan coverage only and are not "
            "independent validation of nutrient-map accuracy."
        ),
    }
    (DIAG_DIR / "proposal_spatial_clhs_v2_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(
        f"Sampling proposal ready: {len(out)} points; "
        f"backend={backend.get('backend_used')}"
    )


if __name__ == "__main__":
    main()
