import json
import math
import os
import shutil
from pathlib import Path

import ee
import geemap
import geopandas as gpd
import numpy as np
import rasterio
import yaml
from pyproj import Transformer
from rasterio.enums import Resampling
from rasterio.windows import Window
from rasterio.warp import reproject


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "AKS_2026"
CFG = yaml.safe_load((PROJECT / "_NOI_BO" / "config" / "project.yml").read_text(encoding="utf-8"))

GEE_PROJECT_ID = "rkapp-492504"
CRS = f"EPSG:{int(CFG['crs_epsg'])}"
START_DATE = CFG["legacy_parameters"]["start_date"]
END_DATE = CFG["legacy_parameters"]["end_date"]
BUFFER_FILE = ROOT / CFG["runtime"]["support_buffers_gpkg"]
SOURCE_DIR = ROOT / CFG["runtime"]["expanded_covariate_dir"]
QA_DIR = ROOT / CFG["runtime"]["qa_dir"]
TEMPLATE_FILE = Path(CFG["source"]["legacy_pca_dir"]) / "PC1.tif"
TILE_DIR = PROJECT / "_NOI_BO" / "work" / "interpolation" / "qa" / "download_tiles"

BAND_NAMES = ["CHIRPS", "DEM", "NDVI", "Slope", "TWI"]
NODATA = -9999.0


def cloud_mask(image):
    mask = image.select("cs_cdf").gte(0.60)
    return image.updateMask(mask).divide(10000)


def build_image_stack():
    dem = ee.Image("USGS/SRTMGL1_003").select("elevation").rename("DEM")
    slope = ee.Terrain.slope(dem).rename("Slope")

    slope_rad = ee.Terrain.slope(dem).multiply(math.pi).divide(180)
    slope_safe = slope_rad.max(0.001)
    flow_acc = ee.Image("MERIT/Hydro/v1_0_1").select("upg")
    contributing_area = flow_acc.multiply(ee.Image.pixelArea()).max(1)
    twi = contributing_area.divide(slope_safe.tan()).log().rename("TWI")

    s2 = (
        ee.ImageCollection("COPERNICUS/S2_SR_HARMONIZED")
        .filterDate(START_DATE, END_DATE)
        .filter(ee.Filter.lt("CLOUDY_PIXEL_PERCENTAGE", 80))
    )
    cloud_score = ee.ImageCollection(
        "GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED"
    ).filterDate(START_DATE, END_DATE)
    clean_s2 = s2.linkCollection(cloud_score, ["cs_cdf"]).map(cloud_mask)
    ndvi = clean_s2.median().normalizedDifference(["B8", "B4"]).rename("NDVI")

    chirps = (
        ee.ImageCollection("UCSB-CHG/CHIRPS/DAILY")
        .filterDate(START_DATE, END_DATE)
        .sum()
        .rename("CHIRPS")
        .setDefaultProjection(crs="EPSG:4326", scale=5566)
        .resample("bilinear")
    )

    return chirps.addBands([dem, ndvi, slope, twi]).select(BAND_NAMES).toFloat()


def aligned_windows(buffer_path, template):
    buffers = gpd.read_file(buffer_path).to_crs(template.crs)
    merged = buffers.geometry.union_all()
    pieces = list(merged.geoms) if hasattr(merged, "geoms") else [merged]
    windows = []
    for geom in pieces:
        left, bottom, right, top = geom.bounds
        raw = rasterio.windows.from_bounds(left, bottom, right, top, template.transform)
        col0 = max(0, math.floor(raw.col_off))
        row0 = max(0, math.floor(raw.row_off))
        col1 = min(template.width, math.ceil(raw.col_off + raw.width))
        row1 = min(template.height, math.ceil(raw.row_off + raw.height))
        if col1 > col0 and row1 > row0:
            windows.append(Window(col0, row0, col1 - col0, row1 - row0))
    return windows


def initialize_outputs(template):
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    profile = template.profile.copy()
    profile.update(
        driver="GTiff",
        count=1,
        dtype="float32",
        nodata=NODATA,
        compress="LZW",
        tiled=True,
        blockxsize=256,
        blockysize=256,
        BIGTIFF="IF_SAFER",
    )
    datasets = {}
    for name in BAND_NAMES:
        path = SOURCE_DIR / f"{name}.tif"
        ds = rasterio.open(path, "w", **profile)
        for _, window in ds.block_windows(1):
            fill = np.full((int(window.height), int(window.width)), NODATA, dtype="float32")
            ds.write(fill, 1, window=window)
        datasets[name] = ds
    return datasets


def export_tile(stack, idx, window, template, to_wgs84):
    left, bottom, right, top = rasterio.windows.bounds(window, template.transform)
    lon_left, lat_bottom = to_wgs84.transform(left, bottom)
    lon_right, lat_top = to_wgs84.transform(right, top)
    region = ee.Geometry.Rectangle(
        [lon_left, lat_bottom, lon_right, lat_top], geodesic=False
    )
    tile_path = TILE_DIR / f"support_{idx:03d}.tif"
    if tile_path.exists():
        tile_path.unlink()
    tile_transform = rasterio.windows.transform(window, template.transform)
    geemap.ee_export_image(
        stack,
        filename=str(tile_path),
        crs=CRS,
        crs_transform=[
            tile_transform.a,
            tile_transform.b,
            tile_transform.c,
            tile_transform.d,
            tile_transform.e,
            tile_transform.f,
        ],
        region=region,
        file_per_band=False,
        unmask_value=NODATA,
        timeout=300,
        verbose=False,
    )
    if not tile_path.exists() or tile_path.stat().st_size == 0:
        raise RuntimeError(f"GEE did not create tile {idx}")
    return tile_path


def write_tile_to_outputs(tile_path, window, template, outputs):
    dst_transform = rasterio.windows.transform(window, template.transform)
    with rasterio.open(tile_path) as src:
        if src.count != len(BAND_NAMES):
            raise RuntimeError(
                f"Unexpected band count in {tile_path.name}: {src.count}"
            )
        for band_idx, name in enumerate(BAND_NAMES, start=1):
            dest = np.full(
                (int(window.height), int(window.width)), NODATA, dtype="float32"
            )
            reproject(
                source=rasterio.band(src, band_idx),
                destination=dest,
                src_transform=src.transform,
                src_crs=src.crs,
                src_nodata=src.nodata,
                dst_transform=dst_transform,
                dst_crs=template.crs,
                dst_nodata=NODATA,
                resampling=Resampling.bilinear,
            )
            outputs[name].write(dest, 1, window=window)


def main():
    if not BUFFER_FILE.exists():
        raise FileNotFoundError(
            f"Support buffers not found: {BUFFER_FILE}. Run preflight first."
        )
    if not TEMPLATE_FILE.exists():
        raise FileNotFoundError(f"Legacy PC template not found: {TEMPLATE_FILE}")

    ee.Initialize(project=GEE_PROJECT_ID)
    stack = build_image_stack()
    TILE_DIR.mkdir(parents=True, exist_ok=True)
    QA_DIR.mkdir(parents=True, exist_ok=True)

    with rasterio.open(TEMPLATE_FILE) as template:
        windows = aligned_windows(BUFFER_FILE, template)
        if not windows:
            raise RuntimeError("No support window intersects the legacy grid.")
        outputs = initialize_outputs(template)
        to_wgs84 = Transformer.from_crs(template.crs, "EPSG:4326", always_xy=True)
        completed = 0
        try:
            for idx, window in enumerate(windows, start=1):
                print(f"[{idx}/{len(windows)}] Downloading GEE support tile...", flush=True)
                tile_path = export_tile(stack, idx, window, template, to_wgs84)
                write_tile_to_outputs(tile_path, window, template, outputs)
                completed += 1
        finally:
            for ds in outputs.values():
                ds.close()

    summary = {
        "project_id": CFG["project_id"],
        "gee_project_id": GEE_PROJECT_ID,
        "start_date": START_DATE,
        "end_date": END_DATE,
        "crs": CRS,
        "resolution_m": CFG["resolution_m"],
        "bands": BAND_NAMES,
        "support_windows": len(windows),
        "completed_windows": completed,
        "output_dir": str(SOURCE_DIR).replace("\\", "/"),
    }
    (QA_DIR / "gee_support_download_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    shutil.rmtree(TILE_DIR, ignore_errors=True)
    print("GEE support download complete.", flush=True)


if __name__ == "__main__":
    main()
