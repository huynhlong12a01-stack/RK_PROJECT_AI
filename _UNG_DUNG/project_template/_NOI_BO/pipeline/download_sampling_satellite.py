"""Download full-area satellite covariates used before sample design.

This reuses the tested multi-band GEE downloader and writes tiled, grid-aligned
rasters into the internal design workspace. Existing complete rasters are reused
by the one-click workflow unless the user requests a forced download.
"""

import hashlib
import importlib.util
import json
import shutil
from pathlib import Path

import ee
import geopandas as gpd
import rasterio
import yaml
from pyproj import Transformer
from rasterio.windows import Window
from shapely.geometry import box

from scientific_metadata import covariate_provenance


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "{{PROJECT_ID}}"
ROI_FILE = PROJECT / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO" / "roi_field_area.geojson"
TEMPLATE_FILE = PROJECT / "_NOI_BO" / "work" / "design" / "grid_template.tif"
OUTPUT_DIR = PROJECT / "_NOI_BO" / "work" / "design"
TILE_DIR = PROJECT / "_NOI_BO" / "work" / "design" / "qa" / "download_tiles"
QA_FILE = PROJECT / "_NOI_BO" / "work" / "design" / "qa" / "download_summary.json"
RAW_PROVENANCE_FILE = QA_FILE.parent / "raw_covariate_provenance.json"
CONFIG_FILE = PROJECT / "_NOI_BO" / "config" / "project.yml"
TILE_PIXELS = 512

with CONFIG_FILE.open("r", encoding="utf-8") as stream:
    cfg = yaml.safe_load(stream)
if not isinstance(cfg, dict):
    raise ValueError(f"Invalid project configuration: {CONFIG_FILE}")
GEE_PROJECT_ID = str(cfg["gee_project_id"])

source_script = PROJECT / "_NOI_BO" / "pipeline" / "02_download_gee_support.py"
spec = importlib.util.spec_from_file_location("aks_gee_support", source_script)
gee_support = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gee_support)
gee_support.SOURCE_DIR = OUTPUT_DIR
gee_support.TILE_DIR = TILE_DIR


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    if not ROI_FILE.exists() or not TEMPLATE_FILE.exists():
        raise FileNotFoundError("ROI or sampling template is missing.")
    ee.Initialize(project=GEE_PROJECT_ID)
    stack = gee_support.build_image_stack()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    TILE_DIR.mkdir(parents=True, exist_ok=True)
    QA_FILE.parent.mkdir(parents=True, exist_ok=True)

    with rasterio.open(TEMPLATE_FILE) as template:
        roi = gpd.read_file(ROI_FILE).to_crs(template.crs)
        spatial_index = roi.sindex
        windows = []
        for row in range(0, template.height, TILE_PIXELS):
            for col in range(0, template.width, TILE_PIXELS):
                window = Window(
                    col,
                    row,
                    min(TILE_PIXELS, template.width - col),
                    min(TILE_PIXELS, template.height - row),
                )
                bounds = rasterio.windows.bounds(window, template.transform)
                if len(spatial_index.query(box(*bounds))) > 0:
                    windows.append(window)

        outputs = gee_support.initialize_outputs(template)
        to_wgs84 = Transformer.from_crs(template.crs, "EPSG:4326", always_xy=True)
        completed = 0
        try:
            for idx, window in enumerate(windows, start=1):
                print(f"[{idx}/{len(windows)}] Full-area GEE tile", flush=True)
                tile = gee_support.export_tile(stack, idx, window, template, to_wgs84)
                gee_support.write_tile_to_outputs(tile, window, template, outputs)
                completed += 1
        finally:
            for dataset in outputs.values():
                dataset.close()

    provenance = covariate_provenance(
        project_id=cfg["project_id"],
        crs=gee_support.CRS,
        computational_grid_m=cfg["resolution_m"],
        start_date=gee_support.START_DATE,
        end_date=gee_support.END_DATE,
    )
    raw_hashes = {
        name: sha256_file(OUTPUT_DIR / f"{name}.tif")
        for name in gee_support.BAND_NAMES
    }
    provenance["source_identity"] = {
        "gee_project_id": GEE_PROJECT_ID,
        "roi_field_area_sha256": sha256_file(ROI_FILE),
    }
    provenance["raw_covariate_sha256"] = raw_hashes
    summary = {
        "project_id": cfg["project_id"],
        "purpose": "satellite covariates before sampling design",
        "gee_project_id": GEE_PROJECT_ID,
        "roi_field_area_sha256": provenance["source_identity"]["roi_field_area_sha256"],
        "bands": gee_support.BAND_NAMES,
        "tiles": len(windows),
        "completed": completed,
        "crs": gee_support.CRS,
        "resolution_m": cfg["resolution_m"],
        "computational_grid_m": cfg["resolution_m"],
        "start_date": gee_support.START_DATE,
        "end_date": gee_support.END_DATE,
        "covariate_provenance": provenance,
    }
    QA_FILE.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (QA_FILE.parent / "covariate_provenance.json").write_text(
        json.dumps(provenance, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    RAW_PROVENANCE_FILE.write_text(
        json.dumps(provenance, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    shutil.rmtree(TILE_DIR, ignore_errors=True)
    print("Full-area sampling covariate download complete.")


if __name__ == "__main__":
    main()
