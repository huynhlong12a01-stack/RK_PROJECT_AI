#!/usr/bin/env python3
"""Smoke tests for the explicit positive-only sugarcane screening contract."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
from shapely.geometry import box


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
PIPELINE = HERE.parent
ENTRY = PIPELINE / "interpret_sugarcane_area_final.py"
SCREENING = PIPELINE / "positive_only_screening.py"


def load_module():
    spec = importlib.util.spec_from_file_location("positive_only_screening_tested", SCREENING)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {SCREENING}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


module = load_module()
rng = np.random.default_rng(42)
values = np.vstack(
    [
        rng.normal(0, 0.25, size=(30, 8)),
        rng.normal(2, 0.25, size=(30, 8)),
    ]
)
center, scale, standardized = module.robust_standardize(values)
assert center.shape == (8,)
assert scale.shape == (8,)
assert np.isfinite(standardized).all()
prototypes = module.farthest_point_prototypes(standardized, 6)
assert prototypes.shape == (6, 8)
distances = module.squared_distance_to_prototypes(standardized, prototypes)
assert distances.shape == (60,)
held_out = module.spatial_holdout_distances(
    standardized,
    np.array([index % 5 for index in range(len(standardized))]),
    6,
)
assert len(held_out) == len(standardized)
assert np.isfinite(held_out).all()
selected, excluded = module.select_screening_bands(
    ["NDVI_T01", "EVI_T01", *[f"X{i}" for i in range(8)], "S2_count_T01", "worldcover_class"]
)
assert "S2_count_T01" in excluded and "worldcover_class" in excluded
assert "NDVI_T01" in selected

toy_score = np.zeros((7, 7), dtype=float)
toy_score[2:5, 2:5] = 0.8
toy_score[0, 0] = 0.8
toy_candidate = module.candidate_array_from_support_score(toy_score, 3)
assert toy_candidate[3, 3] == 1
assert toy_candidate[0, 0] == 0
screening_source = SCREENING.read_text(encoding="utf-8")
assert screening_source.count("core.download_gee_tiled(") == 1
assert "write_candidate_mask_from_score" in screening_source

temp_root = ROOT / ".tmp"
temp_root.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="positive_only_preflight_", dir=temp_root) as raw:
    project = Path(raw) / "AKS_BLIND_TEST"
    input_dir = project / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO"
    result_dir = project / "00_XAC_LAP_VUNG_MIA" / "02_KET_QUA"
    input_dir.mkdir(parents=True)
    result_dir.mkdir(parents=True)

    roi = gpd.GeoDataFrame(
        {"name": ["search_only"]},
        geometry=[box(108.45, 13.75, 108.75, 14.05)],
        crs=4326,
    )
    roi.to_file(input_dir / "roi_search.geojson", driver="GeoJSON")

    rows = []
    for index in range(40):
        rows.append(
            {
                "code": f"P{index + 1:03d}",
                "lat": 13.80 + (index // 8) * 0.04,
                "lon": 108.50 + (index % 8) * 0.025,
                "label": 1,
                "group_id": f"G{index // 5:02d}",
                "label_source": "field_observation",
            }
        )
    pd.DataFrame(rows).to_csv(input_dir / "sugarcane_labels.csv", index=False)
    config = """mode: auto
crs_epsg: 32649
gee_project_id: rkapp-492504
feature_end_date_exclusive: "2026-07-01"
temporal_quarters: 8
phenology_alignment_confirmed: true
crop_calendar_source: "AKS field sampling campaign 2026"
crop_calendar_note: "Positive support preflight only"
spatial_block_m: 3000
spatial_folds: 5
random_seed: 42
min_groups_per_class: 3
positive_screening_min_points: 30
allow_positive_only_screening: true
reuse_reference_positive: false
"""
    (input_dir / "interpretation.yml").write_text(config, encoding="utf-8")

    completed = subprocess.run(
        [
            sys.executable,
            str(ENTRY),
            "--project-dir",
            str(project),
            "--preflight-only",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    qa = json.loads((result_dir / "field_area_QA.json").read_text(encoding="utf-8"))
    assert qa["status"] == "POSITIVE_ONLY_PREFLIGHT_READY"
    assert qa["product_semantics"]["binary_classifier_trained"] is False
    assert qa["scientific_guards"]["known_roi_field_area_used_for_inference"] is False

    blocked_config = config.replace(
        "allow_positive_only_screening: true",
        "allow_positive_only_screening: false",
    )
    (input_dir / "interpretation.yml").write_text(blocked_config, encoding="utf-8")
    blocked = subprocess.run(
        [
            sys.executable,
            str(ENTRY),
            "--project-dir",
            str(project),
            "--preflight-only",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    assert blocked.returncode == 2, blocked.stdout + blocked.stderr
    blocked_qa = json.loads((result_dir / "field_area_QA.json").read_text(encoding="utf-8"))
    assert blocked_qa["status"] == "BLOCKED_POSITIVE_AND_NEGATIVE_LABELS_REQUIRED"

print("[OK] positive-only screening contract and preflight passed")
