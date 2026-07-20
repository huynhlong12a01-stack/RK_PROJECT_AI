suppressPackageStartupMessages({
  library(sf)
  library(terra)
  library(yaml)
  library(jsonlite)
  library(readr)
  library(digest)
})

base <- "projects/PHU_YEN_MOCK"
internal <- file.path(base, "_NOI_BO")
cfg <- yaml::read_yaml(file.path(internal, "config/project.yml"))
reference_file <- file.path(internal, "config/pca_model_reference.json")
pca_ref <- jsonlite::read_json(reference_file, simplifyVector = TRUE)
source(file.path(internal, "pipeline/pca_support_provenance_utils.R"))

features <- c("CHIRPS", "DEM", "NDVI", "Slope", "TWI")
feature_order <- as.character(pca_ref$feature_order)
if (!identical(feature_order, features)) {
  stop("Frozen PCA reference must contain exactly CHIRPS, DEM, NDVI, Slope and TWI in that order.")
}
pca_reference_hash <- tolower(as.character(pca_ref$reference_hash))
pca_reference_frozen <- isTRUE(pca_ref$reference_frozen)
pca_reference_version <- as.character(pca_ref$reference_version)
if (!pca_support_is_sha256(pca_reference_hash)) {
  stop("Frozen PCA reference lacks a valid lowercase SHA-256 reference_hash.")
}
if (!pca_reference_frozen) stop("PCA support rebuild requires reference_frozen=true.")
if (length(pca_reference_version) != 1L || is.na(pca_reference_version) || !nzchar(pca_reference_version)) {
  stop("Frozen PCA reference lacks reference_version.")
}
if (!identical(tolower(as.character(pca_ref$parameter_hash)), pca_reference_hash)) {
  stop("Frozen PCA parameter_hash and reference_hash disagree.")
}

source_dir <- cfg$runtime$expanded_covariate_dir
aligned_dir <- cfg$runtime$aligned_covariate_dir
output_dir <- cfg$runtime$pca_support_dir
qa_dir <- cfg$runtime$qa_dir
design_dir <- cfg$source$legacy_pca_dir
roi_file <- cfg$source$roi_file
buffers_path <- cfg$runtime$support_buffers_gpkg
points_file <- cfg$runtime$standardized_points_csv
download_sidecar <- file.path(qa_dir, "gee_support_download_summary.json")
legacy_template_file <- file.path(design_dir, "PC1.tif")
design_pca_summary_file <- file.path(design_dir, "qa/pca_summary.json")
design_raw_provenance_file <- file.path(design_dir, "qa/raw_covariate_provenance.json")
source_files <- file.path(source_dir, paste0(feature_order, ".tif"))
legacy_pc_files <- file.path(design_dir, paste0("PC", seq_along(features), ".tif"))
design_raw_files <- file.path(design_dir, paste0(features, ".tif"))

required <- c(
  source_files, legacy_pc_files, design_raw_files, roi_file, buffers_path,
  points_file, download_sidecar, reference_file, design_pca_summary_file,
  design_raw_provenance_file
)
missing <- required[!file.exists(required)]
if (length(missing)) {
  stop("PCA support inputs are incomplete: ", paste(missing, collapse = ", "))
}
download_lineage <- pca_support_validate_download(
  download_sidecar, source_files, feature_order, cfg, roi_file,
  buffers_path, legacy_template_file
)
if (!isTRUE(download_lineage$valid)) {
  stop(
    "Support covariates are complete but their provenance is not trustworthy: ",
    paste(download_lineage$reasons, collapse = "; "),
    ". Re-download support covariates."
  )
}
workflow1_lineage <- pca_support_validate_workflow1(
  design_pca_summary_file, legacy_pc_files, design_raw_files,
  design_raw_provenance_file, features, pca_ref, reference_file, cfg, roi_file
)
if (!isTRUE(workflow1_lineage$valid)) {
  stop(
    "Workflow 1 PC source lineage is not trustworthy: ",
    paste(workflow1_lineage$reasons, collapse = "; ")
  )
}

points <- as.data.frame(readr::read_csv(points_file, show_col_types = FALSE, progress = FALSE))
sample_coordinate_hash <- pca_support_coordinate_sha256(points)
means <- as.numeric(pca_ref$scaler_mean)
scales <- as.numeric(pca_ref$scaler_scale)
components <- as.matrix(pca_ref$pca_components)
if (length(means) != length(features) || length(scales) != length(features) ||
    !identical(dim(components), c(length(features), length(features))) ||
    any(!is.finite(means)) || any(!is.finite(scales)) || any(scales <= 0) ||
    any(!is.finite(components))) {
  stop("Frozen PCA reference dimensions or scaler/component values are invalid.")
}

dir.create(aligned_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(qa_dir, recursive = TRUE, showWarnings = FALSE)

# The verified support covariates define the expanded aligned union grid. This
# grid may extend beyond the Workflow 1 PC1 bounding box.
template <- rast(source_files[[1]])[[1]]
if (any(!vapply(source_files, function(path) {
  isTRUE(compareGeom(rast(path)[[1]], template, stopOnError = FALSE))
}, logical(1)))) {
  stop("Verified support covariates no longer share the provenance grid.")
}

align_to_support <- function(path, method = "bilinear") {
  x <- rast(path)[[1]]
  if (isTRUE(compareGeom(x, template, stopOnError = FALSE))) return(x)
  if (same.crs(x, template)) {
    return(resample(x, template, method = method))
  }
  project(x, template, method = method)
}

aligned <- vector("list", length(feature_order))
for (i in seq_along(feature_order)) {
  aligned[[i]] <- align_to_support(source_files[[i]], "bilinear")
  names(aligned[[i]]) <- feature_order[[i]]
  writeRaster(
    aligned[[i]], file.path(aligned_dir, paste0(feature_order[[i]], ".tif")),
    overwrite = TRUE, datatype = "FLT4S",
    gdal = c("COMPRESS=LZW", "BIGTIFF=IF_SAFER")
  )
}
covs <- rast(aligned)
names(covs) <- feature_order

legacy_aligned <- lapply(legacy_pc_files, align_to_support, method = "bilinear")
legacy_mask <- ifel(!is.na(legacy_aligned[[1]]), 1, NA)
if (!all(c("lon", "lat") %in% names(points))) {
  stop("Standardized actual samples must contain lon and lat for the local PCA support mask.")
}
# The broad envelope is download-only. The analytical PCA/model domain keeps
# the verified Workflow 1 mask plus only raster cells containing actual sample
# locations. Actual point geometry is constructed locally and never sent to GEE.
actual_points_sf <- sf::st_as_sf(
  points, coords = c("lon", "lat"), crs = 4326, remove = FALSE
)
actual_points_sf <- sf::st_transform(actual_points_sf, sf::st_crs(terra::crs(template)))
actual_points_vect <- terra::vect(actual_points_sf)
actual_cells <- terra::cellFromXY(template, terra::crds(actual_points_vect))
if (any(is.na(actual_cells))) {
  stop("The verified GEE support grid does not cover every actual sample cell.")
}
actual_point_mask <- terra::rasterize(
  actual_points_vect, template, field = 1, background = NA, touches = TRUE
)
support_mask <- terra::cover(legacy_mask, actual_point_mask)

z <- vector("list", nlyr(covs))
for (i in seq_len(nlyr(covs))) z[[i]] <- (covs[[i]] - means[[i]]) / scales[[i]]

for (j in seq_len(nrow(components))) {
  computed_pc <- z[[1]] * components[j, 1]
  if (nlyr(covs) > 1) {
    for (i in 2:nlyr(covs)) computed_pc <- computed_pc + z[[i]] * components[j, i]
  }
  computed_pc <- terra::mask(computed_pc, support_mask)
  # Exact Workflow 1 values have priority wherever their original mask exists;
  # newly computed frozen-reference values fill only verified support cells.
  hybrid_pc <- terra::cover(legacy_aligned[[j]], computed_pc)
  hybrid_pc <- terra::mask(hybrid_pc, support_mask)
  names(hybrid_pc) <- paste0("PC", j)
  writeRaster(
    hybrid_pc, file.path(output_dir, paste0("PC", j, ".tif")),
    overwrite = TRUE, datatype = "FLT4S",
    gdal = c("COMPRESS=LZW", "BIGTIFF=IF_SAFER")
  )
}

pc_output_files <- file.path(output_dir, paste0("PC", seq_along(features), ".tif"))
pc_output_labels <- paste0("PC", seq_along(features), ".tif")
pc_output_hashes <- pca_support_named_hashes(pc_output_files, pc_output_labels)
pca_output_grid <- pca_support_file_grid(pc_output_files[[1]])
download_payload <- download_lineage$payload
pca_provenance <- list(
  schema_version = "2.0.0",
  provenance_type = "interpolation_pca_lineage",
  provenance_mode = "support_rebuild_from_verified_gee_covariates",
  project_id = as.character(cfg$project_id),
  verification_status = "verified_full_hash_chain",
  pca_reference_hash = pca_reference_hash,
  reference_frozen = pca_reference_frozen,
  reference_version = pca_reference_version,
  reference_file_sha256 = pca_support_sha256(reference_file),
  sample_coordinate_sha256 = sample_coordinate_hash,
  source_workflow1_pca_summary_sha256 = workflow1_lineage$design_summary_sha256,
  source_workflow1_raw_provenance_sha256 = workflow1_lineage$design_raw_provenance_sha256,
  source_workflow1_pc_sha256 = workflow1_lineage$design_pc_sha256,
  source_workflow1_raw_covariate_sha256 = workflow1_lineage$design_raw_sha256,
  source_workflow1_identity_sha256 = workflow1_lineage$source_identity_sha256,
  source_workflow1_grid_sha256 = workflow1_lineage$output_grid_sha256,
  raw_covariate_sha256 = download_lineage$raw_covariate_sha256,
  support_download_provenance_sha256 = download_lineage$sidecar_sha256,
  support_geometry_provenance_sha256 = download_lineage$support_geometry_provenance_sha256,
  support_source_identity_sha256 = download_lineage$source_identity_sha256,
  support_output_grid_sha256 = download_lineage$output_grid_sha256,
  roi_field_area_sha256 = pca_support_sha256(roi_file),
  support_buffer_sha256 = pca_support_sha256(buffers_path),
  support_geometry_policy = as.character(download_payload$source_identity$support_geometry_policy),
  support_privacy_gate_status = as.character(download_payload$privacy_gate$status),
  download_geometry_is_not_prediction_domain = TRUE,
  analytical_support_mask_policy = "workflow1_pc_mask_plus_actual_sample_cells_local_only",
  actual_sample_geometry_sent_to_gee = FALSE,
  legacy_grid_template_sha256 = pca_support_sha256(legacy_template_file),
  gee_project_id = as.character(download_payload$source_identity$gee_project_id),
  start_date = as.character(download_payload$source_identity$start_date),
  end_date = as.character(download_payload$source_identity$end_date),
  crs = as.character(download_payload$output_grid$crs),
  computational_grid_m = as.numeric(download_payload$output_grid$computational_grid_m),
  pca_output_grid = pca_output_grid,
  pca_output_grid_sha256 = pca_support_json_sha256(pca_output_grid),
  pc_file_sha256 = as.list(pc_output_hashes),
  generated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
)
jsonlite::write_json(
  pca_provenance, file.path(qa_dir, "pca_current_provenance.json"),
  pretty = TRUE, auto_unbox = TRUE, digits = 17, null = "null"
)
unlink(file.path(qa_dir, "pca_current_provenance_points.csv"), force = TRUE)

# Soil class remains an audit/stratification layer. It is aligned to the same
# expanded support grid, never used to alter the five frozen PCA components.
soil_source <- file.path(source_dir, "Soil_Class.tif")
if (file.exists(soil_source)) {
  soil <- align_to_support(soil_source, "near")
  soil <- terra::mask(soil, support_mask)
  writeRaster(
    soil, file.path(aligned_dir, "Soil_Class_support.tif"),
    overwrite = TRUE, datatype = "INT2S",
    gdal = c("COMPRESS=LZW", "BIGTIFF=IF_SAFER")
  )
}

pts <- terra::vect(points, geom = c("lon", "lat"), crs = "EPSG:4326")
pts <- terra::project(pts, paste0("EPSG:", cfg$crs_epsg))
pc_stack <- rast(pc_output_files)
pc_values <- terra::extract(pc_stack, pts)[, -1, drop = FALSE]
complete <- stats::complete.cases(pc_values)
coverage <- data.frame(code = points$code, complete_pca_support = complete, pc_values)
coverage_path <- file.path(qa_dir, "pca_support_point_coverage.csv")
readr::write_csv(coverage, coverage_path, na = "")

summary <- list(
  schema_version = "2.0.0",
  project_id = cfg$project_id,
  feature_order = feature_order,
  pca_policy = cfg$support_policy$pca_policy,
  provenance_mode = pca_provenance$provenance_mode,
  pca_reference_hash = pca_reference_hash,
  reference_frozen = pca_reference_frozen,
  reference_version = pca_reference_version,
  sample_coordinate_sha256 = sample_coordinate_hash,
  support_download_provenance_sha256 = download_lineage$sidecar_sha256,
  pca_output_grid_sha256 = pca_provenance$pca_output_grid_sha256,
  provenance_sidecar = normalizePath(
    file.path(qa_dir, "pca_current_provenance.json"),
    winslash = "/", mustWork = FALSE
  ),
  legacy_pc_priority = cfg$support_policy$legacy_pc_priority_inside_existing_mask,
  n_points = nrow(points),
  n_points_with_complete_pc = sum(complete),
  n_points_missing_pc = sum(!complete),
  output_dir = normalizePath(output_dir, winslash = "/", mustWork = FALSE),
  coverage_csv = normalizePath(coverage_path, winslash = "/", mustWork = FALSE)
)
jsonlite::write_json(
  summary, file.path(qa_dir, "pca_support_summary.json"),
  pretty = TRUE, auto_unbox = TRUE, digits = 17, null = "null"
)
if (any(!complete)) {
  stop("PCA support remains missing for ", sum(!complete), " sample(s). See ", coverage_path)
}
cat("PCA support build complete with schema-v2 lineage: all ", nrow(points), " samples covered.\n", sep = "")
