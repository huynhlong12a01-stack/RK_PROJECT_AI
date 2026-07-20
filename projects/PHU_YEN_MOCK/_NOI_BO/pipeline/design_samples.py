"""Spatially constrained cLHS-like sampling for PHU_YEN_MOCK.

This creates a new proposal and never overwrites the legacy field plan.
Candidate pixels must already have PC1-PC5 and Soil_Group_Code values.
"""

import json
import math
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio
from rasterio.features import rasterize
from scipy.spatial import cKDTree
from scipy.stats.qmc import LatinHypercube
from shapely.geometry import mapping
from sampling_diagnostics import plan_diagnostics


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "PHU_YEN_MOCK"
ROI_FILE = PROJECT / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO" / "roi_field_area.geojson"
PREDICTOR_DIR = PROJECT / "_NOI_BO" / "work" / "design"
SOIL_GROUP_FILE = PROJECT / "_NOI_BO" / "work" / "design" / "Soil_Group_Code.tif"
OUTPUT_DIR = PROJECT / "_NOI_BO" / "work" / "design"
DIAG_DIR = PROJECT / "_NOI_BO" / "work" / "design" / "qa"

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


def allocate_quotas(groups, n_total):
    values, counts = np.unique(groups, return_counts=True)
    props = counts / counts.sum()
    raw = props * n_total
    quota = np.floor(raw).astype(int)
    eligible = props >= 0.01
    quota[eligible] = np.maximum(quota[eligible], 2)
    while quota.sum() > n_total:
        candidates = np.where(quota > np.where(eligible, 2, 0))[0]
        quota[candidates[np.argmax(quota[candidates] - raw[candidates])]] -= 1
    while quota.sum() < n_total:
        quota[np.argmax(raw - quota)] += 1
    return dict(zip(values.astype(int), quota.astype(int)))


def select_lhs_for_group(
    features, coords, candidate_ids, n, selected_coords, rng,
    minimum_spacing_m=MIN_SPACING_M,
):
    if n <= 0 or len(candidate_ids) == 0:
        return []
    x = features[candidate_ids]
    means = x.mean(axis=0)
    scales = x.std(axis=0)
    scales[scales == 0] = 1
    z = (x - means) / scales
    lhs = LatinHypercube(d=z.shape[1], seed=int(rng.integers(1, 2**31 - 1))).random(n)
    targets = np.column_stack([
        np.quantile(z[:, col], lhs[:, col]) for col in range(z.shape[1])
    ])
    tree = cKDTree(z)
    _, neighbors = tree.query(targets, k=min(50, len(candidate_ids)))
    neighbors = np.atleast_2d(neighbors)
    chosen = []
    used = set()
    all_selected = list(selected_coords)
    for row in neighbors:
        accepted = None
        for local_idx in np.atleast_1d(row):
            global_idx = int(candidate_ids[int(local_idx)])
            if global_idx in used:
                continue
            point = coords[global_idx]
            if all_selected:
                dist = np.linalg.norm(np.asarray(all_selected) - point, axis=1)
                if np.min(dist) < minimum_spacing_m:
                    continue
            accepted = global_idx
            break
        if accepted is not None:
            chosen.append(accepted)
            used.add(accepted)
            all_selected.append(coords[accepted])
    if len(chosen) < n:
        remainder = [idx for idx in candidate_ids if int(idx) not in used]
        rng.shuffle(remainder)
        for idx in remainder:
            point = coords[int(idx)]
            if all_selected:
                if np.min(np.linalg.norm(np.asarray(all_selected) - point, axis=1)) < minimum_spacing_m:
                    continue
            chosen.append(int(idx))
            all_selected.append(point)
            if len(chosen) == n:
                break
    return chosen


def main():
    rng = np.random.default_rng(SEED)
    pc_files = [PREDICTOR_DIR / f"PC{i}.tif" for i in range(1, 6)]
    required = [ROI_FILE, SOIL_GROUP_FILE] + pc_files
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError("Missing sampling asset(s): " + ", ".join(missing))

    sources = [rasterio.open(path) for path in pc_files]
    soil_src = rasterio.open(SOIL_GROUP_FILE)
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

    feature_chunks = []
    coord_chunks = []
    soil_chunks = []
    probability = min(1.0, MAX_CANDIDATES / 4_000_000.0)
    for _, window in template.block_windows(1):
        bands = np.stack([src.read(1, window=window) for src in sources], axis=-1)
        soil = soil_src.read(1, window=window)
        row0, col0 = int(window.row_off), int(window.col_off)
        core = core_mask[row0:row0 + int(window.height), col0:col0 + int(window.width)] == 1
        valid = core & np.all(np.isfinite(bands), axis=-1) & (soil >= 1) & (soil <= 3)
        rows, cols = np.where(valid)
        if len(rows) == 0:
            continue
        keep = rng.random(len(rows)) < probability
        rows, cols = rows[keep], cols[keep]
        if len(rows) == 0:
            continue
        global_rows = rows + row0
        global_cols = cols + col0
        xs = template.transform.c + template.transform.a * (global_cols + 0.5)
        ys = template.transform.f + template.transform.e * (global_rows + 0.5)
        feature_chunks.append(bands[rows, cols, :])
        coord_chunks.append(np.column_stack([xs, ys]))
        soil_chunks.append(soil[rows, cols])

    for src in sources:
        src.close()
    soil_src.close()

    features = np.vstack(feature_chunks)
    coords = np.vstack(coord_chunks)
    soils = np.concatenate(soil_chunks).astype(int)
    if len(features) > MAX_CANDIDATES:
        keep = rng.choice(len(features), MAX_CANDIDATES, replace=False)
        features, coords, soils = features[keep], coords[keep], soils[keep]
    if len(features) < CORE_SAMPLES * 10:
        raise RuntimeError("Too few valid sampling-core candidates.")

    quotas = allocate_quotas(soils, CORE_SAMPLES)
    selected = []
    for group, quota in sorted(quotas.items()):
        ids = np.where(soils == group)[0]
        chosen = select_lhs_for_group(
            features, coords, ids, quota, coords[selected] if selected else [], rng
        )
        selected.extend(chosen)
    if len(selected) < CORE_SAMPLES:
        raise RuntimeError(f"Only selected {len(selected)}/{CORE_SAMPLES} core samples.")

    roles = ["lhs_core"] * len(selected)
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
    base_ids = rng.choice(len(selected), min(n_short, len(selected)), replace=False)
    for base_pos in base_ids:
        base = coords[selected[int(base_pos)]]
        near = candidate_tree.query_ball_point(base, SHORT_LAG_MAX_M)
        near = [idx for idx in near if SHORT_LAG_MIN_M <= np.linalg.norm(coords[idx] - base) <= SHORT_LAG_MAX_M]
        rng.shuffle(near)
        pick = next((idx for idx in near if idx not in selected), None)
        if pick is not None:
            selected.append(int(pick))
            roles.append("short_lag")

    selected = np.asarray(selected, dtype=int)
    out = pd.DataFrame({
        "Point_ID": [f"V2_{i+1:03d}" for i in range(len(selected))],
        "X_UTM": coords[selected, 0],
        "Y_UTM": coords[selected, 1],
        "design_role": roles,
        "soil_group_code": soils[selected],
        "soil_group": [SOIL_LABELS.get(int(x), "Unknown") for x in soils[selected]],
        "inner_buffer_m": INNER_BUFFER_M,
    })
    points = gpd.GeoDataFrame(
        out,
        geometry=gpd.points_from_xy(out.X_UTM, out.Y_UTM),
        crs=template.crs,
    )
    wgs = points.to_crs(4326)
    out.insert(1, "Longitude", wgs.geometry.x)
    out.insert(2, "Latitude", wgs.geometry.y)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    DIAG_DIR.mkdir(parents=True, exist_ok=True)
    out.to_csv(OUTPUT_DIR / "proposal_spatial_clhs_v2.csv", index=False)
    points.to_crs(4326).to_file(
        OUTPUT_DIR / "proposal_spatial_clhs_v2.geojson",
        driver="GeoJSON",
    )
    reduced_ids = selected[np.asarray(roles) == "lhs_core"]
    plan_metrics = {
        "FULL": plan_diagnostics(
            features, coords, soils, selected, eval_ids, SOIL_LABELS
        ),
        "REDUCED": plan_diagnostics(
            features, coords, soils, reduced_ids, eval_ids, SOIL_LABELS
        ),
    }
    summary = {
        "schema_version": "2.0.0",
        "status": "proposal_only_not_field_plan",
        "method_id": "clhs_like_spatially_constrained_soil_stratified_lhs",
        "method_family": "spatially_constrained_soil_stratified_lhs",
        "is_original_clhs_optimizer": False,
        "method": (
            "cLHS-like soil-stratified Latin-hypercube targets in PCA space "
            "with spatial constraints"
        ),
        "candidate_count": int(len(features)),
        "core_requested": CORE_SAMPLES,
        "total_output": int(len(out)),
        "roles": out.design_role.value_counts().to_dict(),
        "soil_quotas": {SOIL_LABELS.get(k, str(k)): int(v) for k, v in quotas.items()},
        "roi_area_ha_after_0_1ha_filter": roi_area_m2 / 10_000.0,
        "dynamic_dmax_m": dynamic_dmax,
        "minimum_spacing_m": MIN_SPACING_M,
        "minimum_spacing_target_m": MIN_SPACING_M,
        "inner_buffer_m": INNER_BUFFER_M,
        "random_seed": SEED,
        "plan_metrics": plan_metrics,
        "diagnostic_scope": (
            "Feature/spatial metrics describe plan coverage only and are not "
            "independent validation of nutrient-map accuracy."
        ),
    }
    (DIAG_DIR / "proposal_spatial_clhs_v2_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"Sampling proposal ready: {len(out)} points")


if __name__ == "__main__":
    main()
