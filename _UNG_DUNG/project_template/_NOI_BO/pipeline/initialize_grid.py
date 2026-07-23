import math
import re
from pathlib import Path

import geopandas as gpd
import numpy as np
import rasterio
from rasterio.transform import from_origin


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "{{PROJECT_ID}}"
ROI_FILE = PROJECT / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO" / "roi_field_area.geojson"
CONFIG_FILE = PROJECT / "_NOI_BO" / "config" / "project.yml"
OUTPUT_FILE = PROJECT / "_NOI_BO" / "work" / "design" / "grid_template.tif"
NODATA = -9999.0


def config_number(name, default):
    if not CONFIG_FILE.exists():
        return default
    text = CONFIG_FILE.read_text(encoding="utf-8")
    match = re.search(rf"(?m)^[ \t]*{re.escape(name)}[ \t]*:[ \t]*([0-9.]+)[ \t]*$", text)
    return float(match.group(1)) if match else default


def main():
    if not ROI_FILE.exists():
        raise FileNotFoundError(f"Place ROI at: {ROI_FILE}")
    epsg = int(config_number("crs_epsg", 32649))
    resolution = float(config_number("resolution_m", 10))
    roi = gpd.read_file(ROI_FILE)
    if roi.crs is None:
        raise ValueError("ROI has no CRS.")
    roi = roi.to_crs(epsg=epsg)
    left, bottom, right, top = roi.total_bounds
    left = math.floor(left / resolution) * resolution
    bottom = math.floor(bottom / resolution) * resolution
    right = math.ceil(right / resolution) * resolution
    top = math.ceil(top / resolution) * resolution
    width = int(round((right - left) / resolution))
    height = int(round((top - bottom) / resolution))
    if width <= 0 or height <= 0:
        raise ValueError("ROI produced an invalid raster grid.")
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    profile = {
        "driver": "GTiff",
        "height": height,
        "width": width,
        "count": 1,
        "dtype": "float32",
        "crs": f"EPSG:{epsg}",
        "transform": from_origin(left, top, resolution, resolution),
        "nodata": NODATA,
        "compress": "LZW",
        "tiled": True,
        "blockxsize": 256,
        "blockysize": 256,
        "BIGTIFF": "IF_SAFER",
    }
    with rasterio.open(OUTPUT_FILE, "w", **profile) as dst:
        block = np.full((min(256, height), min(256, width)), NODATA, dtype="float32")
        for _, window in dst.block_windows(1):
            dst.write(block[: int(window.height), : int(window.width)], 1, window=window)
    print(f"Grid initialized: {width} x {height} cells; EPSG:{epsg}; {resolution:g} m")


if __name__ == "__main__":
    main()
