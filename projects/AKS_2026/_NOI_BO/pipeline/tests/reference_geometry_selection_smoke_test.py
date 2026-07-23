#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import sys
import contextlib
from pathlib import Path

import geopandas as gpd
from shapely.geometry import box


SCRIPT = Path(__file__).resolve().parents[1] / "interpret_sugarcane_area_final.py"
SPEC = importlib.util.spec_from_file_location("reference_geometry_final", SCRIPT)
assert SPEC and SPEC.loader
FINAL = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = FINAL
SPEC.loader.exec_module(FINAL)
CORE = FINAL.CORE

test_tmp = Path.cwd() / ".tmp"
test_tmp.mkdir(parents=True, exist_ok=True)
test_root = test_tmp / "reference_geometry_smoke"
test_root.mkdir(parents=True, exist_ok=True)
with contextlib.nullcontext(str(test_root)) as raw:
    paths = CORE.ProjectPaths.from_project(Path(raw) / "TEST")
    paths.ensure()
    fields = gpd.GeoDataFrame(
        {"name": ["large", "small", "thin"]},
        geometry=[box(500000, 1500000, 500100, 1500100), box(500200, 1500000, 500220, 1500020), box(500300, 1500000, 500315, 1500100)],
        crs="EPSG:32649",
    )
    config = dict(CORE.DEFAULTS)
    config.update(
        crs_epsg=32649,
        reference_min_field_area_ha=0.10,
        reference_inner_buffer_m=10,
        reference_max_points=100,
    )
    card = CORE.write_reference_package(
        paths,
        fields,
        {"path": "synthetic", "feature_count": 3},
        config,
    )
    selection = card["positive_reference"]["selection"]
    assert selection["excluded_below_minimum_area"] == 1
    assert selection["excluded_without_inner_core"] == 1
    assert selection["selected_points"] == 1
    refs = gpd.read_file(paths.work / "reference_package" / "positive_reference.geojson").to_crs(32649)
    assert len(refs) == 1
    assert refs.geometry.iloc[0].within(fields.geometry.iloc[0].buffer(-10))

print("[OK] positive references use minimum-area and buffered field cores")
