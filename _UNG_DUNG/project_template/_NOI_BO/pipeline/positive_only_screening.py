#!/usr/bin/env python3
"""Positive-only sugarcane candidate screening.

This module is deliberately not a binary classifier.  It estimates the
multivariate support of locally observed sugarcane positives and exports a
candidate layer for expert review.  No background point is labelled as
non-sugarcane, no probability/precision/recall claim is produced, and the
candidate is never approved automatically for sampling design.
"""

from __future__ import annotations

import math
import os
import tempfile
from pathlib import Path
from typing import Any

import geopandas as gpd
import numpy as np
import pandas as pd


METHOD_ID = "sentinel1_sentinel2_positive_support_screening_v2"
PREFLIGHT_READY = "POSITIVE_ONLY_PREFLIGHT_READY"
CANDIDATE_READY = "POSITIVE_ONLY_CANDIDATE_REQUIRES_MANUAL_REVIEW"


def select_screening_bands(bands: list[str]) -> tuple[list[str], list[str]]:
    """Keep crop/terrain features; treat count and categorical bands as QA."""
    excluded = [
        band
        for band in bands
        if band == "worldcover_class" or band.startswith("S2_count_")
    ]
    selected = [band for band in bands if band not in excluded]
    if len(selected) < 10:
        raise ValueError("Positive-only screening requires at least 10 usable predictors")
    return selected, excluded


def robust_standardize(values: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    matrix = np.asarray(values, dtype=float)
    if matrix.ndim != 2 or matrix.shape[0] < 2:
        raise ValueError("Positive-only screening needs at least two complete feature rows")
    if not np.isfinite(matrix).all():
        raise ValueError("Positive-only feature matrix contains missing or non-finite values")
    center = np.median(matrix, axis=0)
    q25 = np.quantile(matrix, 0.25, axis=0)
    q75 = np.quantile(matrix, 0.75, axis=0)
    scale = (q75 - q25) / 1.349
    mad = np.median(np.abs(matrix - center), axis=0) * 1.4826
    std = np.std(matrix, axis=0, ddof=1)
    scale = np.where(np.isfinite(scale) & (scale > 1e-9), scale, mad)
    scale = np.where(np.isfinite(scale) & (scale > 1e-9), scale, std)
    scale = np.where(np.isfinite(scale) & (scale > 1e-9), scale, 1.0)
    standardized = (matrix - center) / scale
    return center, scale, standardized


def farthest_point_prototypes(standardized: np.ndarray, count: int) -> np.ndarray:
    values = np.asarray(standardized, dtype=float)
    if values.ndim != 2 or len(values) == 0:
        raise ValueError("Cannot choose prototypes from an empty matrix")
    target = max(1, min(int(count), len(values)))
    norms = np.mean(values**2, axis=1)
    chosen = [int(np.argmin(norms))]
    while len(chosen) < target:
        current = values[chosen]
        distances = ((values[:, None, :] - current[None, :, :]) ** 2).mean(axis=2)
        nearest = distances.min(axis=1)
        nearest[chosen] = -np.inf
        next_index = int(np.argmax(nearest))
        if next_index in chosen:
            break
        chosen.append(next_index)
    return values[chosen].copy()


def squared_distance_to_prototypes(
    standardized: np.ndarray, prototypes: np.ndarray
) -> np.ndarray:
    values = np.asarray(standardized, dtype=float)
    reference = np.asarray(prototypes, dtype=float)
    if values.ndim != 2 or reference.ndim != 2 or values.shape[1] != reference.shape[1]:
        raise ValueError("Feature and prototype matrices are incompatible")
    distances = ((values[:, None, :] - reference[None, :, :]) ** 2).mean(axis=2)
    return distances.min(axis=1)


def spatial_holdout_distances(
    standardized: np.ndarray, folds: np.ndarray, prototype_count: int
) -> np.ndarray:
    values = np.asarray(standardized, dtype=float)
    fold_values = np.asarray(folds)
    if len(values) != len(fold_values):
        raise ValueError("Fold vector does not match feature rows")
    held_out: list[np.ndarray] = []
    unique_folds = sorted(set(fold_values.tolist()), key=str)
    if len(unique_folds) >= 2:
        for fold in unique_folds:
            test = fold_values == fold
            train = ~test
            if int(train.sum()) < 2 or int(test.sum()) == 0:
                continue
            prototypes = farthest_point_prototypes(values[train], prototype_count)
            held_out.append(squared_distance_to_prototypes(values[test], prototypes))
    if held_out:
        return np.concatenate(held_out)
    if len(values) < 3:
        raise ValueError("At least three complete positives are needed for support calibration")
    pairwise = ((values[:, None, :] - values[None, :, :]) ** 2).mean(axis=2)
    np.fill_diagonal(pairwise, np.inf)
    return pairwise.min(axis=1)


def candidate_array_from_support_score(
    score_values: np.ndarray, minimum_connected_pixels: int
) -> np.ndarray:
    """Reproduce the radius-1 circular mode and 8-neighbour area gate locally."""
    from scipy import ndimage as ndi

    values = np.asarray(score_values, dtype=float)
    if values.ndim != 2:
        raise ValueError("Support-score raster must be a two-dimensional array")
    minimum = max(1, int(minimum_connected_pixels))
    raw = np.isfinite(values) & (values >= 0.5)
    cross = np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]], dtype=np.uint8)
    smoothed = ndi.convolve(raw.astype(np.uint8), cross, mode="constant", cval=0) >= 3
    labels, _ = ndi.label(smoothed, structure=np.ones((3, 3), dtype=np.uint8))
    sizes = np.bincount(labels.ravel())
    keep = sizes >= minimum
    keep[0] = False
    return keep[labels].astype(np.uint8)


def write_candidate_mask_from_score(
    score_path: Path,
    mask_path: Path,
    minimum_field_area_ha: float,
    resolution_m: int,
) -> dict[str, Any]:
    """Create the candidate mask from the downloaded score without a second GEE export."""
    import rasterio

    minimum_pixels = max(
        1,
        math.ceil(float(minimum_field_area_ha) * 10000 / int(resolution_m) ** 2),
    )
    with rasterio.open(score_path) as source:
        score = source.read(1, masked=True).filled(np.nan)
        profile = source.profile.copy()
    candidate = candidate_array_from_support_score(score, minimum_pixels)
    profile.update(count=1, dtype="uint8", nodata=0, compress="DEFLATE", tiled=True)
    mask_path.parent.mkdir(parents=True, exist_ok=True)
    handle, raw_temporary = tempfile.mkstemp(
        prefix=mask_path.name + ".", suffix=".tmp.tif", dir=mask_path.parent
    )
    os.close(handle)
    temporary = Path(raw_temporary)
    try:
        with rasterio.open(temporary, "w", **profile) as destination:
            destination.write(candidate, 1)
        os.replace(temporary, mask_path)
    finally:
        temporary.unlink(missing_ok=True)
    return {
        "engine": "local_scipy_ndimage",
        "source": "downloaded_positive_support_score",
        "support_score_cutoff": 0.5,
        "focal_mode_kernel": "radius_1_circle_5_cell_cross",
        "focal_mode_binary_majority": 3,
        "connected_neighbourhood": 8,
        "minimum_connected_pixels": minimum_pixels,
        "positive_pixels": int(candidate.sum()),
        "second_gee_mask_download_required": False,
    }


def _blocked(core: Any, paths: Any, status: str, preflight: dict[str, Any], reason: str) -> dict[str, Any]:
    qa = {**preflight, "status": status, "reason": reason}
    core.write_json(paths.result / "field_area_QA.json", qa)
    return qa


def run(
    core: Any,
    paths: Any,
    roi_path: Path,
    label_path: Path,
    labels: gpd.GeoDataFrame,
    config: dict[str, Any],
    config_path: Path,
    preflight_only: bool,
) -> dict[str, Any]:
    roi = core.read_vector(roi_path)
    labels_wgs = labels.to_crs(4326)
    within = gpd.sjoin(
        labels_wgs,
        roi.to_crs(4326)[[roi.geometry.name]],
        predicate="within",
        how="inner",
    )
    labels_wgs = labels_wgs.loc[within.index.unique()].copy()
    summary = core.label_summary(labels_wgs)
    labels_wgs["evaluation_eligible"] = False
    preflight: dict[str, Any] = {
        "schema_version": core.SCHEMA_VERSION,
        "created_utc": core.utc_now(),
        "mode": "positive_only_candidate_screening",
        "method_id": METHOD_ID,
        "roi_search": {
            "path": str(roi_path.resolve()),
            "sha256": core.sha256_file(roi_path),
        },
        "labels": {
            "path": str(label_path.resolve()),
            "sha256": core.sha256_file(label_path),
            **summary,
        },
        "product_semantics": {
            "binary_classifier_trained": False,
            "probability_output": False,
            "verified_negative_labels_used": False,
            "random_background_used_as_negative": False,
            "precision_recall_estimable": False,
            "independent_validation": False,
            "approved_for_sample_design": False,
        },
        "scientific_guards": {
            "candidate_requires_manual_review": True,
            "positive_support_is_not_crop_probability": True,
            "known_roi_field_area_used_for_inference": False,
            "missing_predictors_unmasked_to_zero": False,
            "worldcover_hard_mask": False,
            "sentinel1_additional_log_transform": False,
        },
    }
    if summary["n_negative"] != 0 or summary["n_positive"] == 0:
        return _blocked(
            core,
            paths,
            "BLOCKED_POSITIVE_ONLY_LABEL_CONTRACT",
            preflight,
            "This mode accepts local sugarcane positives only and never manufactures negatives.",
        )
    minimum_points = int(config.get("positive_screening_min_points", 30))
    if summary["n_positive"] < minimum_points:
        return _blocked(
            core,
            paths,
            "BLOCKED_INSUFFICIENT_POSITIVE_SCREENING_POINTS",
            preflight,
            f"Need at least {minimum_points} local positive observations.",
        )
    minimum_groups = int(config.get("min_groups_per_class", 3))
    if summary["positive_spatial_groups"] < minimum_groups:
        return _blocked(
            core,
            paths,
            "BLOCKED_INSUFFICIENT_POSITIVE_SPATIAL_GROUPS",
            preflight,
            f"Need at least {minimum_groups} positive spatial groups.",
        )
    preflight["status"] = PREFLIGHT_READY
    core.write_json(paths.result / "field_area_QA.json", preflight)
    if preflight_only:
        return preflight

    import ee

    print("[POSITIVE_SCREEN] Initializing Earth Engine and the 8-quarter feature stack...", flush=True)
    ee.Initialize(project=str(config.get("gee_project_id", "")).strip() or None)
    roi_fc = core.gdf_to_ee(roi)
    roi_geometry = roi_fc.geometry()
    stack, bands, scene_counts = core.gee_feature_stack(config, roi_geometry)
    print(f"[POSITIVE_SCREEN] Feature stack ready ({len(bands)} bands); sampling reference points...", flush=True)
    label_fc = core.gdf_to_ee(labels_wgs)
    sampled = (
        stack.sampleRegions(
            collection=label_fc,
            properties=["spatial_group", "spatial_fold", "evaluation_eligible"],
            scale=int(config["resolution_m"]),
            geometries=False,
            tileScale=8,
        )
        .filter(ee.Filter.notNull(bands))
    )
    payload = sampled.getInfo()
    rows = [feature.get("properties", {}) for feature in payload.get("features", [])]
    complete = pd.DataFrame(rows)
    print(f"[POSITIVE_SCREEN] Complete feature rows: {len(complete)}/{summary['n_positive']}", flush=True)
    complete_fraction = float(len(complete) / summary["n_positive"]) if summary["n_positive"] else 0.0
    minimum_complete = float(config.get("positive_screening_min_complete_fraction", 0.80))
    if complete_fraction < minimum_complete:
        return _blocked(
            core,
            paths,
            "BLOCKED_POSITIVE_FEATURE_COMPLETENESS",
            {
                **preflight,
                "scene_counts": scene_counts,
                "feature_completeness": {
                    "n_positive": summary["n_positive"],
                    "n_complete": int(len(complete)),
                    "fraction": complete_fraction,
                    "minimum": minimum_complete,
                },
            },
            "Too few local positive points have every required temporal predictor.",
        )

    screening_bands, excluded_bands = select_screening_bands(list(bands))
    matrix = complete[screening_bands].apply(pd.to_numeric, errors="coerce").to_numpy(dtype=float)
    if not np.isfinite(matrix).all():
        return _blocked(
            core,
            paths,
            "BLOCKED_NONFINITE_POSITIVE_FEATURES",
            preflight,
            "GEE returned non-finite values after the completeness filter.",
        )
    center, scale, standardized = robust_standardize(matrix)
    prototype_count = int(config.get("positive_screening_prototypes", 12))
    folds = complete["spatial_fold"].astype(str).to_numpy()
    holdout_distances = spatial_holdout_distances(standardized, folds, prototype_count)
    quantile = float(config.get("positive_screening_distance_quantile", 0.95))
    if not 0.50 <= quantile < 1.0:
        raise ValueError("positive_screening_distance_quantile must be in [0.50, 1.0)")
    threshold = float(np.quantile(holdout_distances, quantile))
    if not math.isfinite(threshold) or threshold <= 0:
        threshold = max(float(np.max(holdout_distances)), 1e-6)
    prototypes = farthest_point_prototypes(standardized, prototype_count)

    center_image = ee.Image.constant(center.tolist()).rename(screening_bands)
    scale_image = ee.Image.constant(scale.tolist()).rename(screening_bands)
    standardized_image = stack.select(screening_bands).subtract(center_image).divide(scale_image)
    distance_images = []
    for prototype in prototypes:
        prototype_image = ee.Image.constant(prototype.tolist()).rename(screening_bands)
        distance_images.append(
            standardized_image.subtract(prototype_image)
            .pow(2)
            .reduce(ee.Reducer.mean())
        )
    distance = (
        ee.ImageCollection.fromImages(distance_images)
        .min()
        .rename("positive_support_distance")
    )
    score = (
        ee.Image.constant(1)
        .divide(ee.Image.constant(1).add(distance.divide(threshold)))
        .rename("positive_support_score")
        .updateMask(distance.mask())
    )

    score_path = paths.result / "sugarcane_positive_support_score.tif"
    mask_path = paths.result / "roi_field_area_candidate.tif"
    vector_path = paths.result / "roi_field_area_candidate.geojson"
    print("[POSITIVE_SCREEN] Downloading positive-support score...", flush=True)
    core.download_gee_tiled(
        score,
        roi,
        score_path,
        int(config["resolution_m"]),
        float(config["tile_km"]),
    )
    print("[POSITIVE_SCREEN] Building candidate mask locally from the support score...", flush=True)
    candidate_postprocessing = write_candidate_mask_from_score(
        score_path,
        mask_path,
        float(config["minimum_field_area_ha"]),
        int(config["resolution_m"]),
    )
    candidate_summary = core.polygonize_candidate(
        mask_path,
        vector_path,
        float(config["minimum_field_area_ha"]),
        int(config["crs_epsg"]),
    )

    support_coverage = float(np.mean(holdout_distances <= threshold))
    feature_schema = core.feature_schema_for(config)
    screening_card = {
        "schema_version": core.SCHEMA_VERSION,
        "created_utc": core.utc_now(),
        "method_id": METHOD_ID,
        "artifact_type": "positive_class_support_screening",
        "binary_classifier_trained": False,
        "has_verified_negative_labels": False,
        "probability_output": False,
        "precision_recall_estimable": False,
        "independent_validation": False,
        "transferable_validated_model": False,
        "feature_schema": feature_schema,
        "scene_counts": scene_counts,
        "screening_features": {
            "used": screening_bands,
            "excluded_from_distance": excluded_bands,
            "exclusion_reason": (
                "S2 observation counts are quality diagnostics and WorldCover is categorical; "
                "neither is used as a hard crop decision."
            ),
        },
        "positive_support_calibration": {
            "design": "spatial-fold held-out positive support distances",
            "n_complete_positive": int(len(complete)),
            "complete_fraction": complete_fraction,
            "prototype_count": int(len(prototypes)),
            "distance_quantile": quantile,
            "distance_threshold": threshold,
            "positive_support_coverage_at_selected_quantile": support_coverage,
            "not_a_classification_accuracy_metric": True,
        },
        "training_label_sha256": core.sha256_file(label_path),
        "config_sha256": core.sha256_file(config_path),
        "known_roi_field_area_used_for_inference": False,
    }
    model_dir = paths.work / "model_package"
    model_dir.mkdir(parents=True, exist_ok=True)
    core.write_json(model_dir / "feature_schema.json", feature_schema)
    core.write_json(model_dir / "positive_support_screening_card.json", screening_card)

    qa = {
        **preflight,
        "completed_utc": core.utc_now(),
        "status": CANDIDATE_READY,
        "scene_counts": scene_counts,
        "feature_completeness": {
            "n_positive": summary["n_positive"],
            "n_complete": int(len(complete)),
            "fraction": complete_fraction,
            "minimum": minimum_complete,
        },
        "positive_support_calibration": screening_card["positive_support_calibration"],
        "candidate": {
            **candidate_summary,
            "support_score_raster": str(score_path.resolve()),
            "binary_support_raster": str(mask_path.resolve()),
            "vector": str(vector_path.resolve()),
            "approved_for_sample_design": False,
            "postprocessing": candidate_postprocessing,
        },
        "manual_review_instruction": (
            "This is a positive-class similarity screen, not a crop probability map. "
            "Review against contemporaneous imagery and collect verified non-sugarcane labels "
            "before binary classification or approval as roi_field_area."
        ),
        "aoa_transfer_status": "POSITIVE_CLASS_SUPPORT_ONLY_NOT_BINARY_AOA",
    }
    core.write_json(paths.result / "field_area_QA.json", qa)
    return qa
