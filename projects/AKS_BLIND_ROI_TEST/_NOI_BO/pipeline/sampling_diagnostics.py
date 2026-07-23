"""Descriptive feature-space and spatial diagnostics for sampling plans."""

import numpy as np
from scipy.spatial import cKDTree
from scipy.stats import ks_2samp


def finite_float(value):
    value = float(value)
    return value if np.isfinite(value) else None


def plan_diagnostics(features, coords, soils, selected_ids, evaluation_ids, soil_labels):
    """Compare a plan with candidates; these metrics are not map validation."""
    selected_ids = np.asarray(selected_ids, dtype=int)
    selected_features = features[selected_ids]
    selected_coords = coords[selected_ids]
    candidate_eval = np.asarray(evaluation_ids, dtype=int)

    feature_metrics = {}
    for col in range(features.shape[1]):
        name = f"PC{col + 1}"
        population = np.asarray(features[:, col], dtype=float)
        sample = np.asarray(selected_features[:, col], dtype=float)
        pop_mean = float(np.mean(population))
        pop_sd = float(np.std(population, ddof=1))
        sample_sd = float(np.std(sample, ddof=1)) if len(sample) > 1 else np.nan
        pop_q = np.quantile(population, [0.05, 0.50, 0.95])
        sample_q = np.quantile(sample, [0.05, 0.50, 0.95])
        central_width = float(pop_q[2] - pop_q[0])
        overlap = max(
            0.0,
            min(float(np.max(sample)), float(pop_q[2]))
            - max(float(np.min(sample)), float(pop_q[0])),
        )
        feature_metrics[name] = {
            "candidate_mean": finite_float(pop_mean),
            "candidate_sd": finite_float(pop_sd),
            "candidate_p05": finite_float(pop_q[0]),
            "candidate_p50": finite_float(pop_q[1]),
            "candidate_p95": finite_float(pop_q[2]),
            "plan_mean": finite_float(np.mean(sample)),
            "plan_sd": finite_float(sample_sd),
            "plan_p05": finite_float(sample_q[0]),
            "plan_p50": finite_float(sample_q[1]),
            "plan_p95": finite_float(sample_q[2]),
            "standardized_mean_difference": finite_float(
                (np.mean(sample) - pop_mean) / pop_sd if pop_sd > 0 else np.nan
            ),
            "sd_ratio_plan_to_candidates": finite_float(
                sample_sd / pop_sd if pop_sd > 0 else np.nan
            ),
            "ks_statistic": finite_float(
                ks_2samp(sample, population, method="asymp").statistic
            ),
            "candidate_central_90_range_covered": finite_float(
                min(1.0, overlap / central_width) if central_width > 0 else np.nan
            ),
        }

    sample_tree = cKDTree(selected_coords)
    nearest = (
        sample_tree.query(selected_coords, k=2)[0][:, 1]
        if len(selected_coords) > 1
        else np.asarray([np.nan])
    )
    coverage = sample_tree.query(coords[candidate_eval], k=1)[0]
    spatial_metrics = {
        "crs_units": "metres",
        "nearest_neighbor_min_m": finite_float(np.nanmin(nearest)),
        "nearest_neighbor_p10_m": finite_float(np.nanquantile(nearest, 0.10)),
        "nearest_neighbor_median_m": finite_float(np.nanmedian(nearest)),
        "nearest_neighbor_p90_m": finite_float(np.nanquantile(nearest, 0.90)),
        "nearest_neighbor_max_m": finite_float(np.nanmax(nearest)),
        "candidate_coverage_p50_m": finite_float(np.quantile(coverage, 0.50)),
        "candidate_coverage_p90_m": finite_float(np.quantile(coverage, 0.90)),
        "candidate_coverage_p95_m": finite_float(np.quantile(coverage, 0.95)),
        "candidate_coverage_max_m": finite_float(np.max(coverage)),
        "coverage_evaluation_candidate_count": int(len(candidate_eval)),
    }

    soil_metrics = {}
    for group in sorted(np.unique(soils)):
        candidate_prop = float(np.mean(soils == group))
        plan_prop = float(np.mean(soils[selected_ids] == group))
        label = soil_labels.get(int(group), str(int(group)))
        soil_metrics[label] = {
            "candidate_fraction": candidate_prop,
            "plan_fraction": plan_prop,
            "fraction_difference": plan_prop - candidate_prop,
        }

    return {
        "n_points": int(len(selected_ids)),
        "feature_space": feature_metrics,
        "spatial": spatial_metrics,
        "soil_strata": soil_metrics,
        "interpretation": (
            "Descriptive diagnostics for comparing plans; they do not establish "
            "equal map accuracy or replace post-laboratory outer-held-out spatial "
            "CV or a genuinely independent field validation dataset."
        ),
    }
