#!/usr/bin/env python3
"""Build or validate a sugarcane field-area ROI before sample design.

The workflow deliberately separates three products:
1. an observed/reviewed ``roi_field_area`` that may feed sample design;
2. a model probability/candidate layer that must not feed sample design directly;
3. a reusable reference/model package whose transfer status is explicit.

The implementation does not manufacture absence labels from random points.  A
binary model requires locally verified sugarcane and non-sugarcane labels.
Positive-only data are saved as a reference package, never advertised as a
trained, transferable binary classifier.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import io
import json
import math
import os
import random
import shutil
import sys
import tempfile
import time
import zipfile
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable

import geopandas as gpd
import numpy as np
import pandas as pd
from shapely.geometry import box, mapping, shape
from shapely.ops import unary_union


SCHEMA_VERSION = "sugarcane-field-area-v1"
METHOD_ID = "sentinel1_sentinel2_temporal_random_forest_spatial_holdout_v1"
S2_COLLECTION = "COPERNICUS/S2_SR_HARMONIZED"
S2_QA_COLLECTION = "GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED"
S1_COLLECTION = "COPERNICUS/S1_GRD"
WORLD_COVER = "ESA/WorldCover/v200"


DEFAULTS: dict[str, Any] = {
    "mode": "auto",
    "target_year": date.today().year,
    "history_years": 2,
    "resolution_m": 10,
    "crs_epsg": 32649,
    "gee_project_id": "",
    "cloud_score_threshold": 0.60,
    "cloudy_scene_percentage": 80,
    "spatial_block_m": 5000,
    "spatial_folds": 5,
    "random_seed": 42,
    "rf_trees": 300,
    "rf_min_leaf": 5,
    "rf_bag_fraction": 0.70,
    "max_samples_per_class": 5000,
    "min_groups_per_class": 3,
    "min_outer_test_per_class": 10,
    "minimum_field_area_ha": 0.10,
    "probability_threshold_default": 0.55,
    "minimum_outer_f1": 0.70,
    "minimum_outer_precision": 0.65,
    "minimum_outer_recall": 0.65,
    "tile_km": 5,
    "reference_max_points": 1000,
    "reference_min_field_area_ha": 0.10,
    "reference_inner_buffer_m": 10,
    "reuse_reference_positive": False,
    "reference_package": "",
    "allow_positive_only_screening": False,
    "reference_domain_sample_limit": 2000,
    "reference_minimum_row_fraction": 0.80,
    "reference_minimum_predictor_fraction": 0.90,
    "reference_max_fraction_of_local_training": 0.25,
}


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def parse_scalar(raw: str) -> Any:
    value = raw.strip()
    if not value:
        return ""
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    low = value.lower()
    if low in {"true", "yes", "on"}:
        return True
    if low in {"false", "no", "off"}:
        return False
    if low in {"null", "none", "~"}:
        return None
    try:
        return int(value)
    except ValueError:
        try:
            return float(value)
        except ValueError:
            return value


def read_flat_yaml(path: Path) -> dict[str, Any]:
    """Read the intentionally flat, dependency-free user configuration."""
    result: dict[str, Any] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if line[:1].isspace() or ":" not in stripped:
            raise ValueError(
                f"{path.name}:{line_number}: interpretation.yml only supports flat key: value entries"
            )
        key, raw = stripped.split(":", 1)
        key = key.strip()
        if not key:
            raise ValueError(f"{path.name}:{line_number}: empty key")
        result[key] = parse_scalar(raw.split(" #", 1)[0])
    return result


def write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_reference_reuse_module() -> Any:
    path = Path(__file__).with_name("sugarcane_reference_reuse.py")
    spec = importlib.util.spec_from_file_location("sugarcane_reference_reuse_runtime", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load TRAIN-only reference module: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def stable_fold(value: str, seed: int, n_folds: int) -> int:
    token = hashlib.sha256(f"{seed}|{value}".encode("utf-8")).hexdigest()
    return int(token[:12], 16) % n_folds


def safe_make_valid(gdf: gpd.GeoDataFrame) -> tuple[gpd.GeoDataFrame, int]:
    out = gdf.copy()
    before = int((~out.geometry.is_valid).sum())
    if before:
        try:
            out.geometry = out.geometry.make_valid()
        except AttributeError:
            out.geometry = out.geometry.buffer(0)
    out = out[out.geometry.notna() & ~out.geometry.is_empty].copy()
    return out, before


def read_vector(path: Path) -> gpd.GeoDataFrame:
    gdf = gpd.read_file(path)
    if gdf.crs is None:
        raise ValueError(f"Missing CRS: {path}")
    gdf, _ = safe_make_valid(gdf)
    if gdf.empty:
        raise ValueError(f"No valid geometry: {path}")
    return gdf


def geometry_summary(path: Path, crs_epsg: int) -> tuple[gpd.GeoDataFrame, dict[str, Any]]:
    gdf = gpd.read_file(path)
    if gdf.crs is None:
        raise ValueError(f"Missing CRS: {path}")
    gdf, repaired = safe_make_valid(gdf)
    projected = gdf.to_crs(epsg=crs_epsg)
    area_ha = float(projected.geometry.area.sum() / 10000.0)
    bounds = [float(x) for x in gdf.to_crs(4326).total_bounds]
    return gdf, {
        "path": str(path.resolve()),
        "sha256": sha256_file(path),
        "crs": str(gdf.crs),
        "feature_count": int(len(gdf)),
        "invalid_geometries_repaired": repaired,
        "area_ha": area_ha,
        "bounds_wgs84": bounds,
    }


@dataclass
class ProjectPaths:
    project: Path
    stage: Path
    input: Path
    result: Path
    internal: Path
    work: Path
    qa: Path

    @classmethod
    def from_project(cls, project: Path) -> "ProjectPaths":
        stage = project / "00_XAC_LAP_VUNG_MIA"
        internal = project / "_NOI_BO"
        return cls(
            project=project,
            stage=stage,
            input=stage / "01_DAU_VAO",
            result=stage / "02_KET_QUA",
            internal=internal,
            work=internal / "work" / "field_area",
            qa=internal / "work" / "field_area" / "qa",
        )

    def ensure(self) -> None:
        for path in (self.input, self.result, self.work, self.qa):
            path.mkdir(parents=True, exist_ok=True)


def config_for(paths: ProjectPaths) -> tuple[dict[str, Any], Path]:
    config_path = paths.input / "interpretation.yml"
    if not config_path.exists():
        raise FileNotFoundError(f"Missing configuration: {config_path}")
    config = dict(DEFAULTS)
    config.update(read_flat_yaml(config_path))
    if int(config["spatial_folds"]) < 3:
        raise ValueError("spatial_folds must be at least 3 (train, threshold calibration, outer test)")
    if int(config["history_years"]) < 1:
        raise ValueError("history_years must be at least 1")
    return config, config_path


def locate_inputs(paths: ProjectPaths) -> dict[str, Path | None]:
    def first_existing(names: Iterable[str]) -> Path | None:
        for name in names:
            candidate = paths.input / name
            if candidate.exists():
                return candidate
        return None

    field = first_existing(("roi_field_area.geojson",))
    return {
        "roi_field_area": field,
        "roi_search": first_existing(("roi_search.geojson", "roi_search.gpkg", "roi_search.shp")),
        "labels": first_existing(
            (
                "sugarcane_labels.csv",
                "sugarcane_labels.geojson",
                "sugarcane_labels.gpkg",
                "sugarcane_labels.shp",
            )
        ),
    }


def write_reference_package(
    paths: ProjectPaths,
    field_gdf: gpd.GeoDataFrame,
    source_summary: dict[str, Any],
    config: dict[str, Any],
) -> dict[str, Any]:
    package = paths.work / "reference_package"
    package.mkdir(parents=True, exist_ok=True)
    projected = field_gdf.to_crs(epsg=int(config["crs_epsg"]))
    n_source = int(len(projected))
    polygon_mask = projected.geometry.geom_type.isin(["Polygon", "MultiPolygon"])
    n_non_polygon = int((~polygon_mask).sum())
    polygons = projected.loc[polygon_mask, [projected.geometry.name]].copy()
    polygons["source_feature_index"] = polygons.index.map(str)
    min_area_ha = float(config.get("reference_min_field_area_ha", 0.10))
    area_mask = polygons.geometry.area >= min_area_ha * 10000.0
    n_small = int((~area_mask).sum())
    eligible = polygons.loc[area_mask].copy()
    inner_buffer_m = float(config.get("reference_inner_buffer_m", 10))
    if inner_buffer_m < 0:
        raise ValueError("reference_inner_buffer_m must be non-negative")
    inner_geometry = eligible.geometry.buffer(-inner_buffer_m) if inner_buffer_m else eligible.geometry
    core_mask = inner_geometry.apply(lambda geom: geom is not None and not geom.is_empty)
    n_no_inner_core = int((~core_mask).sum())
    eligible = eligible.loc[core_mask].copy()
    eligible.geometry = inner_geometry.loc[core_mask]
    reps = eligible.copy()
    reps.geometry = reps.geometry.representative_point()
    reps = reps[reps.geometry.notna() & ~reps.geometry.is_empty].copy().to_crs(4326)
    n_eligible_before_limit = int(len(reps))
    if reps.empty:
        raise ValueError("No field polygon remains after minimum-area and inner-buffer reference gates")
    reps["_order"] = reps.geometry.apply(lambda geom: hashlib.sha256(geom.wkb).hexdigest())
    reps = reps.sort_values("_order")
    max_points = int(config["reference_max_points"])
    if len(reps) > max_points:
        indices = np.linspace(0, len(reps) - 1, max_points, dtype=int)
        reps = reps.iloc[indices].copy()
    n_excluded_by_limit = n_eligible_before_limit - int(len(reps))
    reps = reps.drop(columns=["_order"])
    reps["label"] = 1
    reps["label_name"] = "sugarcane"
    reps["label_basis"] = "representative_point_inside_buffered_confirmed_field_core"
    reps["evaluation_eligible"] = False
    reps["source_project"] = paths.project.name
    refs_path = package / "positive_reference.geojson"
    reps.to_file(refs_path, driver="GeoJSON")

    feature_schema = feature_schema_for(config)
    write_json(package / "feature_schema.json", feature_schema)
    card = {
        "schema_version": SCHEMA_VERSION,
        "package_id": f"{paths.project.name}_positive_reference_v2",
        "created_utc": utc_now(),
        "artifact_type": "positive_reference_only",
        "binary_classifier_trained": False,
        "has_verified_negative_labels": False,
        "independent_validation": False,
        "spatial_outer_holdout_validation": False,
        "transferable_validated_model": False,
        "allowed_use": [
            "candidate training reference after local expert review",
            "training-fold augmentation only when a new project has local positive and negative labels",
        ],
        "prohibited_use": [
            "direct inference as a pretrained generalizable sugarcane model",
            "use in threshold calibration or test folds of another project",
            "automatic promotion of a candidate map to roi_field_area",
        ],
        "source_roi": source_summary,
        "positive_reference": {
            "path": str(refs_path.resolve()),
            "sha256": sha256_file(refs_path),
            "n_points": int(len(reps)),
            "selection": {
                "source_features": n_source,
                "excluded_non_polygon": n_non_polygon,
                "excluded_below_minimum_area": n_small,
                "excluded_without_inner_core": n_no_inner_core,
                "eligible_before_max_points": n_eligible_before_limit,
                "excluded_by_max_points_limit": n_excluded_by_limit,
                "selected_points": int(len(reps)),
                "reference_min_field_area_ha": min_area_ha,
                "reference_inner_buffer_m": inner_buffer_m,
                "reference_max_points": max_points,
                "point_method": "representative_point_after_negative_buffer",
            },
        },
        "scientific_reason": (
            f"{paths.project.name} supplies confirmed sugarcane geometry but no verified non-sugarcane class; "
            "positive-only geometry is insufficient to identify a binary decision boundary."
        ),
    }
    write_json(package / "model_card.json", card)
    return card


def approve_direct_field_area(
    paths: ProjectPaths,
    field_path: Path,
    config: dict[str, Any],
    config_path: Path,
) -> dict[str, Any]:
    field_gdf, summary = geometry_summary(field_path, int(config["crs_epsg"]))
    reference = write_reference_package(paths, field_gdf, summary, config)

    design_roi = field_path.resolve()
    sync_state = "canonical_stage0_input"
    qa = {
        "schema_version": SCHEMA_VERSION,
        "created_utc": utc_now(),
        "mode": "provided_or_reviewed_field_area",
        "status": "APPROVED_FOR_SAMPLE_DESIGN",
        "classification_run": False,
        "field_area_source": summary,
        "sample_design_roi": {
            "path": str(design_roi.resolve()),
            "sync_state": sync_state,
            "sha256": sha256_file(design_roi),
        },
        "reference_package_status": reference["artifact_type"],
        "reference_is_transferable_model": False,
        "config": {
            "path": str(config_path.resolve()),
            "sha256": sha256_file(config_path),
        },
        "next_step": "run sample design",
    }
    write_json(paths.result / "field_area_QA.json", qa)
    write_json(
        paths.result / "roi_field_area_pointer.json",
        {
            "status": qa["status"],
            "canonical_path": str(design_roi.resolve()),
            "sha256": qa["sample_design_roi"]["sha256"],
            "note": "The canonical ROI remains in Stage 0 and is read directly by downstream workflows.",
        },
    )
    return qa


def read_labels(path: Path, crs_epsg: int, block_m: float, n_folds: int, seed: int) -> gpd.GeoDataFrame:
    if path.suffix.lower() == ".csv":
        data = pd.read_csv(path)
        missing = {"lat", "lon", "label"} - set(data.columns)
        if missing:
            raise ValueError(f"sugarcane_labels.csv missing columns: {sorted(missing)}")
        gdf = gpd.GeoDataFrame(
            data,
            geometry=gpd.points_from_xy(data["lon"], data["lat"]),
            crs="EPSG:4326",
        )
    else:
        gdf = read_vector(path)
        if "label" not in gdf.columns:
            if "class" in gdf.columns:
                gdf = gdf.rename(columns={"class": "label"})
            else:
                raise ValueError("Label vector needs a label column with 1=sugarcane, 0=verified non-sugarcane")
    numeric = pd.to_numeric(gdf["label"], errors="coerce")
    if numeric.isna().any() or not set(numeric.astype(int).unique()).issubset({0, 1}):
        raise ValueError("label must contain only 0 or 1")
    gdf["label"] = numeric.astype(int)
    gdf, _ = safe_make_valid(gdf)
    projected = gdf.to_crs(epsg=crs_epsg)
    centers = projected.geometry.centroid
    computed_group = [f"{math.floor(x / block_m)}_{math.floor(y / block_m)}" for x, y in zip(centers.x, centers.y)]
    if "group_id" in gdf.columns:
        supplied = gdf["group_id"].fillna("").astype(str).str.strip()
        gdf["spatial_group"] = [s if s else c for s, c in zip(supplied, computed_group)]
    else:
        gdf["spatial_group"] = computed_group
    gdf["spatial_fold"] = [stable_fold(v, seed, n_folds) for v in gdf["spatial_group"]]
    gdf["evaluation_eligible"] = True
    return gdf.to_crs(4326)


def label_summary(labels: gpd.GeoDataFrame) -> dict[str, Any]:
    counts = labels.groupby("label").size().to_dict()
    groups = labels.groupby("label")["spatial_group"].nunique().to_dict()
    folds: dict[str, dict[str, int]] = {}
    for fold, part in labels.groupby("spatial_fold"):
        fold_counts = part.groupby("label").size().to_dict()
        folds[str(int(fold))] = {"negative": int(fold_counts.get(0, 0)), "positive": int(fold_counts.get(1, 0))}
    return {
        "n_labels": int(len(labels)),
        "n_negative": int(counts.get(0, 0)),
        "n_positive": int(counts.get(1, 0)),
        "negative_spatial_groups": int(groups.get(0, 0)),
        "positive_spatial_groups": int(groups.get(1, 0)),
        "fold_counts": folds,
    }


def select_calibration_and_test_folds(labels: gpd.GeoDataFrame, min_test: int) -> tuple[int, int]:
    eligible: list[tuple[int, int]] = []
    for fold, part in labels.groupby("spatial_fold"):
        counts = part.groupby("label").size().to_dict()
        minimum = min(int(counts.get(0, 0)), int(counts.get(1, 0)))
        if minimum >= min_test:
            eligible.append((int(fold), minimum))
    eligible.sort(key=lambda item: (-item[1], item[0]))
    if len(eligible) < 2:
        raise ValueError(
            "Need at least two spatial folds containing both classes: one for threshold calibration and one for outer testing"
        )
    test_fold = eligible[0][0]
    calibration_fold = eligible[1][0]
    training = labels[~labels["spatial_fold"].isin([test_fold, calibration_fold])]
    if set(training["label"].unique()) != {0, 1}:
        raise ValueError("Remaining spatial folds do not contain both classes for training")
    return calibration_fold, test_fold


def feature_schema_for(config: dict[str, Any]) -> dict[str, Any]:
    year = int(config["target_year"])
    history = int(config["history_years"])
    start_year = year - history + 1
    return {
        "schema_version": SCHEMA_VERSION,
        "method_id": METHOD_ID,
        "target_year": year,
        "temporal_window": {"start": f"{start_year}-01-01", "end_exclusive": f"{year + 1}-01-01"},
        "sentinel_2": {
            "collection": S2_COLLECTION,
            "quality_collection": S2_QA_COLLECTION,
            "surface_reflectance_scale_factor": 0.0001,
            "cloud_score_band": "cs_cdf",
            "cloud_score_threshold": float(config["cloud_score_threshold"]),
            "quarterly_features": ["NDVI", "EVI", "NDMI", "NDRE", "NBR2", "valid_count"],
        },
        "sentinel_1": {
            "collection": S1_COLLECTION,
            "input_unit": "dB",
            "additional_log_transform": False,
            "filters": {"instrumentMode": "IW", "polarizations": ["VV", "VH"]},
            "quarterly_features": ["VV_median_dB", "VH_median_dB", "VV_minus_VH_dB"],
        },
        "ancillary": {
            "worldcover": {"collection": WORLD_COVER, "role": "predictor_only_not_hard_mask"},
            "topography": "USGS/SRTMGL1_003",
        },
        "missing_data_policy": "masked predictor pixels are not converted to zero",
        "computational_grid_m": int(config["resolution_m"]),
        "native_resolution_warning": (
            f"A {float(config['resolution_m']):g} m computational/export cell alone "
            f"is not evidence that all predictors have {float(config['resolution_m']):g} m native detail."
        ),
    }


def gee_feature_stack(config: dict[str, Any], roi_geometry: Any) -> tuple[Any, list[str], dict[str, Any]]:
    import ee

    year = int(config["target_year"])
    history = int(config["history_years"])
    start = ee.Date.fromYMD(year - history + 1, 1, 1)
    end_exclusive = ee.Date.fromYMD(year + 1, 1, 1)

    s2 = (
        ee.ImageCollection(S2_COLLECTION)
        .filterBounds(roi_geometry)
        .filterDate(start, end_exclusive)
        .filter(ee.Filter.lt("CLOUDY_PIXEL_PERCENTAGE", float(config["cloudy_scene_percentage"])))
    )
    cs = ee.ImageCollection(S2_QA_COLLECTION).filterBounds(roi_geometry).filterDate(start, end_exclusive)

    def prep_s2(image: Any) -> Any:
        linked = ee.Image(image)
        clear = linked.select("cs_cdf").gte(float(config["cloud_score_threshold"]))
        sr = linked.select(["B2", "B3", "B4", "B5", "B6", "B7", "B8", "B8A", "B11", "B12"]).multiply(0.0001)
        ndvi = sr.normalizedDifference(["B8", "B4"]).rename("NDVI")
        evi = sr.expression(
            "2.5 * (nir-red) / (nir + 6*red - 7.5*blue + 1)",
            {"nir": sr.select("B8"), "red": sr.select("B4"), "blue": sr.select("B2")},
        ).rename("EVI")
        ndmi = sr.normalizedDifference(["B8", "B11"]).rename("NDMI")
        ndre = sr.normalizedDifference(["B8", "B5"]).rename("NDRE")
        nbr2 = sr.normalizedDifference(["B11", "B12"]).rename("NBR2")
        return ee.Image.cat([ndvi, evi, ndmi, ndre, nbr2]).updateMask(clear).copyProperties(image, ["system:time_start"])

    s2_prepared = s2.linkCollection(cs, ["cs_cdf"]).map(prep_s2)

    s1 = (
        ee.ImageCollection(S1_COLLECTION)
        .filterBounds(roi_geometry)
        .filterDate(start, end_exclusive)
        .filter(ee.Filter.eq("instrumentMode", "IW"))
        .filter(ee.Filter.listContains("transmitterReceiverPolarisation", "VV"))
        .filter(ee.Filter.listContains("transmitterReceiverPolarisation", "VH"))
        .select(["VV", "VH"])
    )

    def prep_s1(image: Any) -> Any:
        # COPERNICUS/S1_GRD is already calibrated, terrain-corrected and in dB.
        vv = image.select("VV").rename("VV")
        vh = image.select("VH").rename("VH")
        return ee.Image.cat([vv, vh, vv.subtract(vh).rename("VVminusVH")]).copyProperties(
            image, ["system:time_start"]
        )

    s1_prepared = s1.map(prep_s1)
    images: list[Any] = []
    band_names: list[str] = []
    for yr in range(year - history + 1, year + 1):
        for quarter in range(1, 5):
            month = (quarter - 1) * 3 + 1
            q_start = ee.Date.fromYMD(yr, month, 1)
            q_end = q_start.advance(3, "month")
            suffix = f"{yr}_Q{quarter}"
            s2_q = s2_prepared.filterDate(q_start, q_end)
            s1_q = s1_prepared.filterDate(q_start, q_end)
            s2_names = [f"{name}_{suffix}" for name in ("NDVI", "EVI", "NDMI", "NDRE", "NBR2")]
            s1_names = [f"{name}_{suffix}" for name in ("VV", "VH", "VVminusVH")]
            images.append(s2_q.select(["NDVI", "EVI", "NDMI", "NDRE", "NBR2"]).median().rename(s2_names))
            images.append(s2_q.select("NDVI").count().rename(f"S2_count_{suffix}"))
            images.append(s1_q.select(["VV", "VH", "VVminusVH"]).median().rename(s1_names))
            band_names.extend(s2_names + [f"S2_count_{suffix}"] + s1_names)

    dem = ee.Image("USGS/SRTMGL1_003").select("elevation").rename("elevation_m")
    slope = ee.Terrain.slope(dem).rename("slope_deg")
    worldcover = ee.ImageCollection(WORLD_COVER).first().select("Map").rename("worldcover_class")
    images.extend([dem, slope, worldcover])
    band_names.extend(["elevation_m", "slope_deg", "worldcover_class"])
    stack = ee.Image.cat(images).select(band_names).clip(roi_geometry)
    counts = {
        "s2_scene_count": int(s2.size().getInfo()),
        "s1_scene_count": int(s1.size().getInfo()),
        "band_count": len(band_names),
    }
    return stack, band_names, counts


def gdf_to_ee(gdf: gpd.GeoDataFrame) -> Any:
    import ee

    features = []
    for _, row in gdf.to_crs(4326).iterrows():
        props = {key: value for key, value in row.drop(labels=[gdf.geometry.name]).items() if pd.notna(value)}
        props = {key: (value.item() if hasattr(value, "item") else value) for key, value in props.items()}
        features.append(ee.Feature(ee.Geometry(mapping(row.geometry)), props))
    return ee.FeatureCollection(features)


def classification_metrics(y_true: list[int], probabilities: list[float], threshold: float) -> dict[str, Any]:
    predicted = [1 if p >= threshold else 0 for p in probabilities]
    tp = sum(int(y == 1 and p == 1) for y, p in zip(y_true, predicted))
    tn = sum(int(y == 0 and p == 0) for y, p in zip(y_true, predicted))
    fp = sum(int(y == 0 and p == 1) for y, p in zip(y_true, predicted))
    fn = sum(int(y == 1 and p == 0) for y, p in zip(y_true, predicted))
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    specificity = tn / (tn + fp) if tn + fp else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {
        "threshold": threshold,
        "n": len(y_true),
        "confusion": {"tn": tn, "fp": fp, "fn": fn, "tp": tp},
        "precision_user_accuracy_sugarcane": precision,
        "recall_producer_accuracy_sugarcane": recall,
        "specificity": specificity,
        "balanced_accuracy": (recall + specificity) / 2,
        "f1": f1,
    }


def best_threshold(y_true: list[int], probabilities: list[float], default: float) -> tuple[float, dict[str, Any]]:
    if not y_true or set(y_true) != {0, 1}:
        return default, {"status": "insufficient_calibration_classes"}
    candidates = np.arange(0.30, 0.81, 0.02)
    scored = [classification_metrics(y_true, probabilities, float(t)) for t in candidates]
    scored.sort(key=lambda row: (-row["f1"], -row["balanced_accuracy"], abs(row["threshold"] - default)))
    return float(scored[0]["threshold"]), scored[0]


def ee_predictions_to_lists(collection: Any) -> tuple[list[int], list[float]]:
    payload = collection.getInfo()
    truth: list[int] = []
    probabilities: list[float] = []
    for feature in payload.get("features", []):
        props = feature.get("properties", {})
        truth.append(int(props["label"]))
        probabilities.append(float(props.get("cane_probability", 0.0)))
    return truth, probabilities


def choose_projected_crs(gdf: gpd.GeoDataFrame, configured_epsg: int) -> Any:
    try:
        configured = gdf.to_crs(epsg=configured_epsg)
        if configured.geometry.is_valid.all():
            return configured.crs
    except Exception:
        pass
    estimated = gdf.estimate_utm_crs()
    if estimated is None:
        raise ValueError("Cannot determine a projected CRS")
    return estimated


def tile_boxes(bounds: list[float], tile_km: float) -> list[Any]:
    minx, miny, maxx, maxy = bounds
    mid_lat = (miny + maxy) / 2
    dy = tile_km / 110.574
    dx = tile_km / max(1e-6, 111.320 * math.cos(math.radians(mid_lat)))
    tiles = []
    y = miny
    while y < maxy:
        x = minx
        next_y = min(y + dy, maxy)
        while x < maxx:
            next_x = min(x + dx, maxx)
            tiles.append(box(x, y, next_x, next_y))
            x = next_x
        y = next_y
    return tiles


def download_gee_tiled(image: Any, roi_gdf: gpd.GeoDataFrame, path: Path, scale: int, tile_km: float) -> None:
    import ee
    import rasterio
    import requests
    from rasterio.merge import merge

    roi_wgs = roi_gdf.to_crs(4326)
    roi_union = unary_union(roi_wgs.geometry)
    tiles = [tile for tile in tile_boxes(list(roi_wgs.total_bounds), tile_km) if tile.intersects(roi_union)]
    if not tiles:
        raise ValueError("ROI search does not intersect any export tile")
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_paths: list[Path] = []
    with tempfile.TemporaryDirectory(prefix="sugarcane_gee_") as temp_dir_raw:
        temp_dir = Path(temp_dir_raw)
        for index, tile in enumerate(tiles):
            geom = ee.Geometry(mapping(tile.intersection(roi_union)))
            url = image.clip(geom).getDownloadURL(
                {"scale": scale, "region": geom, "format": "GEO_TIFF", "crs": "EPSG:4326"}
            )
            response = None
            for attempt in range(4):
                response = requests.get(url, timeout=300)
                if response.status_code == 200:
                    break
                if response.status_code not in {429, 500, 502, 503, 504}:
                    break
                time.sleep(2 ** attempt)
            if response is None or response.status_code != 200:
                code = "no-response" if response is None else response.status_code
                raise RuntimeError(f"Earth Engine tile download failed ({index + 1}/{len(tiles)}): HTTP {code}")
            raw = response.content
            tile_path = temp_dir / f"tile_{index:05d}.tif"
            if raw[:2] == b"PK":
                with zipfile.ZipFile(io.BytesIO(raw)) as archive:
                    tif_names = [name for name in archive.namelist() if name.lower().endswith((".tif", ".tiff"))]
                    if not tif_names:
                        raise RuntimeError("Earth Engine ZIP did not contain a GeoTIFF")
                    with archive.open(tif_names[0]) as source, tile_path.open("wb") as target:
                        shutil.copyfileobj(source, target)
            else:
                tile_path.write_bytes(raw)
            temp_paths.append(tile_path)

        sources = [rasterio.open(item) for item in temp_paths]
        try:
            mosaic, transform = merge(sources)
            metadata = sources[0].meta.copy()
            metadata.update(
                driver="GTiff",
                height=mosaic.shape[1],
                width=mosaic.shape[2],
                transform=transform,
                compress="DEFLATE",
                tiled=True,
            )
            with rasterio.open(path, "w", **metadata) as destination:
                destination.write(mosaic)
        finally:
            for source in sources:
                source.close()


def polygonize_candidate(mask_path: Path, output: Path, min_area_ha: float, crs_epsg: int) -> dict[str, Any]:
    import rasterio
    from rasterio.features import shapes

    with rasterio.open(mask_path) as src:
        values = src.read(1)
        valid = values == 1
        geometries = [shape(geom) for geom, value in shapes(values, mask=valid, transform=src.transform) if int(value) == 1]
        crs = src.crs
    if not geometries:
        empty = gpd.GeoDataFrame({"class": []}, geometry=[], crs=crs)
        empty.to_file(output, driver="GeoJSON")
        return {"feature_count": 0, "area_ha": 0.0}
    candidate = gpd.GeoDataFrame({"class": [1] * len(geometries)}, geometry=geometries, crs=crs)
    projected_crs = choose_projected_crs(candidate, crs_epsg)
    projected = candidate.to_crs(projected_crs)
    projected = projected[projected.geometry.area >= min_area_ha * 10000].copy()
    projected["area_ha"] = projected.geometry.area / 10000.0
    projected = projected.dissolve().explode(index_parts=False).reset_index(drop=True)
    projected["candidate_id"] = [f"CANE_{i + 1:06d}" for i in range(len(projected))]
    projected["area_ha"] = projected.geometry.area / 10000.0
    projected.to_crs(4326).to_file(output, driver="GeoJSON")
    return {"feature_count": int(len(projected)), "area_ha": float(projected.geometry.area.sum() / 10000.0)}


def run_supervised(
    paths: ProjectPaths,
    roi_path: Path,
    label_path: Path,
    config: dict[str, Any],
    config_path: Path,
    preflight_only: bool,
) -> dict[str, Any]:
    roi = read_vector(roi_path)
    labels = read_labels(
        label_path,
        int(config["crs_epsg"]),
        float(config["spatial_block_m"]),
        int(config["spatial_folds"]),
        int(config["random_seed"]),
    )
    within = gpd.sjoin(labels, roi.to_crs(4326)[[roi.geometry.name]], predicate="within", how="inner")
    labels = labels.loc[within.index.unique()].copy()
    summary = label_summary(labels)
    preflight: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "created_utc": utc_now(),
        "mode": "supervised_classification",
        "roi_search": {"path": str(roi_path.resolve()), "sha256": sha256_file(roi_path)},
        "labels": {"path": str(label_path.resolve()), "sha256": sha256_file(label_path), **summary},
        "scientific_guards": {
            "random_points_used_as_verified_absence": False,
            "missing_predictors_unmasked_to_zero": False,
            "worldcover_hard_mask": False,
            "sentinel1_additional_log_transform": False,
            "threshold_and_outer_test_are_separate_spatial_folds": True,
            "candidate_requires_manual_review": True,
            "candidate_missing_predictors_preserved_as_nodata": True,
        },
    }
    if summary["n_negative"] == 0 or summary["n_positive"] == 0:
        preflight.update(
            status="BLOCKED_POSITIVE_AND_NEGATIVE_LABELS_REQUIRED",
            reason=(
                "A binary sugarcane map requires verified labels for both sugarcane (1) and non-sugarcane (0). "
                "Random background points are not treated as confirmed negatives."
            ),
        )
        write_json(paths.result / "field_area_QA.json", preflight)
        return preflight
    min_groups = int(config["min_groups_per_class"])
    if summary["negative_spatial_groups"] < min_groups or summary["positive_spatial_groups"] < min_groups:
        preflight.update(
            status="BLOCKED_INSUFFICIENT_SPATIAL_GROUPS",
            reason=f"Each class needs at least {min_groups} spatial groups to assess transfer beyond labelled fields.",
        )
        write_json(paths.result / "field_area_QA.json", preflight)
        return preflight
    try:
        calibration_fold, test_fold = select_calibration_and_test_folds(
            labels, int(config["min_outer_test_per_class"])
        )
    except ValueError as exc:
        preflight.update(status="BLOCKED_SPATIAL_HOLDOUT_NOT_POSSIBLE", reason=str(exc))
        write_json(paths.result / "field_area_QA.json", preflight)
        return preflight
    preflight["fold_roles"] = {
        "calibration_fold": calibration_fold,
        "outer_test_fold": test_fold,
        "training_folds": sorted(
            int(x) for x in labels["spatial_fold"].unique() if int(x) not in {calibration_fold, test_fold}
        ),
    }
    preflight["status"] = "PREFLIGHT_READY" if preflight_only else "RUNNING"
    write_json(paths.result / "field_area_QA.json", preflight)
    if preflight_only:
        return preflight

    import ee

    ee.Initialize(project=str(config["gee_project_id"]) or None)
    roi_fc = gdf_to_ee(roi)
    roi_geom = roi_fc.geometry()
    stack, bands, scene_counts = gee_feature_stack(config, roi_geom)
    labels_fc = gdf_to_ee(labels)
    samples = stack.sampleRegions(
        collection=labels_fc,
        properties=["label", "spatial_group", "spatial_fold", "evaluation_eligible"],
        scale=int(config["resolution_m"]),
        geometries=True,
        tileScale=8,
    ).filter(ee.Filter.notNull(bands))

    external_train_only_fc = None
    reference_reuse_qa: dict[str, Any] = {
        "enabled": False,
        "direct_inference_allowed": False,
        "calibration_or_test_use_allowed": False,
    }
    if bool(config.get("reuse_reference_positive", False)):
        reference_reuse = load_reference_reuse_module()
        package = str(config.get("reference_package", "")).strip()
        transfer = reference_reuse.reference_reuse_preflight(
            package,
            feature_schema_for(config),
            target_has_local_positive=summary["n_positive"] > 0,
            target_has_local_negative=summary["n_negative"] > 0,
            target_phenology_confirmed=bool(config.get("phenology_alignment_confirmed", False)),
        )
        if not transfer.get("training_augmentation_allowed", False):
            preflight.update(
                status=transfer.get("status", "BLOCKED_REFERENCE_REUSE_GATE"),
                reference_reuse=transfer,
            )
            write_json(paths.result / "field_area_QA.json", preflight)
            return preflight
        domain_limit = int(config.get("reference_domain_sample_limit", 2000))
        positive_payload = samples.filter(ee.Filter.eq("label", 1)).limit(domain_limit).getInfo()
        positive_rows = [feature.get("properties", {}) for feature in positive_payload.get("features", [])]
        domain = reference_reuse.target_domain_gate(
            pd.DataFrame(positive_rows),
            package,
            minimum_row_fraction=float(config.get("reference_minimum_row_fraction", 0.80)),
            minimum_predictor_fraction=float(
                config.get("reference_minimum_predictor_fraction", 0.90)
            ),
        )
        if not domain.get("pass", False):
            preflight.update(
                status=domain.get("status", "BLOCKED_ENVIRONMENTAL_DOMAIN_MISMATCH"),
                reference_reuse={**transfer, "domain_gate": domain},
            )
            write_json(paths.result / "field_area_QA.json", preflight)
            return preflight
        external_rows = reference_reuse.sanitized_train_only_rows(package, bands)
        local_training_n = int(
            samples.filter(ee.Filter.neq("spatial_fold", calibration_fold))
            .filter(ee.Filter.neq("spatial_fold", test_fold))
            .size()
            .getInfo()
        )
        max_external = max(
            1,
            int(
                math.floor(
                    local_training_n
                    * float(config.get("reference_max_fraction_of_local_training", 0.25))
                )
            ),
        )
        external_rows = external_rows.sort_values("reference_id").head(max_external)
        external_train_only_fc = reference_reuse.dataframe_to_ee_train_only(external_rows, bands)
        reference_reuse_qa = {
            **transfer,
            "enabled": True,
            "domain_gate": domain,
            "n_train_only_rows": int(len(external_rows)),
            "direct_inference_allowed": False,
            "calibration_or_test_use_allowed": False,
            "merge_role": "TRAIN_ONLY_EXTERNAL_REFERENCE",
        }

    def balanced_subset(collection: Any) -> Any:
        limit = int(config["max_samples_per_class"])
        negative = collection.filter(ee.Filter.eq("label", 0)).randomColumn("balance", int(config["random_seed"])).sort("balance").limit(limit)
        positive = collection.filter(ee.Filter.eq("label", 1)).randomColumn("balance", int(config["random_seed"]) + 1).sort("balance").limit(limit)
        return negative.merge(positive)

    train_samples = balanced_subset(
        samples.filter(ee.Filter.neq("spatial_fold", calibration_fold)).filter(ee.Filter.neq("spatial_fold", test_fold))
    )
    if external_train_only_fc is not None:
        train_samples = train_samples.merge(external_train_only_fc)
    calibration_samples = balanced_subset(samples.filter(ee.Filter.eq("spatial_fold", calibration_fold)))
    test_samples = balanced_subset(samples.filter(ee.Filter.eq("spatial_fold", test_fold)))
    variables_per_split = max(2, round(math.sqrt(len(bands))))

    def fit(training: Any) -> Any:
        return ee.Classifier.smileRandomForest(
            numberOfTrees=int(config["rf_trees"]),
            variablesPerSplit=variables_per_split,
            minLeafPopulation=int(config["rf_min_leaf"]),
            bagFraction=float(config["rf_bag_fraction"]),
            seed=int(config["random_seed"]),
        ).train(training, "label", bands)

    preliminary = fit(train_samples)
    calibration_predictions = calibration_samples.classify(
        preliminary.setOutputMode("PROBABILITY"), "cane_probability"
    )
    calibration_y, calibration_p = ee_predictions_to_lists(calibration_predictions)
    threshold, calibration_metrics = best_threshold(
        calibration_y, calibration_p, float(config["probability_threshold_default"])
    )
    test_predictions = test_samples.classify(preliminary.setOutputMode("PROBABILITY"), "cane_probability")
    test_y, test_p = ee_predictions_to_lists(test_predictions)
    outer_metrics = classification_metrics(test_y, test_p, threshold)
    gates = {
        "minimum_outer_f1": outer_metrics["f1"] >= float(config["minimum_outer_f1"]),
        "minimum_outer_precision": outer_metrics["precision_user_accuracy_sugarcane"]
        >= float(config["minimum_outer_precision"]),
        "minimum_outer_recall": outer_metrics["recall_producer_accuracy_sugarcane"]
        >= float(config["minimum_outer_recall"]),
    }
    metric_gate = all(gates.values())

    final_training = balanced_subset(samples)
    if external_train_only_fc is not None:
        final_training = final_training.merge(external_train_only_fc)
    final_classifier = fit(final_training)
    probability = stack.classify(final_classifier.setOutputMode("PROBABILITY")).rename("cane_probability")
    raw_candidate = probability.gte(threshold)
    smoothed = raw_candidate.focalMode(radius=1, units="pixels")
    min_pixels = max(1, math.ceil(float(config["minimum_field_area_ha"]) * 10000 / int(config["resolution_m"]) ** 2))
    candidate = (
        smoothed.updateMask(smoothed)
        .connectedPixelCount(maxSize=max(128, min_pixels + 1), eightConnected=True)
        .gte(min_pixels)
        .rename("cane_candidate")
        .toByte()
    )

    probability_path = paths.result / "sugarcane_probability.tif"
    mask_path = paths.result / "roi_field_area_candidate.tif"
    vector_path = paths.result / "roi_field_area_candidate.geojson"
    download_gee_tiled(
        probability,
        roi,
        probability_path,
        int(config["resolution_m"]),
        float(config["tile_km"]),
    )
    download_gee_tiled(
        candidate,
        roi,
        mask_path,
        int(config["resolution_m"]),
        float(config["tile_km"]),
    )
    candidate_summary = polygonize_candidate(
        mask_path, vector_path, float(config["minimum_field_area_ha"]), int(config["crs_epsg"])
    )
    model_status = "LOCALLY_SPATIAL_HOLDOUT_PASSED" if metric_gate else "OUTER_METRIC_GATE_FAILED"
    product_status = "CANDIDATE_REQUIRES_MANUAL_REVIEW" if metric_gate else "BLOCKED_MODEL_QA_FAILED"
    feature_schema = feature_schema_for(config)
    write_json(paths.work / "model_package" / "feature_schema.json", feature_schema)
    model_card = {
        "schema_version": SCHEMA_VERSION,
        "created_utc": utc_now(),
        "method_id": METHOD_ID,
        "model_status": model_status,
        "binary_classifier_trained": True,
        "validation_design": "spatial-group train / separate threshold-calibration fold / outer held-out test fold",
        "independent_field_validation": False,
        "threshold_calibration": calibration_metrics,
        "outer_test": outer_metrics,
        "metric_gates": gates,
        "transferable_validated_model": False,
        "transfer_policy": (
            "The package may augment training only after feature-schema/domain checks. A new region still needs "
            "local positive and negative labels and a local spatial outer test."
        ),
        "scene_counts": scene_counts,
        "candidate_missing_predictors_preserved_as_nodata": True,
        "final_production_refit": {
            "performed_after_outer_assessment": True,
            "uses_all_local_labels": True,
            "optional_external_rows_role": "TRAIN_ONLY_EXTERNAL_REFERENCE",
            "outer_metrics_source": "preliminary model evaluated before final refit",
            "independent_field_validation": False,
        },
        "training_label_sha256": sha256_file(label_path),
        "config_sha256": sha256_file(config_path),
        "reference_reuse": reference_reuse_qa,
    }
    write_json(paths.work / "model_package" / "model_card.json", model_card)
    qa = {
        **preflight,
        "completed_utc": utc_now(),
        "status": product_status,
        "method_id": METHOD_ID,
        "feature_schema": feature_schema,
        "scene_counts": scene_counts,
        "threshold": threshold,
        "calibration_metrics": calibration_metrics,
        "outer_test_metrics": outer_metrics,
        "metric_gates": gates,
        "reference_reuse": reference_reuse_qa,
        "candidate_missing_predictors_preserved_as_nodata": True,
        "final_production_refit": {
            "performed_after_outer_assessment": True,
            "uses_all_local_labels": True,
            "outer_metrics_are_not_computed_from_final_refit": True,
            "optional_external_rows_are_train_only": True,
        },
        "candidate": {
            **candidate_summary,
            "probability_raster": str(probability_path.resolve()),
            "binary_raster": str(mask_path.resolve()),
            "vector": str(vector_path.resolve()),
            "approved_for_sample_design": False,
        },
        "manual_review_instruction": (
            "Inspect probability and candidate boundaries against contemporaneous high-resolution imagery and field knowledge. "
            "Edit/copy only reviewed geometry to 00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson, then rerun."
        ),
        "aoa_transfer_status": "LOCAL_DOMAIN_ONLY; cross-region applicability not established",
    }
    write_json(paths.result / "field_area_QA.json", qa)
    return qa


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", required=True)
    parser.add_argument("--preflight-only", action="store_true")
    args = parser.parse_args()
    project = Path(args.project_dir).resolve()
    paths = ProjectPaths.from_project(project)
    paths.ensure()
    config, config_path = config_for(paths)
    inputs = locate_inputs(paths)
    requested_mode = str(config["mode"]).strip().lower()
    direct = inputs["roi_field_area"] is not None and requested_mode in {"auto", "provided", "direct"}
    if direct:
        qa = approve_direct_field_area(
            paths,
            Path(inputs["roi_field_area"]),
            config,
            config_path,
        )
        print(f"[OK] Field-area ROI approved: {qa['field_area_source']['area_ha']:.2f} ha")
        print("[INFO] AKS reference package status: positive_reference_only (not a transferable binary model)")
        return 0
    if inputs["roi_search"] is None:
        raise FileNotFoundError(
            "Provide roi_field_area.geojson when the field area is known, or roi_search.geojson when classification is needed."
        )
    if inputs["labels"] is None:
        qa = {
            "schema_version": SCHEMA_VERSION,
            "created_utc": utc_now(),
            "status": "BLOCKED_LABELS_REQUIRED",
            "reason": "Classification requires sugarcane_labels with verified label 1 and label 0 examples.",
            "random_background_is_not_absence": True,
        }
        write_json(paths.result / "field_area_QA.json", qa)
        print("[BLOCKED] Missing sugarcane_labels.csv (both verified classes are required).")
        return 2
    qa = run_supervised(
        paths,
        Path(inputs["roi_search"]),
        Path(inputs["labels"]),
        config,
        config_path,
        args.preflight_only,
    )
    print(f"[{qa['status']}] See: {paths.result / 'field_area_QA.json'}")
    return 0 if qa["status"] in {"PREFLIGHT_READY", "CANDIDATE_REQUIRES_MANUAL_REVIEW"} else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        raise
