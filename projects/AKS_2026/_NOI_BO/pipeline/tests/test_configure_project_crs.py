#!/usr/bin/env python3
"""Portable-CRS regression tests without project or private data."""
from __future__ import annotations

import importlib.util
import shutil
import sys
from pathlib import Path
from unittest.mock import patch

import geopandas as gpd
from shapely.geometry import box

ROOT = Path(__file__).resolve().parents[5]
SCRIPT = Path(__file__).resolve().parents[1] / "configure_project_crs.py"
spec = importlib.util.spec_from_file_location("configure_project_crs_tested", SCRIPT)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

zone48 = gpd.GeoDataFrame(geometry=[box(104.5, 10.0, 106.0, 12.0)], crs=4326)
with patch.object(module.gpd, "read_file", return_value=zone48):
    epsg, summary = module.derive_utm_epsg(Path("zone48.geojson"))
assert epsg == 32648
assert summary["utm_zone"] == 48

zone49 = gpd.GeoDataFrame(geometry=[box(108.4, 13.6, 109.0, 14.3)], crs=4326)
with patch.object(module.gpd, "read_file", return_value=zone49):
    epsg, summary = module.derive_utm_epsg(Path("zone49.geojson"))
assert epsg == 32649
assert summary["utm_zone"] == 49

unsafe_wide = gpd.GeoDataFrame(geometry=[box(102.0, 8.0, 110.0, 22.0)], crs=4326)
with patch.object(module.gpd, "read_file", return_value=unsafe_wide):
    try:
        module.derive_utm_epsg(Path("unsafe.geojson"))
    except ValueError as error:
        assert "more than 6 degrees" in str(error)
    else:
        raise AssertionError("A multi-zone ROI was silently assigned one UTM CRS")

config_dir = ROOT / "_UNG_DUNG" / "runtime" / "tests" / "crs_atomic_update"
shutil.rmtree(config_dir, ignore_errors=True)
config_dir.mkdir(parents=True, exist_ok=True)
try:
    config_path = config_dir / "config.yml"
    config_path.write_text(
        "project_id: TEST\ncrs_mode: auto\ncrs_epsg: 32648\nresolution_m: 30\n",
        encoding="utf-8",
    )
    module.atomic_update(config_path, {"crs_mode": "manual", "crs_epsg": 32649})
    assert config_path.read_text(encoding="utf-8").splitlines() == [
        "project_id: TEST",
        "crs_mode: manual",
        "crs_epsg: 32649",
        "resolution_m: 30",
    ]
finally:
    shutil.rmtree(config_dir, ignore_errors=True)

metric = module.validate_metric_projected_crs(32649)
assert metric["is_projected"] is True
assert metric["unit_conversion_factor"] == 1.0

for unsafe_epsg in (4326, 2263):
    try:
        module.validate_metric_projected_crs(unsafe_epsg)
    except ValueError:
        pass
    else:
        raise AssertionError(f"Unsafe non-metric/projected CRS EPSG:{unsafe_epsg} was accepted")

print("[OK] automatic CRS: UTM48/49, multi-zone, atomic config and metric-projected gates")
