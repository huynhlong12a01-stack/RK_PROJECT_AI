"""Download GEE covariates on an aligned grid that covers Workflow 1 plus support buffers.

The completion sidecar is schema-v2 and is written atomically only after every
raw raster has closed and its SHA-256 has been computed.
"""

import hashlib
import json
import math
import shutil
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

import ee
import geemap
import geopandas as gpd
import numpy as np
import rasterio
import yaml
from pyproj import Transformer
from rasterio.enums import Resampling
from rasterio.transform import array_bounds
from rasterio.windows import Window
from rasterio.warp import reproject


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "PHU_YEN_MOCK"
CFG = yaml.safe_load((PROJECT / "_NOI_BO" / "config" / "project.yml").read_text(encoding="utf-8"))

GEE_PROJECT_ID = str(CFG["gee_project_id"])
CRS = f"EPSG:{int(CFG['crs_epsg'])}"
START_DATE = str(CFG["legacy_parameters"]["start_date"])
END_DATE = str(CFG["legacy_parameters"]["end_date"])
SUPPORT_GEOMETRY_POLICY = str(CFG["support_policy"]["support_geometry_policy"])
SUPPORT_GEOMETRY_DERIVATION = "sf_projected_bbox_then_st_buffer_nQuadSegs_30"
SUPPORT_BUFFER_M = float(CFG["support_policy"]["covariate_support_buffer_m"])
BUFFER_FILE = ROOT / Path(CFG["runtime"]["support_buffers_gpkg"])
SOURCE_DIR = ROOT / Path(CFG["runtime"]["expanded_covariate_dir"])
QA_DIR = ROOT / Path(CFG["runtime"]["qa_dir"])
TEMPLATE_FILE = ROOT / Path(CFG["source"]["legacy_pca_dir"]) / "PC1.tif"
ROI_FILE = ROOT / Path(CFG["source"]["roi_file"])
TILE_DIR = PROJECT / "_NOI_BO" / "work" / "interpolation" / "qa" / "download_tiles"
PROVENANCE_FILE = QA_DIR / "gee_support_download_summary.json"
SUPPORT_GEOMETRY_PROVENANCE_FILE = QA_DIR / "support_geometry_privacy.json"

BAND_NAMES = ["CHIRPS", "DEM", "NDVI", "Slope", "TWI"]
NODATA = -9999.0
MAX_TILE_SIDE_PIXELS = 1024


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


FORBIDDEN_SAMPLE_FIELDS = {
    "code", "sample_code", "sample_id", "point_id", "lat", "latitude",
    "lon", "long", "longitude", "x", "y", "x_utm", "y_utm",
    "covariate_support_status",
}


def validate_privacy_preserving_support_geometry(path):
    """Fail before GEE initialization unless preflight certified minimal support."""
    if not SUPPORT_GEOMETRY_PROVENANCE_FILE.exists():
        raise RuntimeError("Support geometry privacy provenance is missing.")
    try:
        provenance = json.loads(
            SUPPORT_GEOMETRY_PROVENANCE_FILE.read_text(encoding="utf-8")
        )
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError("Support geometry privacy provenance is unreadable.") from error

    allowed_columns = {
        "support_geometry_policy", "support_buffer_m", "contains_sample_attributes"
    }
    expected_source = "reviewed_roi_bounding_envelope_plus_fixed_metric_buffer"
    expected_schema = sorted(allowed_columns)
    checks = {
        "schema_version": provenance.get("schema_version") == "1.0.0",
        "provenance_type": provenance.get("provenance_type")
        == "privacy_preserving_support_geometry",
        "status": provenance.get("status") == "certified_by_preflight",
        "project_id": str(provenance.get("project_id")) == str(CFG["project_id"]),
        "policy": provenance.get("support_geometry_policy")
        == SUPPORT_GEOMETRY_POLICY,
        "geometry_source": provenance.get("geometry_source") == expected_source,
        "geometry_derivation": provenance.get("geometry_derivation")
        == SUPPORT_GEOMETRY_DERIVATION,
        "coverage_guarantee": provenance.get("coverage_guarantee")
        == "contains_the_fixed_metric_buffer_of_the_reviewed_roi",
        "project_crs": str(provenance.get("project_crs", "")).upper() == CRS.upper(),
        "feature_count": provenance.get("feature_count") == 1,
        "attribute_schema": sorted(provenance.get("attribute_schema", []))
        == expected_schema,
        "contains_sample_attributes": provenance.get("contains_sample_attributes")
        is False,
        "sample_geometry_not_used": provenance.get(
            "sample_coordinates_or_identifiers_used_to_define_geometry"
        ) is False,
        "sample_attributes_not_used": provenance.get(
            "sample_coordinates_or_identifiers_in_attributes"
        ) is False,
        "roi_hash": str(provenance.get("roi_field_area_sha256", "")).lower()
        == sha256_file(ROI_FILE),
        "support_hash": str(
            provenance.get("support_geometry_file_sha256", "")
        ).lower() == sha256_file(path),
    }
    try:
        checks["buffer_m"] = np.isclose(
            float(provenance.get("support_buffer_m")),
            SUPPORT_BUFFER_M,
            rtol=0.0,
            atol=1e-9,
        )
    except (TypeError, ValueError):
        checks["buffer_m"] = False
    failed = sorted(name for name, passed in checks.items() if not bool(passed))
    if failed:
        raise RuntimeError(
            "Support geometry privacy provenance mismatch: " + ", ".join(failed)
        )

    support = gpd.read_file(path)
    support = support[support.geometry.notna() & ~support.geometry.is_empty].copy()
    if len(support) != 1:
        raise RuntimeError("Support geometry must contain exactly one fixed ROI-buffer feature.")
    if support.crs is None or support.crs.to_epsg() != int(CFG["crs_epsg"]):
        raise RuntimeError("Support geometry CRS does not match the project CRS.")
    attribute_columns = {
        str(column).strip().casefold() for column in support.columns if column != "geometry"
    }
    forbidden = sorted(attribute_columns & FORBIDDEN_SAMPLE_FIELDS)
    unexpected = sorted(attribute_columns - allowed_columns)
    missing = sorted(allowed_columns - attribute_columns)
    if forbidden:
        raise RuntimeError(
            "Support geometry contains prohibited sample-derived fields: "
            + ", ".join(forbidden)
        )
    if unexpected or missing:
        raise RuntimeError(
            "Support geometry attribute schema is not privacy-minimal; "
            f"unexpected={unexpected}, missing={missing}."
        )
    policies = {
        str(value).strip() for value in support["support_geometry_policy"].dropna()
    }
    if policies != {SUPPORT_GEOMETRY_POLICY}:
        raise RuntimeError("Support geometry policy does not match project configuration.")
    buffer_values = np.asarray(support["support_buffer_m"], dtype=float)
    if buffer_values.size != 1 or not np.isfinite(buffer_values[0]) or not np.isclose(
        buffer_values[0], SUPPORT_BUFFER_M, rtol=0.0, atol=1e-9
    ):
        raise RuntimeError("Support buffer distance does not match project configuration.")
    declared = support["contains_sample_attributes"].astype(str).str.strip().str.casefold()
    if not declared.isin({"false", "0", "no"}).all():
        raise RuntimeError("Support geometry does not explicitly declare zero sample attributes.")
    if not support.geometry.geom_type.isin({"Polygon", "MultiPolygon"}).all():
        raise RuntimeError("Support geometry must be polygonal.")

    return {
        "status": "verified_before_gee_initialization",
        "support_geometry_policy": SUPPORT_GEOMETRY_POLICY,
        "geometry_source": expected_source,
        "geometry_derivation": SUPPORT_GEOMETRY_DERIVATION,
        "coverage_guarantee": "contains_the_fixed_metric_buffer_of_the_reviewed_roi",
        "support_buffer_m": SUPPORT_BUFFER_M,
        "geometry_certified_by_preflight_hash_chain": True,
        "attribute_schema_exact_and_privacy_minimal": True,
        "roi_hash_matches_current_file": True,
        "support_hash_matches_current_file": True,
        "sample_coordinates_or_identifiers_sent": False,
        "forbidden_sample_fields_present": [],
        "preflight_geometry_provenance_sha256": sha256_file(
            SUPPORT_GEOMETRY_PROVENANCE_FILE
        ),
    }

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


def build_aligned_union_grid(template, buffer_path):
    """Return a north-up grid aligned to template and containing both extents."""
    if not np.isclose(template.transform.b, 0.0) or not np.isclose(template.transform.d, 0.0):
        raise RuntimeError("Rotated Workflow 1 grids are not supported.")
    buffers = gpd.read_file(buffer_path).to_crs(template.crs)
    buffers = buffers[buffers.geometry.notna() & ~buffers.geometry.is_empty]
    if buffers.empty:
        raise RuntimeError("Support buffer layer is empty.")
    left, bottom, right, top = buffers.total_bounds
    raw = rasterio.windows.from_bounds(left, bottom, right, top, template.transform)
    col0 = min(0, math.floor(raw.col_off))
    row0 = min(0, math.floor(raw.row_off))
    col1 = max(template.width, math.ceil(raw.col_off + raw.width))
    row1 = max(template.height, math.ceil(raw.row_off + raw.height))
    width = int(col1 - col0)
    height = int(row1 - row0)
    if width <= 0 or height <= 0:
        raise RuntimeError("Expanded support grid has invalid dimensions.")
    transform = rasterio.windows.transform(
        Window(col0, row0, width, height), template.transform
    )
    profile = template.profile.copy()
    profile.update(width=width, height=height, transform=transform)
    return SimpleNamespace(
        crs=template.crs,
        transform=transform,
        width=width,
        height=height,
        profile=profile,
    )


def aligned_windows(buffer_path, template):
    """Split support bounds into bounded GEE requests on the aligned grid."""
    buffers = gpd.read_file(buffer_path).to_crs(template.crs)
    buffers = buffers[buffers.geometry.notna() & ~buffers.geometry.is_empty]
    if buffers.empty:
        return []
    geometry = buffers.geometry
    merged = geometry.union_all() if hasattr(geometry, "union_all") else geometry.unary_union
    pieces = list(merged.geoms) if hasattr(merged, "geoms") else [merged]
    window_keys = set()
    for geom in pieces:
        left, bottom, right, top = geom.bounds
        raw = rasterio.windows.from_bounds(left, bottom, right, top, template.transform)
        col0 = max(0, math.floor(raw.col_off))
        row0 = max(0, math.floor(raw.row_off))
        col1 = min(template.width, math.ceil(raw.col_off + raw.width))
        row1 = min(template.height, math.ceil(raw.row_off + raw.height))
        for row in range(row0, row1, MAX_TILE_SIDE_PIXELS):
            height = min(MAX_TILE_SIDE_PIXELS, row1 - row)
            for col in range(col0, col1, MAX_TILE_SIDE_PIXELS):
                width = min(MAX_TILE_SIDE_PIXELS, col1 - col)
                if width > 0 and height > 0:
                    window_keys.add((col, row, width, height))
    return [Window(*key) for key in sorted(window_keys, key=lambda x: (x[1], x[0]))]


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


def grid_identity(grid):
    west, south, east, north = array_bounds(grid.height, grid.width, grid.transform)
    return {
        "crs": grid.crs.to_string(),
        "computational_grid_m": float(abs(grid.transform.a)),
        "width": int(grid.width),
        "height": int(grid.height),
        "transform": [
            float(grid.transform.a),
            float(grid.transform.b),
            float(grid.transform.c),
            float(grid.transform.d),
            float(grid.transform.e),
            float(grid.transform.f),
        ],
        "bounds": [float(west), float(south), float(east), float(north)],
        "alignment_policy": "pixel-aligned union of Workflow 1 grid and support buffers",
    }


def write_json_atomic(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    temporary.replace(path)


def main():
    if not BUFFER_FILE.exists():
        raise FileNotFoundError(
            f"Support buffers not found: {BUFFER_FILE}. Run preflight first."
        )
    if not TEMPLATE_FILE.exists():
        raise FileNotFoundError(f"Workflow 1 PC template not found: {TEMPLATE_FILE}")
    if not ROI_FILE.exists():
        raise FileNotFoundError(f"ROI file not found: {ROI_FILE}")

    support_privacy = validate_privacy_preserving_support_geometry(BUFFER_FILE)
    PROVENANCE_FILE.unlink(missing_ok=True)
    ee.Initialize(project=GEE_PROJECT_ID)
    stack = build_image_stack()
    shutil.rmtree(TILE_DIR, ignore_errors=True)
    TILE_DIR.mkdir(parents=True, exist_ok=True)
    QA_DIR.mkdir(parents=True, exist_ok=True)

    with rasterio.open(TEMPLATE_FILE) as legacy_template:
        expanded_grid = build_aligned_union_grid(legacy_template, BUFFER_FILE)
        windows = aligned_windows(BUFFER_FILE, expanded_grid)
        if not windows:
            raise RuntimeError("No support window intersects the expanded aligned grid.")
        outputs = initialize_outputs(expanded_grid)
        to_wgs84 = Transformer.from_crs(expanded_grid.crs, "EPSG:4326", always_xy=True)
        completed = 0
        try:
            for idx, window in enumerate(windows, start=1):
                print(f"[{idx}/{len(windows)}] Downloading GEE support tile...", flush=True)
                tile_path = export_tile(stack, idx, window, expanded_grid, to_wgs84)
                write_tile_to_outputs(tile_path, window, expanded_grid, outputs)
                completed += 1
        finally:
            for ds in outputs.values():
                ds.close()

    raw_hashes = {
        name: sha256_file(SOURCE_DIR / f"{name}.tif") for name in BAND_NAMES
    }
    summary = {
        "schema_version": "2.0.0",
        "provenance_type": "gee_covariate_support_download",
        "status": "complete",
        "project_id": str(CFG["project_id"]),
        "source_identity": {
            "gee_project_id": GEE_PROJECT_ID,
            "start_date": START_DATE,
            "end_date": END_DATE,
            "roi_field_area_sha256": sha256_file(ROI_FILE),
            "support_buffer_sha256": sha256_file(BUFFER_FILE),
            "support_geometry_policy": SUPPORT_GEOMETRY_POLICY,
            "support_geometry_provenance_sha256": sha256_file(SUPPORT_GEOMETRY_PROVENANCE_FILE),
            "legacy_grid_template_sha256": sha256_file(TEMPLATE_FILE),
        },
        "output_grid": grid_identity(expanded_grid),
        "privacy_gate": support_privacy,
        "bands": BAND_NAMES,
        "support_windows": len(windows),
        "completed_windows": completed,
        "max_tile_side_pixels": MAX_TILE_SIDE_PIXELS,
        "max_window_pixel_count": max(int(window.width * window.height) for window in windows),
        "raw_covariate_sha256": raw_hashes,
        "output_dir": str(SOURCE_DIR).replace("\\", "/"),
        "generated_utc": datetime.now(timezone.utc).isoformat(),
    }
    if completed != len(windows):
        raise RuntimeError("Support download did not complete every planned window.")
    write_json_atomic(PROVENANCE_FILE, summary)
    shutil.rmtree(TILE_DIR, ignore_errors=True)
    print("GEE support download complete with schema-v2 provenance.", flush=True)


if __name__ == "__main__":
    main()
