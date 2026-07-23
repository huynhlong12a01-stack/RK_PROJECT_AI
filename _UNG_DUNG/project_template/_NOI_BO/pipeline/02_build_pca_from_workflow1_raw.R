suppressPackageStartupMessages({
  library(sf)
  library(terra)
  library(yaml)
  library(jsonlite)
  library(readr)
  library(digest)
})

base <- "projects/{{PROJECT_ID}}"
internal <- file.path(base, "_NOI_BO")
cfg <- yaml::read_yaml(file.path(internal, "config/project.yml"))
source(file.path(internal, "pipeline/pca_support_provenance_utils.R"))

features <- c("CHIRPS", "DEM", "NDVI", "Slope", "TWI")
reference_file <- file.path(internal, "config/pca_model_reference.json")
pca_ref <- jsonlite::read_json(reference_file, simplifyVector = TRUE)
if (!identical(as.character(pca_ref$feature_order), features)) {
  stop("Frozen PCA feature order must be CHIRPS, DEM, NDVI, Slope and TWI.")
}
reference_hash <- tolower(as.character(pca_ref$reference_hash))
if (!isTRUE(pca_ref$reference_frozen) || !pca_support_is_sha256(reference_hash) ||
    !identical(tolower(as.character(pca_ref$parameter_hash)), reference_hash)) {
  stop("Frozen PCA reference is not certified.")
}
reference_version <- as.character(pca_ref$reference_version)
means <- as.numeric(pca_ref$scaler_mean)
scales <- as.numeric(pca_ref$scaler_scale)
components <- as.matrix(pca_ref$pca_components)
if (length(means) != length(features) || length(scales) != length(features) ||
    !identical(dim(components), c(length(features), length(features))) ||
    any(!is.finite(means)) || any(!is.finite(scales)) || any(scales <= 0) ||
    any(!is.finite(components))) {
  stop("Frozen PCA scaler/components are invalid.")
}

design_dir <- cfg$source$legacy_pca_dir
output_dir <- cfg$runtime$pca_support_dir
qa_dir <- cfg$runtime$qa_dir
points_file <- cfg$runtime$standardized_points_csv
roi_file <- cfg$source$roi_file
design_raw_files <- file.path(design_dir, paste0(features, ".tif"))
legacy_pc_files <- file.path(design_dir, paste0("PC", seq_along(features), ".tif"))
design_pca_summary_file <- file.path(design_dir, "qa/pca_summary.json")
design_raw_provenance_file <- file.path(design_dir, "qa/raw_covariate_provenance.json")
required <- c(
  design_raw_files, legacy_pc_files, design_pca_summary_file,
  design_raw_provenance_file, points_file, roi_file, reference_file
)
missing <- required[!file.exists(required)]
if (length(missing)) stop("Local PCA rebuild inputs are incomplete: ", paste(missing, collapse = ", "))

workflow1 <- pca_support_validate_workflow1(
  design_pca_summary_file, legacy_pc_files, design_raw_files,
  design_raw_provenance_file, features, pca_ref, reference_file, cfg, roi_file
)
if (!isTRUE(workflow1$valid)) {
  stop("Workflow 1 raw/PCA lineage is not trustworthy: ", paste(workflow1$reasons, collapse = "; "))
}

points <- as.data.frame(readr::read_csv(points_file, show_col_types = FALSE, progress = FALSE))
if (!all(c("code", "lat", "lon") %in% names(points))) {
  stop("Standardized actual samples must contain code, lat and lon.")
}
sample_coordinate_hash <- pca_support_coordinate_sha256(points)

template <- terra::rast(design_raw_files[[1]])[[1]]
if (any(!vapply(design_raw_files, function(path) {
  isTRUE(terra::compareGeom(terra::rast(path)[[1]], template, stopOnError = FALSE))
}, logical(1)))) {
  stop("Certified Workflow 1 raw covariates do not share one grid.")
}

points_sf <- sf::st_as_sf(points, coords = c("lon", "lat"), crs = 4326, remove = FALSE)
points_sf <- sf::st_transform(points_sf, sf::st_crs(terra::crs(template)))
points_vect <- terra::vect(points_sf)
point_cells <- terra::cellFromXY(template, terra::crds(points_vect))
if (any(is.na(point_cells))) {
  stop("Workflow 1 raw grid does not cover every actual sample; external support is required.")
}
raw_stack <- terra::rast(design_raw_files)
names(raw_stack) <- features
point_raw <- as.data.frame(terra::extract(raw_stack, points_vect))
point_raw <- point_raw[, setdiff(names(point_raw), "ID"), drop = FALSE]
if (ncol(point_raw) != length(features) || any(!is.finite(as.matrix(point_raw)))) {
  stop("Workflow 1 raw covariates are incomplete at one or more actual samples; external support is required.")
}

align_to_raw <- function(path) {
  x <- terra::rast(path)[[1]]
  if (isTRUE(terra::compareGeom(x, template, stopOnError = FALSE))) return(x)
  if (terra::same.crs(x, template)) return(terra::resample(x, template, method = "bilinear"))
  terra::project(x, template, method = "bilinear")
}
legacy_aligned <- lapply(legacy_pc_files, align_to_raw)
legacy_mask <- terra::ifel(!is.na(legacy_aligned[[1]]), 1, NA)
actual_point_mask <- terra::rasterize(
  points_vect, template, field = 1, background = NA, touches = TRUE
)
analytical_mask <- terra::cover(legacy_mask, actual_point_mask)

z <- vector("list", terra::nlyr(raw_stack))
for (i in seq_len(terra::nlyr(raw_stack))) {
  z[[i]] <- (raw_stack[[i]] - means[[i]]) / scales[[i]]
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(qa_dir, recursive = TRUE, showWarnings = FALSE)
for (j in seq_len(nrow(components))) {
  computed_pc <- z[[1]] * components[j, 1]
  for (i in 2:terra::nlyr(raw_stack)) {
    computed_pc <- computed_pc + z[[i]] * components[j, i]
  }
  computed_pc <- terra::mask(computed_pc, analytical_mask)
  hybrid_pc <- terra::cover(legacy_aligned[[j]], computed_pc)
  hybrid_pc <- terra::mask(hybrid_pc, analytical_mask)
  names(hybrid_pc) <- paste0("PC", j)
  terra::writeRaster(
    hybrid_pc, file.path(output_dir, paste0("PC", j, ".tif")),
    overwrite = TRUE, datatype = "FLT4S",
    gdal = c("COMPRESS=LZW", "BIGTIFF=IF_SAFER")
  )
}

pc_files <- file.path(output_dir, paste0("PC", seq_along(features), ".tif"))
pc_labels <- paste0("PC", seq_along(features), ".tif")
point_pc <- as.data.frame(terra::extract(terra::rast(pc_files), points_vect))
point_pc <- point_pc[, setdiff(names(point_pc), "ID"), drop = FALSE]
if (ncol(point_pc) != length(features) || any(!is.finite(as.matrix(point_pc)))) {
  stop("Local PCA rebuild did not produce complete PC values at every actual sample.")
}
pc_hashes <- pca_support_named_hashes(pc_files, pc_labels)
pca_output_grid <- pca_support_file_grid(pc_files[[1]])
provenance <- list(
  schema_version = "2.0.0",
  provenance_type = "interpolation_pca_lineage",
  provenance_mode = "local_rebuild_from_verified_workflow1_raw_covariates",
  project_id = as.character(cfg$project_id),
  verification_status = "verified_full_hash_chain",
  pca_reference_hash = reference_hash,
  reference_frozen = TRUE,
  reference_version = reference_version,
  reference_file_sha256 = pca_support_sha256(reference_file),
  sample_coordinate_sha256 = sample_coordinate_hash,
  source_workflow1_pca_summary_sha256 = workflow1$design_summary_sha256,
  source_workflow1_raw_provenance_sha256 = workflow1$design_raw_provenance_sha256,
  source_workflow1_pc_sha256 = workflow1$design_pc_sha256,
  source_workflow1_raw_covariate_sha256 = workflow1$design_raw_sha256,
  source_workflow1_identity_sha256 = workflow1$source_identity_sha256,
  source_workflow1_grid_sha256 = workflow1$output_grid_sha256,
  raw_covariate_sha256 = workflow1$design_raw_sha256,
  roi_field_area_sha256 = pca_support_sha256(roi_file),
  raw_covariate_source = "verified_workflow1_raw_covariates",
  workflow1_pc_values_prioritized = TRUE,
  download_geometry_is_not_prediction_domain = TRUE,
  analytical_support_mask_policy = "workflow1_pc_mask_plus_actual_sample_cells_local_only",
  external_data_transfer_for_pca_refresh = FALSE,
  actual_sample_geometry_sent_to_gee = FALSE,
  gee_support_download_used = FALSE,
  verified_actual_sample_count = nrow(points),
  pca_output_grid = pca_output_grid,
  pca_output_grid_sha256 = pca_support_json_sha256(pca_output_grid),
  pc_file_sha256 = as.list(pc_hashes),
  generated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
)
provenance_file <- file.path(qa_dir, "pca_current_provenance.json")
temporary <- paste0(provenance_file, ".tmp")
jsonlite::write_json(
  provenance, temporary, pretty = TRUE, auto_unbox = TRUE,
  digits = 17, null = "null", na = "null"
)
if (file.exists(provenance_file)) unlink(provenance_file)
if (!file.rename(temporary, provenance_file)) {
  stop("Could not atomically publish local PCA provenance.")
}
cat(
  "Local PCA rebuild complete from certified Workflow 1 raw covariates; ",
  nrow(points), " actual samples verified; no external data transfer.\n", sep = ""
)