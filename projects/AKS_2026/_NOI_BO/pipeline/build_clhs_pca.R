suppressPackageStartupMessages({
  library(terra)
  library(jsonlite)
  library(digest)
  library(yaml)
})

base <- "projects/AKS_2026"
work_dir <- file.path(base, "_NOI_BO/work/design")
aligned_dir <- file.path(work_dir, "_aligned")
qa_dir <- file.path(work_dir, "qa")
terra_tmp_dir <- file.path(work_dir, "_terra_tmp")
roi_file <- file.path(base, "00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson")
reference_file <- file.path(base, "_NOI_BO/config/pca_model_reference.json")
template_file <- file.path(work_dir, "grid_template.tif")
features <- c("CHIRPS", "DEM", "NDVI", "Slope", "TWI")
pc_names <- paste0("PC", seq_along(features))
pc_files <- file.path(work_dir, paste0(pc_names, ".tif"))
raw_covariate_files <- file.path(work_dir, paste0(features, ".tif"))
raw_provenance_file <- file.path(qa_dir, "raw_covariate_provenance.json")
sampling_file <- file.path(base, "01_THIET_KE_LAY_MAU/01_DAU_VAO/sampling.yml")
pca_fit_requested_n <- 200000L

dir.create(qa_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(terra_tmp_dir, recursive = TRUE, showWarnings = FALSE)
terraOptions(memfrac = 0.35, tempdir = terra_tmp_dir, progress = 1)

if (!file.exists(sampling_file)) stop("Missing sampling.yml; cannot set deterministic PCA seed.")
sampling_cfg <- yaml::read_yaml(sampling_file)
seed_numeric <- suppressWarnings(as.numeric(sampling_cfg$random_seed))
if (length(seed_numeric) != 1L || !is.finite(seed_numeric) ||
    seed_numeric != floor(seed_numeric) || seed_numeric < 0 ||
    seed_numeric > .Machine$integer.max) {
  stop("sampling.yml random_seed must be one integer from 0 to 2147483647.")
}
pca_seed <- as.integer(seed_numeric)

component_rows <- function(x) {
  unname(lapply(seq_len(nrow(x)), function(i) as.numeric(x[i, ])))
}

pca_parameter_payload <- function(feature_order, means, scales, components) {
  list(
    feature_order = as.character(feature_order),
    n_input_features = length(feature_order),
    n_retained_components = nrow(components),
    scaler_mean = as.numeric(means),
    scaler_scale = as.numeric(scales),
    pca_components = component_rows(components)
  )
}

pca_parameter_hash <- function(payload) {
  canonical <- jsonlite::toJSON(
    payload, auto_unbox = TRUE, digits = 17, null = "null", pretty = FALSE
  )
  digest::digest(canonical, algo = "sha256", serialize = FALSE)
}

freeze_reference <- function(ref, means, scales, components) {
  expected_n <- length(features)
  explained <- as.numeric(ref$pca_explained_variance_ratio)
  if (length(means) != expected_n || length(scales) != expected_n ||
      !identical(dim(components), c(expected_n, expected_n))) {
    stop("PCA reference must be full-rank 5x5 with five means and five scales.")
  }
  if (!all(is.finite(means)) || !all(is.finite(scales)) ||
      !all(is.finite(components)) || any(scales <= 0)) {
    stop("PCA reference contains non-finite values or non-positive scales.")
  }
  if (length(explained) != expected_n || !all(is.finite(explained)) ||
      any(explained < 0) || abs(sum(explained) - 1) > 1e-6) {
    stop("PCA explained-variance ratios must contain five non-negative values summing to one.")
  }
  orthogonality_error <- max(abs(tcrossprod(components) - diag(expected_n)))
  if (!is.finite(orthogonality_error) || orthogonality_error > 1e-6) {
    stop("PCA component rows are not orthonormal within tolerance.")
  }
  if (!identical(as.character(ref$feature_order), features)) {
    stop("Frozen PCA feature order does not match configured covariates.")
  }
  payload <- pca_parameter_payload(features, means, scales, components)
  parameter_hash <- pca_parameter_hash(payload)
  stored_parameter_hash <- if (is.null(ref$parameter_hash)) "" else as.character(ref$parameter_hash)[1]
  stored_reference_hash <- if (is.null(ref$reference_hash)) "" else as.character(ref$reference_hash)[1]
  if (nzchar(stored_parameter_hash) && nzchar(stored_reference_hash) &&
      !identical(stored_parameter_hash, stored_reference_hash)) {
    stop("Frozen PCA parameter_hash and reference_hash disagree.")
  }
  stored_hash <- if (nzchar(stored_parameter_hash)) stored_parameter_hash else stored_reference_hash
  if (nzchar(stored_hash) && !identical(stored_hash, parameter_hash)) {
    stop("Frozen PCA parameter hash mismatch. Do not silently refit or modify the reference.")
  }
  reference_version <- if (is.null(ref$reference_version)) {
    paste0(
      "pca-", length(features), "x", nrow(components),
      "-sha256-", substr(parameter_hash, 1, 12)
    )
  } else {
    as.character(ref$reference_version)[1]
  }
  ref$reference_schema_version <- "1.0.0"
  ref$feature_order <- features
  ref$n_components <- nrow(components)
  ref$n_input_features <- length(features)
  ref$n_retained_components <- nrow(components)
  ref$dimension_reduction_applied <- nrow(components) < length(features)
  ref$reference_policy <- "frozen_after_fit_for_workflow_reuse"
  ref$reference_frozen <- TRUE
  ref$reference_version <- reference_version
  ref$parameter_hash_algorithm <- "sha256"
  ref$parameter_hash <- parameter_hash
  # reference_hash is the stable compatibility key consumed by workflow 2.
  ref$reference_hash_algorithm <- "sha256"
  ref$reference_hash <- parameter_hash
  ref$scaler_mean <- as.numeric(means)
  ref$scaler_scale <- as.numeric(scales)
  ref$pca_components <- component_rows(components)
  jsonlite::write_json(
    ref, reference_file, pretty = TRUE, auto_unbox = TRUE,
    digits = 17, null = "null"
  )
  list(ref = ref, hash = parameter_hash, version = reference_version)
}

file_sha256 <- function(path) {
  if (!file.exists(path)) stop("Cannot hash missing file: ", path)
  tolower(unname(digest::digest(path, algo = "sha256", file = TRUE)))
}

named_file_hashes <- function(paths, labels) {
  if (length(paths) != length(labels) || anyDuplicated(labels)) {
    stop("Hash labels must uniquely match files.")
  }
  missing <- paths[!file.exists(paths)]
  if (length(missing)) stop("Cannot hash missing file(s): ", paste(missing, collapse = ", "))
  setNames(vapply(paths, file_sha256, character(1)), labels)
}

current_raw_lineage <- function() {
  required <- c(raw_provenance_file, raw_covariate_files)
  missing <- required[!file.exists(required)]
  if (length(missing)) {
    stop("Cannot certify PCA input lineage; missing: ", paste(missing, collapse = ", "))
  }
  provenance <- jsonlite::read_json(raw_provenance_file, simplifyVector = TRUE)
  recorded <- unlist(provenance$raw_covariate_sha256, use.names = TRUE)
  if (!setequal(names(recorded), features)) {
    stop("Raw provenance does not contain the exact configured covariate hash set.")
  }
  recorded <- tolower(as.character(recorded[features]))
  current <- named_file_hashes(raw_covariate_files, features)
  if (any(recorded != current)) {
    stop("Raw covariate hashes changed after the GEE provenance sidecar was written.")
  }
  list(
    raw_covariate_sha256 = as.list(current),
    raw_provenance_sha256 = file_sha256(raw_provenance_file),
    raw_provenance_path = gsub("\\\\", "/", raw_provenance_file)
  )
}

current_pca_hashes <- function() {
  named_file_hashes(pc_files, pc_names)
}

verify_metadata_refresh_inputs <- function() {
  summary_file <- file.path(qa_dir, "pca_summary.json")
  if (!file.exists(summary_file)) {
    stop("Cannot refresh PCA metadata without an existing certified summary; full PCA rebuild required.")
  }
  summary <- jsonlite::read_json(summary_file, simplifyVector = TRUE)
  if (!identical(as.character(summary$schema_version), "2.0.0") ||
      !isTRUE(summary$pca_input_lineage_verified) ||
      !isTRUE(summary$reference_frozen) ||
      !identical(as.character(summary$feature_order), features) ||
      !identical(as.integer(summary$n_input), length(features)) ||
      !identical(as.integer(summary$n_retained), length(features)) ||
      !identical(summary$dimension_reduction_applied, FALSE)) {
    stop("Existing PCA summary is not a certified full-rank v2 lineage record; full PCA rebuild required.")
  }

  lineage <- current_raw_lineage()
  recorded_raw <- unlist(summary$raw_covariate_sha256, use.names = TRUE)
  current_raw <- unlist(lineage$raw_covariate_sha256, use.names = TRUE)
  if (!setequal(names(recorded_raw), features) ||
      any(tolower(as.character(recorded_raw[features])) != current_raw[features]) ||
      !identical(tolower(as.character(summary$raw_provenance_sha256)), lineage$raw_provenance_sha256)) {
    stop("Existing PCA summary does not match current raw covariates; full PCA rebuild required.")
  }

  recorded_pcs <- unlist(summary$pca_raster_sha256, use.names = TRUE)
  current_pcs <- current_pca_hashes()
  if (!setequal(names(recorded_pcs), pc_names) ||
      any(tolower(as.character(recorded_pcs[pc_names])) != current_pcs[pc_names])) {
    stop("Existing PC raster bytes do not match certified hashes; full PCA rebuild required.")
  }

  reference <- jsonlite::read_json(reference_file, simplifyVector = TRUE)
  summary_parameter_hash <- tolower(as.character(summary$reference_hash))
  reference_hash <- tolower(as.character(reference$reference_hash))
  parameter_hash <- tolower(as.character(reference$parameter_hash))
  if (length(summary_parameter_hash) != 1L || length(reference_hash) != 1L ||
      length(parameter_hash) != 1L || !identical(summary_parameter_hash, reference_hash) ||
      !identical(reference_hash, parameter_hash)) {
    stop("Existing PCA summary and current reference parameter hashes disagree; full PCA rebuild required.")
  }
  if (!identical(tolower(as.character(summary$reference_file_sha256)), file_sha256(reference_file))) {
    stop("Current PCA reference bytes do not match the certified summary; full PCA rebuild required.")
  }
  invisible(TRUE)
}

write_pca_qa <- function(ref, reference_mode, parameter_hash, reference_version) {
  lineage <- current_raw_lineage()
  pca_hashes <- current_pca_hashes()
  explained <- as.numeric(ref$pca_explained_variance_ratio)
  n_retained <- as.integer(ref$n_retained_components)
  qa <- list(
    schema_version = "2.0.0",
    feature_order = features,
    n_input = length(features),
    n_retained = n_retained,
    dimension_reduction_applied = n_retained < length(features),
    transformation = if (n_retained < length(features)) {
      "standardized_PCA_dimension_reduction"
    } else {
      "standardized_full_rank_PCA_rotation"
    },
    explained_variance_ratio = explained,
    explained_variance_percent_retained = 100 * sum(explained[seq_len(n_retained)]),
    reference_mode = reference_mode,
    reference_policy = ref$reference_policy,
    reference_frozen = TRUE,
    reference_version = reference_version,
    reference_hash_algorithm = "sha256",
    reference_hash = parameter_hash,
    reference_path = gsub("\\\\", "/", reference_file),
    reference_file_sha256 = file_sha256(reference_file),
    pca_input_lineage_verified = TRUE,
    raw_covariate_sha256 = lineage$raw_covariate_sha256,
    raw_provenance_sha256 = lineage$raw_provenance_sha256,
    raw_provenance_path = lineage$raw_provenance_path,
    pca_raster_sha256 = as.list(pca_hashes),
    pca_fit_random_seed = ref$pca_fit_random_seed,
    pca_fit_sample_requested = ref$pca_fit_sample_requested,
    pca_fit_sample_returned = ref$pca_fit_sample_returned,
    pca_fit_sample_complete = ref$pca_fit_sample_complete,
    pca_fit_r_version = ref$pca_fit_r_version,
    pca_fit_terra_version = ref$pca_fit_terra_version,
    reproducibility_scope = "Seeded fit is repeatable within the recorded software environment; cross-version bitwise identity is not claimed.",
    roi_masked = TRUE,
    components_written = pc_names
  )
  jsonlite::write_json(
    qa, file.path(qa_dir, "pca_summary.json"),
    pretty = TRUE, auto_unbox = TRUE, digits = 17, null = "null", na = "null"
  )
}
metadata_only <- identical(Sys.getenv("PCA_METADATA_ONLY", unset = "0"), "1")
if (metadata_only) {
  required <- c(reference_file, template_file, pc_files)
  missing <- required[!file.exists(required)]
  if (length(missing)) {
    stop("Cannot refresh PCA metadata; missing: ", paste(missing, collapse = ", "))
  }
  template <- rast(template_file)[[1]]
  existing_pcs <- rast(pc_files)
  if (nlyr(existing_pcs) != length(features) ||
      !isTRUE(compareGeom(existing_pcs, template, stopOnError = FALSE)) ||
      !all(hasValues(existing_pcs))) {
    stop("Existing PCA rasters are incomplete or do not match the project grid.")
  }
  verify_metadata_refresh_inputs()
  ref <- jsonlite::read_json(reference_file, simplifyVector = TRUE)
  means <- as.numeric(ref$scaler_mean)
  scales <- as.numeric(ref$scaler_scale)
  components <- as.matrix(ref$pca_components)
  frozen <- freeze_reference(ref, means, scales, components)
  write_pca_qa(
    frozen$ref, "existing_frozen_reference_metadata_refresh",
    frozen$hash, frozen$version
  )
  cat("PCA metadata refreshed from existing frozen reference; rasters reused.\n")
  quit(save = "no", status = 0)
}

required <- c(roi_file, template_file, file.path(work_dir, paste0(features, ".tif")))
missing <- required[!file.exists(required)]
if (length(missing)) {
  stop("Missing sampling-design PCA asset(s): ", paste(missing, collapse = ", "))
}
dir.create(aligned_dir, recursive = TRUE, showWarnings = FALSE)
template <- rast(template_file)[[1]]

align_one <- function(path) {
  x <- rast(path)[[1]]
  if (isTRUE(compareGeom(x, template, stopOnError = FALSE))) return(x)
  if (same.crs(x, template)) {
    resample(x, template, method = "bilinear")
  } else {
    project(x, template, method = "bilinear")
  }
}

aligned_paths <- file.path(aligned_dir, paste0(features, ".tif"))
for (i in seq_along(features)) {
  x <- align_one(file.path(work_dir, paste0(features[[i]], ".tif")))
  names(x) <- features[[i]]
  writeRaster(
    x, aligned_paths[[i]], overwrite = TRUE, datatype = "FLT4S",
    gdal = c("COMPRESS=LZW", "BIGTIFF=IF_SAFER")
  )
  rm(x)
  gc(verbose = FALSE)
}
covs <- rast(aligned_paths)
names(covs) <- features

if (file.exists(reference_file)) {
  ref <- jsonlite::read_json(reference_file, simplifyVector = TRUE)
  means <- as.numeric(ref$scaler_mean)
  scales <- as.numeric(ref$scaler_scale)
  components <- as.matrix(ref$pca_components)
  reference_mode <- "existing_frozen_reference"
} else {
  set.seed(pca_seed)
  sample_values <- as.data.frame(
    spatSample(covs, size = pca_fit_requested_n, method = "random", na.rm = TRUE, values = TRUE)
  )
  pca_fit_sample_returned <- nrow(sample_values)
  sample_values <- sample_values[complete.cases(sample_values), features, drop = FALSE]
  if (nrow(sample_values) < 1000) {
    stop("Too few complete covariate pixels to fit PCA.")
  }
  fit <- prcomp(
    sample_values, center = TRUE, scale. = TRUE, rank. = length(features)
  )
  means <- as.numeric(fit$center)
  scales <- as.numeric(fit$scale)
  components <- t(fit$rotation)
  explained <- (fit$sdev^2) / sum(fit$sdev^2)
  ref <- list(
    source = "fitted from project sampling-design covariates",
    feature_order = features,
    n_components = nrow(components),
    explained_variance_percent = 100,
    scaler_mean = means,
    scaler_scale = scales,
    pca_components = component_rows(components),
    pca_explained_variance_ratio = as.numeric(explained),
    pca_fit_random_seed = pca_seed,
    pca_fit_sample_requested = pca_fit_requested_n,
    pca_fit_sample_returned = pca_fit_sample_returned,
    pca_fit_sample_complete = nrow(sample_values),
    pca_fit_r_version = R.version.string,
    pca_fit_terra_version = as.character(utils::packageVersion("terra"))
  )
  reference_mode <- "fitted_and_frozen_for_project"
}
frozen <- freeze_reference(ref, means, scales, components)
ref <- frozen$ref

python <- Sys.getenv("PCA_STREAM_PYTHON", unset = "")
if (!nzchar(python)) python <- Sys.which("python")
if (!nzchar(python)) {
  stop("Python is required for memory-safe streaming PCA raster creation.")
}
stream_script <- file.path(
  base, "_NOI_BO/pipeline/write_pca_rasters_streaming.py"
)
status <- system2(
  python, args = shQuote(normalizePath(stream_script, winslash = "/"))
)
if (!identical(as.integer(status), 0L)) {
  stop("Memory-safe streaming PCA raster creation failed.")
}
pc_stack <- rast(pc_files)
if (nlyr(pc_stack) != length(features) ||
    !isTRUE(compareGeom(pc_stack, template, stopOnError = FALSE)) ||
    !all(hasValues(pc_stack))) {
  stop("Streaming PCA outputs are incomplete or do not match the project grid.")
}
write_pca_qa(ref, reference_mode, frozen$hash, frozen$version)
cat("Sampling-design PCA support ready: ", work_dir, "; mode: ", reference_mode, "\n", sep = "")
