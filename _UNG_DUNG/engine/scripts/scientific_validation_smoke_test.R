# Smoke tests for leakage-resistant validation and scientific guards.

source("_UNG_DUNG/engine/scripts/00_config.R")
source("_UNG_DUNG/engine/rk_evaluation/evaluation.R")
source("_UNG_DUNG/engine/scripts/transform_utils.R")
suppressPackageStartupMessages({
  library(sf)
  library(sp)
  library(gstat)
  library(terra)
})
source("_UNG_DUNG/engine/scripts/spatial_validation.R")

extract_functions <- c(
  "bt", "get_vgm_params", "variogram_practical_range",
  "variogram_candidate_score", "make_pure_nugget_variogram",
  "is_pure_nugget_variogram", "fit_variogram_auto_select",
  "metric_table", "fit_variogram_for_cv"
)
main_expr <- parse("_UNG_DUNG/engine/scripts/main.R")
for (expr in main_expr) {
  if (is.call(expr) && identical(as.character(expr[[1]]), "<-") &&
      is.symbol(expr[[2]]) && as.character(expr[[2]]) %in% extract_functions) {
    eval(expr, envir = .GlobalEnv)
  }
}
missing_functions <- extract_functions[
  !vapply(extract_functions, exists, logical(1), mode = "function")]
if (length(missing_functions) > 0) {
  stop("Could not load helper functions: ", paste(missing_functions, collapse = ", "))
}

pure_test <- make_pure_nugget_variogram(c(-1, 0, 1))
pure_params <- get_vgm_params(pure_test)
if (!is_pure_nugget_variogram(pure_test) ||
    pure_params$model != "Nug" ||
    pure_params$psill != 0 ||
    pure_params$nugget <= 0) {
  stop("Pure-nugget fallback metadata is invalid.")
}

profiles <- rk_eval_default_profiles()
ambiguous_p <- match_indicator_profile("P", profiles)
if (!isTRUE(ambiguous_p$profile_ambiguous) ||
    !isTRUE(ambiguous_p$manual_review_required)) {
  stop("Ambiguous P alias was not blocked.")
}
canonical_p <- match_indicator_profile("P_Olsen_mgkg", profiles)
if (!isTRUE(canonical_p$profile_matched) ||
    canonical_p$profile_name != "P_Olsen_mgkg") {
  stop("Canonical P_Olsen_mgkg did not match its profile.")
}
canonical_mehlich <- match_indicator_profile(
  "P_Mehlich3_mgkg", profiles)
if (!isTRUE(canonical_mehlich$profile_matched) ||
    canonical_mehlich$profile_name != "P_Mehlich3_mgkg") {
  stop("Canonical P_Mehlich3_mgkg did not match its profile.")
}
ambiguous_zn <- match_indicator_profile("Zn", profiles)
if (!isTRUE(ambiguous_zn$profile_ambiguous) ||
    !isTRUE(ambiguous_zn$manual_review_required)) {
  stop("Method-sensitive Zn alias was not blocked.")
}
unc <- rk_eval_uncertainty(summary = list(
  available = TRUE, threshold_source = "self_quantile",
  high_uncertainty_area_percent = 20,
  calibration_basis = "residual_kriging_only"
))
if (isTRUE(unc$used_in_grade) ||
    is.finite(unc$high_uncertainty_area_percent)) {
  stop("Self-quantile uncertainty was incorrectly kept as a quality score.")
}
unc_claim <- rk_eval_uncertainty(summary = list(
  available = TRUE, calibrated = TRUE,
  prediction_interval_claim_allowed = TRUE,
  total_predictive_uncertainty_available = TRUE,
  calibration_basis = "total_predictive",
  coverage_95 = 0.95, mean_standardized_error = 0,
  variance_standardized_RMSE = 1
))
if (isTRUE(unc_claim$calibrated) ||
    isTRUE(unc_claim$prediction_interval_claim_allowed) ||
    !any(grepl("chặn nhãn calibrated", unc_claim$warnings, fixed = TRUE))) {
  stop("Prediction-interval claim was not blocked without calibration evidence.")
}

class_incomplete <- profiles$P_Olsen_mgkg
class_incomplete$class_bins$approved <- TRUE
class_blocked <- rk_eval_class_prediction(
  c(5, 12, 25), c(6, 11, 24), class_incomplete)
if (isTRUE(class_blocked$enabled) ||
    !all(c("source", "unit", "laboratory_method", "crop", "region") %in%
      class_blocked$missing_required_metadata)) {
  stop("Incomplete classification metadata did not close the class gate.")
}
class_complete <- class_incomplete
class_complete$class_bins$source <- "approved local calibration"
class_complete$class_bins$unit <- "mg/kg"
class_complete$class_bins$method <- "Olsen"
class_complete$class_bins$crop <- "sugarcane"
class_complete$class_bins$region <- "study region"
class_allowed <- rk_eval_class_prediction(
  c(5, 12, 25), c(6, 11, 24), class_complete)
if (!isTRUE(class_allowed$enabled) || !isTRUE(class_allowed$gate_passed)) {
  stop("Complete approved classification metadata did not open the class gate.")
}

cv_semantics <- rk_eval_cross_validation(
  c(1, 2, 3), c(1.1, 1.9, 3.1), profiles$generic_continuous,
  method = "nested_spatial_block", cv_folds = 3,
  metadata = list(
    strict_outer_cv = TRUE, tuning_uses_outer_test = FALSE,
    outer_method = "spatial_block", outer_folds = 3,
    validation_design = "nested_spatial_cv_outer_held_out",
    validation_task = "internal_model_performance_estimation"
  )
)
if (!identical(cv_semantics$validation_design,
      "nested_spatial_cv_outer_held_out") ||
    !identical(cv_semantics$validation_task,
      "internal_model_performance_estimation") ||
    isTRUE(cv_semantics$independent_field_validation) ||
    !any(grepl("không phải independent field validation",
      cv_semantics$messages, fixed = TRUE))) {
  stop("Outer held-out CV semantics are incomplete or overclaim independence.")
}

confirmed_metadata <- list(
  confirmed = TRUE, unit = "mg/kg", laboratory_method = "Olsen",
  crop = "sugarcane", region = "study region",
  decision_use = "soil_property_mapping_and_screening",
  classification = list(approved = FALSE)
)
pending_product <- rk_eval_product_semantics(
  confirmed_metadata, profiles$P_Olsen_mgkg, list(enabled = FALSE),
  point_support = list(
    outside_review_gate_passed = FALSE,
    n_outside_pending_review = 2,
    outside_roi_points_are_validation = FALSE
  )
)
if (!identical(pending_product$product_status,
      "DRAFT_PENDING_OUTSIDE_REVIEW") ||
    isTRUE(pending_product$primary_product_eligible) ||
    isTRUE(pending_product$recommendation_language_allowed) ||
    length(pending_product$hard_failures) == 0) {
  stop("Pending outside-ROI review did not force DRAFT/hard gate.")
}
unconfirmed_product <- rk_eval_product_semantics(
  list(), profiles$generic_continuous, list(enabled = FALSE))
if (!identical(unconfirmed_product$product_status,
      "DRAFT_UNCONFIRMED_METADATA")) {
  stop("Missing confirmed metadata did not force DRAFT.")
}

incomplete_mapping_product <- rk_eval_product_semantics(
  list(confirmed = TRUE, unit = "mg/kg", laboratory_method = ""),
  profiles$generic_continuous, list(enabled = FALSE))
if (!identical(incomplete_mapping_product$product_status,
      "DRAFT_INCOMPLETE_TARGET_METADATA") ||
    isTRUE(incomplete_mapping_product$mapping_metadata_complete) ||
    isTRUE(incomplete_mapping_product$primary_product_eligible) ||
    !identical(incomplete_mapping_product$mapping_metadata_missing_fields,
      "laboratory_method") ||
    length(incomplete_mapping_product$hard_failures) == 0) {
  stop("Incomplete unit/laboratory metadata did not close the mapping gate.")
}

roles <- c(
  "model_candidate_confirmed", "model_development_confirmed",
  "model_candidate_pending_assessment", "validation", "sensitivity"
)
expected_primary <- c(TRUE, TRUE, FALSE, FALSE, FALSE)
if (!identical(rk_eval_primary_model_role(roles), expected_primary)) {
  stop("Outside-review primary-role gate is inconsistent with preflight roles.")
}
set.seed(2026)
n <- 36L
x <- runif(n, 0, 12000)
y <- runif(n, 0, 12000)
pc1 <- scale(x)[, 1] + rnorm(n, 0, 0.15)
pc2 <- scale(y)[, 1] + rnorm(n, 0, 0.15)
target <- 5.5 + 0.35 * pc1 - 0.20 * pc2 +
  0.18 * sin(x / 1800) + rnorm(n, 0, 0.12)
df <- data.frame(
  code = sprintf("S%03d", seq_len(n)),
  lon = 106 + x / 1e6, lat = 11 + y / 1e6,
  pH = as.numeric(target), PC1 = as.numeric(pc1), PC2 = as.numeric(pc2)
)
pts <- st_as_sf(
  data.frame(df, x = x + 500000, y = y + 1200000),
  coords = c("x", "y"), crs = 32649
)
MODEL_TARGET_FIELD <- ".rk_target_model"
df[[MODEL_TARGET_FIELD]] <- df$pH

CV_OUTER_METHOD <- "spatial_block"
CV_OUTER_FOLDS <- 3L
CV_OUTER_REPEATS <- 2L
CV_OUTER_BLOCK_SIZE <- "auto"
CV_INNER_METHOD <- "spatial_block"
CV_INNER_FOLDS <- 2L
CV_INNER_NEIGHBOR_MAX_CANDIDATES <- 4L
CV_TRANSFORM_CANDIDATES <- c("none", "log1p")
CV_LOG_BACKTRANSFORM_BIAS_CORRECTION <- TRUE
AUTO_NEIGHBORS <- TRUE
AUTO_NEIGHBOR_NMAX_CANDIDATES <- c(6L, 10L)
AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES <- c(5000, 10000)
VARIOGRAM_CANDIDATE_MODELS <- c("Exp", "Sph")
VARIOGRAM_CUTOFF <- 10000
VARIOGRAM_WIDTH <- 1500
VARIOGRAM_RANGE_MIN <- 500
VARIOGRAM_RANGE_MAX <- 8000
VARIOGRAM_INITIAL_RANGE_FACTORS <- c(0.3, 0.6)
VARIOGRAM_INITIAL_NUGGET_FACTORS <- c(0.05, 0.20)
VARIOGRAM_INITIAL_PSILL_FACTORS <- c(0.6, 1.0)
TARGET_TRANSFORM <- "auto"
TARGET_PROFILE_OVERRIDE <- NULL
UTM_EPSG <- 32649
CV_REQUIRE_KRIGING_NEIGHBORS <- TRUE
VARIOGRAM_ROBUST_CRESSIE <- TRUE
MIN_PAIRS_PER_VARIOGRAM_BIN <- 5
MAX_NUGGET_SILL_RATIO_WARNING <- 0.75
MAX_PRACTICAL_RANGE_FACTOR_OF_CUTOFF <- 0.80
CODE_COL <- "code"
LON_COL <- "lon"
LAT_COL <- "lat"

manual_vgm <- gstat::vgm(
  psill = 0.15, model = "Exp", range = 3000, nugget = 0.03)
formula <- stats::reformulate(
  c("PC1", "PC2"), response = MODEL_TARGET_FIELD)
plan <- rk_make_cv_plan(pts, "spatial_block", 3, 99)
if (length(plan$folds) < 2 ||
    any(vapply(plan$folds, function(z)
      length(intersect(z$train, z$test)) > 0, logical(1)))) {
  stop("Spatial block plan has invalid train/test partitions.")
}

result <- rk_nested_spatial_cv(
  model_df = df, points_sf = pts, regression_formula = formula,
  target_field = "pH", target_model_field = MODEL_TARGET_FIELD,
  manual_vgm = manual_vgm, prediction_raster = NULL
)
if (!isTRUE(result$metadata$strict_outer_cv) ||
    !identical(result$metadata$tuning_uses_outer_test, FALSE)) {
  stop("Nested CV leakage guard metadata is incorrect.")
}
if (!isTRUE(result$metadata$cv_log_bias_correction_requested) ||
    isTRUE(result$metadata$cv_log_bias_correction) ||
    result$metadata$cv_backtransform_comparison !=
      "direct_inverse_for_all_baselines") {
  stop("Nested CV did not enforce comparable baseline back-transforms.")
}
if (result$metadata$outer_repeats != 2L ||
    nrow(result$repeat_metrics) != 6L) {
  stop("Repeated outer CV metrics are incomplete.")
}
if (nrow(result$predictions) != n ||
    nrow(result$tuning) == 0 ||
    !"selection_score" %in% names(result$tuning)) {
  stop("Nested CV did not produce predictions/tuning diagnostics.")
}
if (!"inner_tuning_fallback" %in% names(result$folds)) {
  stop("Nested CV did not report inner tuning fallback status.")
}
cat("[OK] scientific validation smoke tests passed\n")
