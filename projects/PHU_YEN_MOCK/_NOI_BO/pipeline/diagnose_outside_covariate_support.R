suppressPackageStartupMessages({
  library(readr)
  library(jsonlite)
  library(terra)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

argument_value <- function(name, default = NULL) {
  args <- commandArgs(trailingOnly = TRUE)
  hit <- match(name, args)
  if (is.na(hit) || hit == length(args)) return(default)
  args[[hit + 1L]]
}

base <- argument_value("--project", "projects/PHU_YEN_MOCK")
work_dir <- file.path(base, "_NOI_BO/work/interpolation")
qa_dir <- file.path(work_dir, "qa")
sample_file <- file.path(work_dir, "sample_actual_clean.csv")
point_qa_file <- file.path(qa_dir, "sample_roi_status.csv")
provenance_file <- file.path(qa_dir, "pca_current_provenance.json")
output_csv <- file.path(qa_dir, "outside_covariate_dissimilarity.csv")
output_json <- file.path(qa_dir, "outside_covariate_dissimilarity_summary.json")
utility_file <- file.path(
  base, "_NOI_BO/pipeline/outside_covariate_dissimilarity_utils.R")

required_files <- c(sample_file, point_qa_file, provenance_file, utility_file)
missing_files <- required_files[!file.exists(required_files)]
if (length(missing_files)) {
  stop("Missing prerequisite file(s): ", paste(missing_files, collapse = ", "))
}
source(utility_file)

provenance <- jsonlite::read_json(provenance_file, simplifyVector = TRUE)
verification_status <- as.character(provenance$verification_status %||% "missing")
if (!grepl("^verified", verification_status, ignore.case = TRUE)) {
  stop(
    "Current PC rasters do not have verified frozen-reference provenance. ",
    "Refresh PCA support before interpreting covariate dissimilarity."
  )
}

samples <- as.data.frame(readr::read_csv(
  sample_file, show_col_types = FALSE, progress = FALSE))
point_qa <- as.data.frame(readr::read_csv(
  point_qa_file, show_col_types = FALSE, progress = FALSE))
required_sample <- c("code", "lat", "lon")
missing_sample <- setdiff(required_sample, names(samples))
if (length(missing_sample)) {
  stop("sample_actual_clean.csv is missing: ",
    paste(missing_sample, collapse = ", "))
}
required_qa <- c("code", "inside_roi")
missing_qa <- setdiff(required_qa, names(point_qa))
if (length(missing_qa)) {
  stop("sample_roi_status.csv is missing: ", paste(missing_qa, collapse = ", "))
}
if (anyDuplicated(samples$code) || anyDuplicated(point_qa$code)) {
  stop("Sample and point-QA codes must be unique.")
}
qa_index <- match(as.character(samples$code), as.character(point_qa$code))
if (any(is.na(qa_index))) stop("Point QA is missing one or more sample codes.")
point_qa <- point_qa[qa_index, , drop = FALSE]
inside <- as.logical(point_qa$inside_roi)
if (any(is.na(inside))) stop("inside_roi contains missing or invalid values.")

pc_names <- paste0("PC", 1:5)
pc_files <- file.path(work_dir, paste0(pc_names, ".tif"))
missing_pc <- pc_files[!file.exists(pc_files)]
if (length(missing_pc)) {
  stop("Missing current PC raster(s): ", paste(missing_pc, collapse = ", "))
}
pc_stack <- terra::rast(pc_files)
names(pc_stack) <- pc_names
sample_vector <- terra::vect(
  samples, geom = c("lon", "lat"), crs = "EPSG:4326")
sample_vector <- terra::project(sample_vector, terra::crs(pc_stack))
pc_values <- as.data.frame(terra::extract(pc_stack, sample_vector, ID = FALSE))
names(pc_values) <- pc_names
complete_pc <- stats::complete.cases(pc_values) &
  apply(pc_values, 1, function(x) all(is.finite(as.numeric(x))))
if (any(!complete_pc)) {
  stop(
    sum(!complete_pc),
    " sample(s) lack complete verified PC1-PC5 values; refresh covariate support."
  )
}

reference_index <- which(inside)
outside_index <- which(!inside)
if (length(reference_index) < 3L) {
  stop("At least three inside-ROI samples are required as the reference.")
}

dir.create(qa_dir, recursive = TRUE, showWarnings = FALSE)
if (!length(outside_index)) {
  empty <- data.frame(
    code = character(), lat = numeric(), lon = numeric(),
    nearest_inside_code = character(), standardized_nn_distance = numeric(),
    inside_loo_q95_threshold = numeric(), inside_loo_max_threshold = numeric(),
    pc_range_exceed_count = integer(), pc_range_exceed_fields = character(),
    empirical_support_status = character(), recommended_action = character(),
    diagnostic_role = character(), is_final_model_aoa = logical(),
    is_independent_validation = logical(), stringsAsFactors = FALSE
  )
  readr::write_csv(empty, output_csv, na = "")
  jsonlite::write_json(list(
    diagnostic_id = "outside_pc_support_pre_inclusion_v1",
    status = "no_outside_samples",
    n_inside_reference = length(reference_index),
    n_outside_candidates = 0L,
    pca_provenance_status = verification_status,
    pca_reference_hash = provenance$pca_reference_hash %||% NA_character_,
    is_final_model_aoa = FALSE,
    is_independent_validation = FALSE
  ), output_json, pretty = TRUE, auto_unbox = TRUE, na = "null")
  cat("No outside-ROI samples; wrote an empty support diagnostic.\n")
  quit(save = "no", status = 0L)
}

diagnostic <- outside_covariate_diagnostic(
  reference = pc_values[reference_index, pc_names, drop = FALSE],
  candidates = pc_values[outside_index, pc_names, drop = FALSE],
  reference_ids = samples$code[reference_index],
  candidate_ids = samples$code[outside_index],
  threshold_probability = 0.95
)

qa_fields <- intersect(c(
  "geographic_status", "distance_to_roi_m", "target_population_status",
  "sampling_support_status", "manual_assessment_status",
  "include_in_model_development", "analysis_role",
  "aoa_assessment_status"
), names(point_qa))
output <- cbind(
  samples[outside_index, c("code", "lat", "lon"), drop = FALSE],
  pc_values[outside_index, pc_names, drop = FALSE],
  diagnostic$table[, setdiff(names(diagnostic$table), "code"), drop = FALSE],
  point_qa[outside_index, qa_fields, drop = FALSE]
)
readr::write_csv(output, output_csv, na = "")

status_counts <- as.list(table(output$empirical_support_status))
summary <- list(
  diagnostic_id = "outside_pc_support_pre_inclusion_v1",
  status = "complete",
  diagnostic_role = "target_free_pre_inclusion_covariate_support_diagnostic",
  predictor_space = pc_names,
  n_inside_reference = length(reference_index),
  n_outside_candidates = length(outside_index),
  n_active_predictors = length(diagnostic$standardization$active_predictors),
  active_predictors = diagnostic$standardization$active_predictors,
  inactive_predictors = diagnostic$standardization$inactive_predictors,
  standardization = "inside-reference mean and sample standard deviation",
  distance = "Euclidean nearest-neighbour distance in standardized PC space",
  threshold = list(
    rule = "empirical 95th percentile of leave-one-out nearest-neighbour distances among inside-ROI reference samples",
    probability = diagnostic$threshold_probability,
    q95 = diagnostic$threshold_q,
    maximum_inside_loo = diagnostic$threshold_max
  ),
  status_counts = status_counts,
  pca_provenance_status = verification_status,
  pca_reference_hash = provenance$pca_reference_hash %||% NA_character_,
  pca_reference_frozen = provenance$reference_frozen %||% NA,
  output_csv = normalizePath(output_csv, winslash = "/", mustWork = FALSE),
  is_final_model_aoa = FALSE,
  is_independent_validation = FALSE,
  automatic_include_exclude_decision = FALSE,
  interpretation = paste0(
    "This target-free diagnostic compares outside samples with the current ",
    "inside-frame calibration sample support. It does not replace manual ",
    "target-population/sampling-support review, model-dependent CAST AOA, or ",
    "inside-only sensitivity analysis."
  ),
  limitations = c(
    "Thresholds are empirical diagnostics from the current inside sample set, not probability-sample accuracy bounds.",
    "A similar PC location does not prove the same soil population, laboratory support, or unbiased sampling.",
    "Outside samples remain model-development candidates and are not an independent validation set."
  ),
  generated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
)
jsonlite::write_json(
  summary, output_json, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(
  "Outside covariate support diagnostic: ", length(outside_index),
  " candidates; output: ", output_csv, "\n", sep = ""
)
