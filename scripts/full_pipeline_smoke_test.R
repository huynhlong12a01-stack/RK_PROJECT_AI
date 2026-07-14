# End-to-end smoke test on a small synthetic raster stack.

if (!requireNamespace("terra", quietly = TRUE) ||
    !requireNamespace("jsonlite", quietly = TRUE)) {
  stop("terra and jsonlite are required for the full pipeline smoke test.")
}
root <- file.path(".tmp", "full_pipeline_science")
if (dir.exists(root)) unlink(root, recursive = TRUE, force = TRUE)
point_dir <- file.path(root, "input", "points")
raster_dir <- file.path(root, "input", "raster")
output_dir <- file.path(root, "output")
dir.create(point_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(raster_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

set.seed(2718)
template <- terra::rast(
  nrows = 45, ncols = 45, xmin = 105.90, xmax = 106.10,
  ymin = 10.90, ymax = 11.10, crs = "EPSG:4326"
)
xy <- terra::xyFromCell(template, seq_len(terra::ncell(template)))
pc_values <- list(
  as.numeric(scale(xy[, 1])),
  as.numeric(scale(xy[, 2])),
  sin(xy[, 1] * 40) + cos(xy[, 2] * 35),
  stats::rnorm(terra::ncell(template), 0, 0.3),
  as.numeric(scale(xy[, 1] * xy[, 2]))
)
for (i in seq_len(5)) {
  r <- template
  terra::values(r) <- pc_values[[i]]
  terra::writeRaster(
    r, file.path(raster_dir, paste0("PC", i, ".tif")), overwrite = TRUE)
}

n <- 42L
points <- data.frame(
  code = sprintf("T%03d", seq_len(n)),
  lon = stats::runif(n, 105.92, 106.08),
  lat = stats::runif(n, 10.92, 11.08)
)
covariates <- terra::extract(
  terra::rast(list.files(raster_dir, pattern = "\\.tif$",
    full.names = TRUE)), terra::vect(points, geom = c("lon", "lat"),
      crs = "EPSG:4326")
)
points$pH_H2O <- 5.6 + 0.35 * covariates[[2]] - 0.22 * covariates[[3]] +
  0.10 * covariates[[4]] + stats::rnorm(n, 0, 0.12)
point_file <- file.path(point_dir, "soil_points.csv")
utils::write.csv(points, point_file, row.names = FALSE, fileEncoding = "UTF-8")

override <- file.path(root, "smoke_override.R")
writeLines(c(
  paste0("POINT_FILE <- ", dQuote(normalizePath(point_file,
    winslash = "/", mustWork = FALSE))),
  paste0("RASTER_DIR <- ", dQuote(normalizePath(raster_dir,
    winslash = "/", mustWork = FALSE))),
  paste0("OUTPUT_ROOT <- ", dQuote(normalizePath(output_dir,
    winslash = "/", mustWork = FALSE))),
  "RUN_NAME_OVERRIDE <- \"science_full_smoke\"",
  "ASK_OUTPUT_FOLDER <- FALSE",
  "TARGET_FIELD <- \"pH_H2O\"",
  "TARGET_TRANSFORM <- \"log1p\"",
  "LOG_BACKTRANSFORM_BIAS_CORRECTION <- TRUE",
  "UTM_EPSG <- \"auto\"",
  "EXPORT_EPSG <- NA",
  "AUTO_NEIGHBORS <- FALSE",
  "NMAX_NEIGHBORS <- 10",
  "SEARCH_RADIUS <- 20000",
  "VARIOGRAM_MODE <- \"auto_select\"",
  "VARIOGRAM_CUTOFF <- 18000",
  "VARIOGRAM_WIDTH <- 2000",
  "VARIOGRAM_RANGE_MIN <- 500",
  "VARIOGRAM_RANGE_MAX <- 12000",
  "MANUAL_RANGE <- 5000",
  "CV_EVALUATION_MODE <- \"nested_spatial\"",
  "CV_OUTER_METHOD <- \"spatial_block\"",
  "CV_OUTER_FOLDS <- 3",
  "CV_OUTER_REPEATS <- 1",
  "CV_INNER_METHOD <- \"spatial_block\"",
  "CV_INNER_FOLDS <- 2",
  "CV_INNER_NEIGHBOR_MAX_CANDIDATES <- 2",
  "CV_METHODS <- character(0)",
  "VARIOGRAM_CANDIDATE_MODELS <- c(\"Exp\", \"Sph\")",
  "VARIOGRAM_INITIAL_RANGE_FACTORS <- c(0.3, 0.6)",
  "VARIOGRAM_INITIAL_NUGGET_FACTORS <- c(0.05, 0.2)",
  "VARIOGRAM_INITIAL_PSILL_FACTORS <- c(0.6, 1.0)",
  "RUN_AOA_DIAGNOSTICS <- TRUE",
  "EXPORT_RAW_CV_TABLES <- FALSE"
), override, useBytes = TRUE)

old_override <- Sys.getenv("RK_CONFIG_OVERRIDE", unset = NA_character_)
Sys.setenv(RK_CONFIG_OVERRIDE = normalizePath(
  override, winslash = "/", mustWork = TRUE))
on.exit({
  if (is.na(old_override)) Sys.unsetenv("RK_CONFIG_OVERRIDE")
  else Sys.setenv(RK_CONFIG_OVERRIDE = old_override)
}, add = TRUE)
log_file <- file.path(root, "full_pipeline.log")
status <- system2(
  Sys.which("Rscript"), "scripts/main.R", stdout = log_file, stderr = log_file)
if (!identical(status, 0L)) {
  stop("Full pipeline smoke test failed. See ", log_file)
}

run_dir <- file.path(output_dir, "science_full_smoke")
report_dir <- file.path(run_dir, "06_report")
required <- c(
  file.path(report_dir, "json", "evaluation_pH_H2O.json"),
  file.path(report_dir, "index_pH_H2O.html"),
  file.path(report_dir, "interactive", "variogram_interactive_pH_H2O.html"),
  file.path(report_dir, "tables", "nested_cv_repeat_metrics_pH_H2O.csv"),
  file.path(run_dir, "05_final_rk", "RK_final_unclamped_pH_H2O_utm.tif"),
  file.path(run_dir, "05_final_rk", "RK_clipping_mask_pH_H2O_utm.tif"),
  file.path(run_dir, "05_final_rk", "area_of_applicability_pH_H2O_utm.tif")
)
missing <- required[!file.exists(required)]
if (length(missing) > 0) {
  stop("Full pipeline missed required outputs: ",
    paste(missing, collapse = ", "))
}
evaluation <- jsonlite::read_json(required[1], simplifyVector = TRUE)
if (!isTRUE(evaluation$cross_validation$strict_outer_cv)) {
  stop("Full pipeline report did not use strict outer spatial CV.")
}
cv_metrics <- evaluation$cross_validation$metrics
if (!is.finite(cv_metrics$RMSE) ||
    !is.finite(cv_metrics$n) ||
    cv_metrics$n < 0.80 * n) {
  stop("Full pipeline outer spatial CV did not produce enough valid predictions.")
}
if (!is.finite(cv_metrics$n_interval) ||
    !is.finite(cv_metrics$interval_fraction) ||
    cv_metrics$n_interval > cv_metrics$n ||
    abs(cv_metrics$interval_fraction -
      cv_metrics$n_interval / cv_metrics$n) > 5e-4) {
  stop("Interval metric support count/fraction is missing or inconsistent.")
}
variance_support_warning <- any(
  grepl("outer predictions", evaluation$warnings, fixed = TRUE) &
    grepl("variance", evaluation$warnings, fixed = TRUE))
if (cv_metrics$interval_fraction < 0.80 && !variance_support_warning) {
  stop("Subset-based coverage did not produce the required warning.")
}
if (isTRUE(evaluation$uncertainty$used_in_grade)) {
  stop("Residual-only uncertainty was incorrectly used in grade.")
}
if (is.null(evaluation$messages) || is.null(evaluation$warnings) ||
    is.null(evaluation$hard_failures)) {
  stop("Evaluation did not separate messages, warnings and hard failures.")
}
if (!grepl("Internal QA grade", evaluation$quality$grade_label, fixed = TRUE)) {
  stop("Internal QA grade label is missing.")
}
final_unclamped <- terra::rast(required[5])
finite_final_cells <- terra::global(
  is.finite(final_unclamped), "sum", na.rm = TRUE)[1, 1]
if (!is.finite(finite_final_cells) || finite_final_cells <= 0) {
  stop("Full pipeline final raster has no finite predictions.")
}
if (identical(evaluation$variogram$model, "Nug")) {
  if (!identical(
      evaluation$prediction_method,
      "regression_only_pure_nugget_fallback")) {
    stop("Pure-nugget final variogram did not switch to regression-only.")
  }
  if (isTRUE(evaluation$uncertainty$available)) {
    stop("Pure-nugget fallback incorrectly reported an uncertainty raster.")
  }
  if (!isTRUE(
      evaluation$target_transform$log_backtransform_bias_correction_requested) ||
      isTRUE(
        evaluation$target_transform$log_backtransform_bias_correction)) {
    stop("Pure-nugget fallback did not disable partial production bias correction.")
  }
  uncertainty_file <- file.path(
    run_dir, "05_final_rk", "RK_uncertainty_STD_pH_H2O_utm.tif")
  if (file.exists(uncertainty_file)) {
    stop("Pure-nugget fallback exported a misleading all-NA uncertainty raster.")
  }
}
cat("[OK] full pipeline scientific smoke test passed\n")
cat("[INFO] Log: ", normalizePath(log_file, winslash = "/"), "\n", sep = "")
