"""Prepare deterministic, explicitly synthetic inputs for PHU_YEN_MOCK.

This helper is intentionally project-local. It does not alter the production
interpretation or sampling gates. The generated field-area geometry and labels
are simulation fixtures only and must never be promoted to real sugarcane data.
"""

from __future__ import annotations

import hashlib
import json
import math
from datetime import datetime, timezone
from pathlib import Path

import geopandas as gpd
import pandas as pd
import pyogrio
from shapely.geometry import box


PROJECT = Path(__file__).resolve().parents[2]
ROOT = PROJECT.parents[1]
STAGE0_INPUT = PROJECT / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO"
STAGE1_INPUT = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO"
WORK = PROJECT / "_NOI_BO" / "work" / "field_area"
ADM1_SOURCE = WORK / "VNM_ADM1_geoboundaries_2008.geojson"
SOIL_CANONICAL = ROOT / "shared_data" / "soil_type_vietnam" / "raw" / "VN_soil_type.geojson"
ROI_SEARCH = STAGE0_INPUT / "roi_search.geojson"
MOCK_FIELD_AREA = STAGE0_INPUT / "roi_field_area.geojson"
MOCK_LABELS = STAGE0_INPUT / "sugarcane_labels.csv"
SOIL_OUTPUT = STAGE1_INPUT / "soil_type.geojson"
METADATA_OUTPUT = STAGE0_INPUT / "MOCK_INPUT_METADATA.json"

PROJECTED_EPSG = 32649
GRID_SIZE_M = 500
SELECTION_PERCENT = 8
RANDOM_SEED = 20260715


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def stable_bucket(row: int, col: int, seed: int = RANDOM_SEED) -> int:
    payload = f"{seed}:{row}:{col}".encode("ascii")
    return int.from_bytes(hashlib.sha256(payload).digest()[:8], "big") % 100


def repair(gdf: gpd.GeoDataFrame) -> gpd.GeoDataFrame:
    result = gdf.copy()
    result.geometry = result.geometry.make_valid()
    result = result[result.geometry.notna() & ~result.geometry.is_empty].copy()
    return result


def read_phu_yen_boundary() -> gpd.GeoDataFrame:
    if not ADM1_SOURCE.exists():
        raise FileNotFoundError(f"Missing downloaded geoBoundaries ADM1: {ADM1_SOURCE}")
    adm1 = gpd.read_file(ADM1_SOURCE)
    selected = adm1.loc[adm1["shapeISO"].astype(str).eq("VN-32")].copy()
    if len(selected) != 1:
        raise ValueError(f"Expected one VN-32 feature, found {len(selected)}")
    selected = repair(selected.to_crs(4326))
    selected["mock_scope"] = "historical_Phu_Yen_pre_2025_reorganization"
    selected["boundary_year_represented"] = 2008
    selected["boundary_source"] = "geoBoundaries VNM ADM1, public domain"
    selected["boundary_id"] = "VNM-ADM1-63759600"
    selected["use_policy"] = "MOCK_TEST_ONLY_NOT_AUTHORITATIVE_CURRENT_BOUNDARY"
    return selected


def extract_soil(boundary: gpd.GeoDataFrame) -> gpd.GeoDataFrame:
    soil_source = SOIL_CANONICAL
    if not soil_source.exists():
        raise FileNotFoundError(f"Missing national Soil Type: {SOIL_CANONICAL}")
    fields = [
        "fid",
        "Dat_ID",
        "Ma1",
        "DoDoc",
        "Ma2",
        "TPCG",
        "TDay",
        "MoTa",
        "CoGioi",
        "TangDay",
        "layer",
    ]
    soil = pyogrio.read_dataframe(
        soil_source,
        columns=fields,
        where="layer = 'Soil_PhuYen'",
        bbox=tuple(float(v) for v in boundary.total_bounds),
        force_2d=True,
    )
    if soil.empty:
        raise ValueError("No Soil_PhuYen features were found in VN_soil_type.geojson")
    soil = repair(soil.to_crs(4326))
    province = boundary.geometry.union_all()
    soil = soil.loc[soil.geometry.intersects(province)].copy()
    soil.geometry = soil.geometry.intersection(province)
    soil = repair(soil)
    soil["mock_project"] = "PHU_YEN_MOCK"
    soil["source_file"] = "shared_data/soil_type_vietnam/raw/VN_soil_type.geojson"
    return soil


def synthetic_field_cells(boundary: gpd.GeoDataFrame) -> gpd.GeoDataFrame:
    projected = boundary.to_crs(epsg=PROJECTED_EPSG)
    province = projected.geometry.union_all()
    left, bottom, right, top = province.bounds
    left = math.floor(left / GRID_SIZE_M) * GRID_SIZE_M
    bottom = math.floor(bottom / GRID_SIZE_M) * GRID_SIZE_M
    right = math.ceil(right / GRID_SIZE_M) * GRID_SIZE_M
    top = math.ceil(top / GRID_SIZE_M) * GRID_SIZE_M

    rows: list[dict[str, object]] = []
    row_id = 0
    y = bottom
    while y < top:
        col_id = 0
        x = left
        while x < right:
            if stable_bucket(row_id, col_id) < SELECTION_PERCENT:
                cell = box(x, y, x + GRID_SIZE_M, y + GRID_SIZE_M)
                clipped = cell.intersection(province)
                if not clipped.is_empty and clipped.area >= 10_000:
                    rows.append(
                        {
                            "mock_field_id": f"PYM_{row_id:04d}_{col_id:04d}",
                            "mock_only": True,
                            "synthetic_class": "sugarcane_fixture",
                            "selection_algorithm": "sha256_grid_bucket",
                            "geometry": clipped,
                        }
                    )
            x += GRID_SIZE_M
            col_id += 1
        y += GRID_SIZE_M
        row_id += 1
    fields = gpd.GeoDataFrame(rows, geometry="geometry", crs=f"EPSG:{PROJECTED_EPSG}")
    if fields.empty:
        raise ValueError("Synthetic field selection unexpectedly produced no polygons")
    fields["area_ha"] = fields.geometry.area / 10_000
    return fields.to_crs(4326)


def synthetic_labels(
    boundary: gpd.GeoDataFrame, fields: gpd.GeoDataFrame, n_per_class: int = 250
) -> pd.DataFrame:
    province = boundary.to_crs(epsg=PROJECTED_EPSG).geometry.union_all()
    cane = fields.to_crs(epsg=PROJECTED_EPSG)
    positives = cane.geometry.centroid
    positive_points = list(positives.iloc[:n_per_class])

    field_union = cane.geometry.union_all()
    negative_points = []
    minx, miny, maxx, maxy = province.bounds
    step = 3_000
    y = miny + step / 2
    while y < maxy and len(negative_points) < n_per_class:
        x = minx + step / 2
        while x < maxx and len(negative_points) < n_per_class:
            point = box(x - 1, y - 1, x + 1, y + 1).centroid
            if province.contains(point) and field_union.distance(point) >= 1_000:
                negative_points.append(point)
            x += step
        y += step
    if len(positive_points) < 50 or len(negative_points) < 50:
        raise ValueError("Not enough spatially distributed synthetic labels")

    records = []
    for label, points in ((1, positive_points), (0, negative_points)):
        points_wgs84 = gpd.GeoSeries(points, crs=PROJECTED_EPSG).to_crs(4326)
        for idx, point in enumerate(points_wgs84, start=1):
            records.append(
                {
                    "code": f"MOCK_{'POS' if label else 'NEG'}_{idx:04d}",
                    "lat": round(float(point.y), 8),
                    "lon": round(float(point.x), 8),
                    "label": label,
                    "group_id": "",
                    "label_source": "SYNTHETIC_FIXTURE_NOT_FIELD_VERIFIED",
                    "observation_date": "",
                    "reviewer": "",
                    "note": "MOCK ONLY; ineligible for production training or validation",
                }
            )
    return pd.DataFrame.from_records(records)


def main() -> None:
    for directory in (STAGE0_INPUT, STAGE1_INPUT, WORK):
        directory.mkdir(parents=True, exist_ok=True)

    boundary = read_phu_yen_boundary()
    boundary.to_file(ROI_SEARCH, driver="GeoJSON", index=False)
    soil = extract_soil(boundary)
    soil.to_file(SOIL_OUTPUT, driver="GeoJSON", index=False)
    fields = synthetic_field_cells(boundary)
    fields.to_file(MOCK_FIELD_AREA, driver="GeoJSON", index=False)
    labels = synthetic_labels(boundary, fields)
    labels.to_csv(MOCK_LABELS, index=False, encoding="utf-8")

    boundary_projected = boundary.to_crs(epsg=PROJECTED_EPSG)
    metadata = {
        "schema_version": 1,
        "created_utc": utc_now(),
        "project_id": "PHU_YEN_MOCK",
        "mock_only": True,
        "validated_sugarcane_map": False,
        "authoritative_current_boundary": False,
        "scope": "historical Phu Yen province before the 2025 provincial reorganization",
        "roi_search": {
            "source": "geoBoundaries VNM ADM1",
            "boundary_id": "VNM-ADM1-63759600",
            "shape_iso": "VN-32",
            "year_represented": 2008,
            "license": "Public Domain",
            "area_ha": round(float(boundary_projected.geometry.area.sum() / 10_000), 2),
        },
        "soil_type": {
            "source": "shared_data/soil_type_vietnam/raw/VN_soil_type.geojson",
            "source_layer_filter": "Soil_PhuYen",
            "n_features": int(len(soil)),
            "soil_group_field": "Ma1",
        },
        "synthetic_field_area": {
            "algorithm": "500 m grid cells selected by deterministic SHA-256 bucket",
            "selection_percent": SELECTION_PERCENT,
            "random_seed": RANDOM_SEED,
            "n_fields": int(len(fields)),
            "area_ha": round(float(fields.to_crs(epsg=PROJECTED_EPSG).geometry.area.sum() / 10_000), 2),
        },
        "synthetic_labels": {
            "n_positive": int((labels["label"] == 1).sum()),
            "n_negative": int((labels["label"] == 0).sum()),
            "verified": False,
            "production_eligible": False,
        },
        "safety": [
            "All generated sugarcane fields, labels and later laboratory values are synthetic.",
            "Do not use them for production training, accuracy claims, agronomic decisions or fertilizer recommendations.",
            "Replace roi_field_area and labels with reviewed local evidence before any real Phu Yen study.",
        ],
    }
    METADATA_OUTPUT.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(metadata, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
