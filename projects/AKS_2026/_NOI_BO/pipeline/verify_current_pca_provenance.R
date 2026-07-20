suppressPackageStartupMessages({
  library(terra)
  library(readr)
  library(jsonlite)
  library(yaml)
  library(digest)
  library(sf)
})

base <- "projects/AKS_2026"
internal <- file.path(base, "_NOI_BO")
ref_file <- file.path(internal, "config/pca_model_reference.json")
point_file <- file.path(internal, "work/interpolation/sample_actual_clean.csv")
design_dir <- file.path(internal, "work/design")
current_dir <- file.path(internal, "work/interpolation")
qa_dir <- file.path(current_dir, "qa")
sidecar_file <- file.path(qa_dir, "pca_current_provenance.json")
cfg <- yaml::read_yaml(file.path(internal, "config/project.yml"))
source(file.path(internal, "pipeline/pca_support_provenance_utils.R"))

# Retained as a pure compatibility helper for the focused lazy-raw unit test.
# The active no-support route below uses the stronger exact whole-file copy proof.
resolve_expected_pca <- function(design, n_points, n_components, ref, raw_loader) {
  if (is.null(design)) design <- matrix(NA_real_, nrow = n_points, ncol = n_components)
  design_complete <- stats::complete.cases(design)
  raw_complete <- rep(FALSE, n_points)
  raw_pc <- matrix(NA_real_, nrow = n_points, ncol = n_components)
  raw_loaded <- FALSE
  raw_available <- FALSE
  if (any(!design_complete)) {
    raw_loaded <- TRUE
    raw <- raw_loader()
    raw_available <- !is.null(raw)
    if (raw_available) {
      raw_complete <- stats::complete.cases(raw)
      z <- sweep(raw, 2, as.numeric(ref$scaler_mean), "-")
      z <- sweep(z, 2, as.numeric(ref$scaler_scale), "/")
      raw_pc <- z %*% t(as.matrix(ref$pca_components))
    }
  }
  expected <- matrix(NA_real_, nrow = n_points, ncol = n_components)
  verification_source <- rep("unavailable", n_points)
  expected[design_complete, ] <- design[design_complete, , drop = FALSE]
  verification_source[design_complete] <- "workflow1_frozen_pca_raster"
  use_raw <- !design_complete & raw_complete
  expected[use_raw, ] <- raw_pc[use_raw, , drop = FALSE]
  verification_source[use_raw] <- "raw_covariates_recomputed_with_frozen_reference"
  list(
    expected = expected, verification_source = verification_source,
    design_complete = design_complete, use_raw = use_raw,
    raw_loaded = raw_loaded, raw_available = raw_available
  )
}

features <- c("CHIRPS", "DEM", "NDVI", "Slope", "TWI")
pc_labels <- paste0("PC", seq_along(features))
pc_file_labels <- paste0(pc_labels, ".tif")
current_files <- file.path(current_dir, pc_file_labels)
design_files <- file.path(design_dir, pc_file_labels)
design_raw_files <- file.path(design_dir, paste0(features, ".tif"))
design_summary_file <- file.path(design_dir, "qa/pca_summary.json")
design_raw_provenance_file <- file.path(design_dir, "qa/raw_covariate_provenance.json")
roi_file <- cfg$source$roi_file
required <- c(
  ref_file, point_file, current_files, design_files, design_raw_files,
  design_summary_file, design_raw_provenance_file, roi_file
)
missing <- required[!file.exists(required)]
if (length(missing)) stop("Cannot certify Workflow 1 PCA copy; missing: ", paste(missing, collapse = ", "))

ref <- jsonlite::read_json(ref_file, simplifyVector = TRUE)
if (!identical(as.character(ref$feature_order), features)) {
  stop("Frozen PCA feature order does not match the five Workflow 1 covariates.")
}
workflow1 <- pca_support_validate_workflow1(
  design_summary_file, design_files, design_raw_files,
  design_raw_provenance_file, features, ref, ref_file, cfg, roi_file
)
if (!isTRUE(workflow1$valid)) {
  stop("Workflow 1 lineage is not trustworthy: ", paste(workflow1$reasons, collapse = "; "))
}
source_hashes <- unlist(workflow1$design_pc_sha256, use.names = TRUE)
current_hashes_by_file <- pca_support_named_hashes(current_files, pc_file_labels)
current_hashes_by_component <- setNames(unname(current_hashes_by_file), pc_labels)
if (!pca_support_exact_hash_map(source_hashes, current_hashes_by_component, pc_labels)) {
  stop("Current interpolation PC rasters are not exact byte-for-byte copies of Workflow 1 PCs.")
}

points <- as.data.frame(readr::read_csv(point_file, show_col_types = FALSE, progress = FALSE))
coordinate_hash <- pca_support_coordinate_sha256(points)
pca_output_grid <- pca_support_file_grid(current_files[[1]])
ref_hash <- tolower(as.character(ref$reference_hash))
if (!isTRUE(ref$reference_frozen) || !pca_support_is_sha256(ref_hash)) {
  stop("PCA reference is not a valid frozen reference.")
}

dir.create(qa_dir, recursive = TRUE, showWarnings = FALSE)
point_verification <- data.frame(
  code = points$code,
  verification_source = "exact_workflow1_file_copy",
  maximum_absolute_pc_error = 0,
  stringsAsFactors = FALSE
)
readr::write_csv(
  point_verification,
  file.path(qa_dir, "pca_current_provenance_points.csv"),
  na = ""
)
jsonlite::write_json(
  list(
    schema_version = "2.0.0",
    provenance_type = "interpolation_pca_lineage",
    provenance_mode = "verified_workflow1_copy",
    project_id = as.character(cfg$project_id),
    verification_status = "verified_full_hash_chain",
    pca_reference_hash = ref_hash,
    reference_frozen = TRUE,
    reference_version = as.character(ref$reference_version),
    reference_file_sha256 = pca_support_sha256(ref_file),
    sample_coordinate_sha256 = coordinate_hash,
    source_workflow1_pca_summary_sha256 = workflow1$design_summary_sha256,
    source_workflow1_raw_provenance_sha256 = workflow1$design_raw_provenance_sha256,
    source_workflow1_pc_sha256 = workflow1$design_pc_sha256,
    source_workflow1_raw_covariate_sha256 = workflow1$design_raw_sha256,
    source_workflow1_identity_sha256 = workflow1$source_identity_sha256,
    source_workflow1_grid_sha256 = workflow1$output_grid_sha256,
    pca_output_grid = pca_output_grid,
    pca_output_grid_sha256 = pca_support_json_sha256(pca_output_grid),
    n_points = nrow(points),
    n_verified_total = nrow(points),
    pc_file_sha256 = as.list(current_hashes_by_file),
    generated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
  ),
  sidecar_file, pretty = TRUE, auto_unbox = TRUE,
  digits = 17, null = "null"
)

# Route-specific QA from an older support rebuild must not masquerade as active.
unlink(
  file.path(
    qa_dir,
    c(
      "pca_support_summary.json",
      "pca_support_point_coverage.csv",
      "gee_support_download_summary.json"
    )
  ),
  force = TRUE
)
cat("Current PCA provenance verified as an exact schema-v2 Workflow 1 copy for ", nrow(points), " samples.\n", sep = "")
