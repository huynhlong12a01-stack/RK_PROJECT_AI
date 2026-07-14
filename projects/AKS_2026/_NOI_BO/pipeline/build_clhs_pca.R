suppressPackageStartupMessages({
  library(terra)
  library(jsonlite)
  library(digest)
})

base <- "projects/AKS_2026"
work_dir <- file.path(base, "_NOI_BO/work/design")
aligned_dir <- file.path(work_dir, "_aligned")
qa_dir <- file.path(work_dir, "qa")
terra_tmp_dir <- file.path(work_dir, "_terra_tmp")
roi_file <- file.path(base, "01_THIET_KE_LAY_MAU/01_DAU_VAO/roi.geojson")
reference_file <- file.path(base, "_NOI_BO/config/pca_model_reference.json")
template_file <- file.path(work_dir, "grid_template.tif")
features <- c("CHIRPS", "DEM", "NDVI", "Slope", "TWI")
pc_files <- file.path(work_dir, paste0("PC", seq_along(features), ".tif"))

dir.create(qa_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(terra_tmp_dir, recursive = TRUE, showWarnings = FALSE)
terraOptions(memfrac = 0.35, tempdir = terra_tmp_dir, progress = 1)

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
  if (length(means) != length(features) || ncol(components) != length(features)) {
    stop("PCA reference dimensions do not match configured covariates.")
  }
  if (!identical(as.character(ref$feature_order), features)) {
    stop("Frozen PCA feature order does not match configured covariates.")
  }
  payload <- pca_parameter_payload(features, means, scales, components)
  parameter_hash <- pca_parameter_hash(payload)
  stored_hash <- if (is.null(ref$parameter_hash)) "" else as.character(ref$parameter_hash)[1]
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
  ref$scaler_mean <- as.numeric(means)
  ref$scaler_scale <- as.numeric(scales)
  ref$pca_components <- component_rows(components)
  jsonlite::write_json(
    ref, reference_file, pretty = TRUE, auto_unbox = TRUE,
    digits = 17, null = "null"
  )
  list(ref = ref, hash = parameter_hash, version = reference_version)
}

write_pca_qa <- function(ref, reference_mode, parameter_hash, reference_version) {
  explained <- as.numeric(ref$pca_explained_variance_ratio)
  n_retained <- as.integer(ref$n_retained_components)
  qa <- list(
    schema_version = "1.0.0",
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
    roi_masked = TRUE,
    components_written = paste0("PC", seq_len(n_retained))
  )
  jsonlite::write_json(
    qa, file.path(qa_dir, "pca_summary.json"),
    pretty = TRUE, auto_unbox = TRUE, digits = 17, null = "null"
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
  sample_values <- as.data.frame(
    spatSample(covs, size = 200000, method = "random", na.rm = TRUE, values = TRUE)
  )
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
    pca_explained_variance_ratio = as.numeric(explained)
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
