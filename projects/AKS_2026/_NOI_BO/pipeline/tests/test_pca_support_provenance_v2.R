suppressPackageStartupMessages({
  library(terra)
  library(sf)
  library(jsonlite)
  library(digest)
})
source("projects/AKS_2026/_NOI_BO/pipeline/pca_support_provenance_utils.R")

root <- tempfile("rk_pca_support_lineage_")
dir.create(root, recursive = TRUE)
on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
features <- c("CHIRPS", "DEM", "NDVI", "Slope", "TWI")
pc_labels <- paste0("PC", 1:5)
pc_file_labels <- paste0(pc_labels, ".tif")
cfg <- list(
  project_id = "FIXTURE",
  gee_project_id = "gee-fixture",
  crs_epsg = 32649L,
  resolution_m = 10,
  support_policy = list(
    support_geometry_policy = "fixed_roi_buffer_no_sample_geometry",
    covariate_support_buffer_m = 300
  ),
  legacy_parameters = list(start_date = "2025-01-01", end_date = "2026-01-01")
)

write_fixture_raster <- function(path, xmin, xmax, ymin, ymax, value) {
  x <- rast(ncols = as.integer((xmax - xmin) / 10), nrows = as.integer((ymax - ymin) / 10),
            xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, crs = "EPSG:32649")
  values(x) <- value
  writeRaster(x, path, overwrite = TRUE, datatype = "FLT4S", gdal = "COMPRESS=LZW")
}
write_json <- function(value, path) {
  jsonlite::write_json(
    value, path, pretty = TRUE, auto_unbox = TRUE,
    digits = 17, null = "null", na = "null"
  )
}

roi_file <- file.path(root, "roi.geojson")
buffer_file <- file.path(root, "buffers.gpkg")
roi <- st_sf(id = 1L, geometry = st_sfc(st_polygon(list(matrix(
  c(0, 0, 40, 0, 40, 40, 0, 40, 0, 0), ncol = 2, byrow = TRUE
))), crs = 32649))
buffer <- st_sf(
  support_geometry_policy = "fixed_roi_buffer_no_sample_geometry",
  support_buffer_m = 300,
  contains_sample_attributes = FALSE,
  geometry = st_buffer(st_as_sfc(st_bbox(roi)), dist = 300, nQuadSegs = 30)
)
st_write(roi, roi_file, quiet = TRUE)
st_write(buffer, buffer_file, layer = "roi_fixed_covariate_support", quiet = TRUE)

legacy_dir <- file.path(root, "design")
support_dir <- file.path(root, "support")
copy_dir <- file.path(root, "copy")
local_dir <- file.path(root, "local")
dir.create(legacy_dir)
dir.create(support_dir)
dir.create(copy_dir)
dir.create(local_dir)
support_geometry_privacy_file <- file.path(support_dir, "support_geometry_privacy.json")
support_geometry_privacy <- list(
  schema_version = "1.0.0",
  provenance_type = "privacy_preserving_support_geometry",
  status = "certified_by_preflight",
  project_id = cfg$project_id,
  support_geometry_policy = cfg$support_policy$support_geometry_policy,
  geometry_source = "reviewed_roi_bounding_envelope_plus_fixed_metric_buffer",
  geometry_derivation = "sf_projected_bbox_then_st_buffer_nQuadSegs_30",
  coverage_guarantee = "contains_the_fixed_metric_buffer_of_the_reviewed_roi",
  project_crs = "EPSG:32649",
  support_buffer_m = cfg$support_policy$covariate_support_buffer_m,
  feature_count = 1L,
  attribute_schema = c(
    "support_geometry_policy", "support_buffer_m", "contains_sample_attributes"
  ),
  contains_sample_attributes = FALSE,
  sample_coordinates_or_identifiers_used_to_define_geometry = FALSE,
  sample_coordinates_or_identifiers_in_attributes = FALSE,
  roi_field_area_sha256 = pca_support_sha256(roi_file),
  support_geometry_file_sha256 = pca_support_sha256(buffer_file)
)
write_json(support_geometry_privacy, support_geometry_privacy_file)
legacy_template <- file.path(legacy_dir, "PC1.tif")
design_pc_files <- file.path(legacy_dir, pc_file_labels)
design_raw_files <- file.path(legacy_dir, paste0(features, ".tif"))
support_raw_files <- file.path(support_dir, paste0(features, ".tif"))
support_pc_files <- file.path(support_dir, pc_file_labels)
for (i in seq_along(features)) {
  write_fixture_raster(design_raw_files[[i]], 0, 40, 0, 40, i)
  write_fixture_raster(design_pc_files[[i]], 0, 40, 0, 40, i + 10)
  write_fixture_raster(support_raw_files[[i]], -300, 340, -300, 340, i + 20)
  write_fixture_raster(support_pc_files[[i]], -300, 340, -300, 340, i + 30)
}

ref_hash <- paste(rep("a", 64), collapse = "")
ref <- list(
  reference_frozen = TRUE,
  reference_version = "fixture-v1",
  reference_hash = ref_hash,
  parameter_hash = ref_hash,
  feature_order = features
)
reference_file <- file.path(root, "pca_model_reference.json")
write_json(ref, reference_file)

# Certified Workflow 1 lineage is an upstream source for both current-PCA modes.
design_raw_provenance_file <- file.path(legacy_dir, "raw_covariate_provenance.json")
design_raw <- list(
  project_id = cfg$project_id,
  source_identity = list(
    gee_project_id = cfg$gee_project_id,
    roi_field_area_sha256 = pca_support_sha256(roi_file)
  ),
  output_grid = list(crs = "EPSG:32649", computational_grid_m = 10),
  temporal_window = list(
    start_date_inclusive = cfg$legacy_parameters$start_date,
    end_date_exclusive = cfg$legacy_parameters$end_date
  ),
  raw_covariate_sha256 = as.list(pca_support_named_hashes(design_raw_files, features))
)
write_json(design_raw, design_raw_provenance_file)
design_summary_file <- file.path(legacy_dir, "pca_summary.json")
design_summary <- list(
  schema_version = "2.0.0",
  pca_input_lineage_verified = TRUE,
  pca_raster_sha256 = as.list(pca_support_named_hashes(design_pc_files, pc_labels)),
  raw_covariate_sha256 = as.list(pca_support_named_hashes(design_raw_files, features)),
  raw_provenance_sha256 = pca_support_sha256(design_raw_provenance_file),
  reference_hash = ref_hash,
  reference_file_sha256 = pca_support_sha256(reference_file)
)
write_json(design_summary, design_summary_file)
workflow1 <- pca_support_validate_workflow1(
  design_summary_file, design_pc_files, design_raw_files,
  design_raw_provenance_file, features, ref, reference_file, cfg, roi_file
)
stopifnot(isTRUE(workflow1$valid))

support_download_file <- file.path(support_dir, "gee_support_download_summary.json")
support_grid <- pca_support_file_grid(support_raw_files[[1]])
support_download <- list(
  schema_version = "2.0.0",
  provenance_type = "gee_covariate_support_download",
  status = "complete",
  project_id = cfg$project_id,
  source_identity = list(
    gee_project_id = cfg$gee_project_id,
    start_date = cfg$legacy_parameters$start_date,
    end_date = cfg$legacy_parameters$end_date,
    roi_field_area_sha256 = pca_support_sha256(roi_file),
    support_buffer_sha256 = pca_support_sha256(buffer_file),
    support_geometry_policy = cfg$support_policy$support_geometry_policy,
    support_geometry_provenance_sha256 = pca_support_sha256(support_geometry_privacy_file),
    legacy_grid_template_sha256 = pca_support_sha256(legacy_template)
  ),
  output_grid = support_grid,
  privacy_gate = list(
    status = "verified_before_gee_initialization",
    support_geometry_policy = cfg$support_policy$support_geometry_policy,
    geometry_source = "reviewed_roi_bounding_envelope_plus_fixed_metric_buffer",
    geometry_derivation = "sf_projected_bbox_then_st_buffer_nQuadSegs_30",
    coverage_guarantee = "contains_the_fixed_metric_buffer_of_the_reviewed_roi",
    support_buffer_m = cfg$support_policy$covariate_support_buffer_m,
    geometry_certified_by_preflight_hash_chain = TRUE,
    attribute_schema_exact_and_privacy_minimal = TRUE,
    roi_hash_matches_current_file = TRUE,
    support_hash_matches_current_file = TRUE,
    sample_coordinates_or_identifiers_sent = FALSE,
    forbidden_sample_fields_present = list(),
    preflight_geometry_provenance_sha256 = pca_support_sha256(support_geometry_privacy_file)
  ),
  bands = features,
  support_windows = 1L,
  completed_windows = 1L,
  max_tile_side_pixels = 1024L,
  max_window_pixel_count = 36L,
  raw_covariate_sha256 = as.list(pca_support_named_hashes(support_raw_files, features))
)
write_json(support_download, support_download_file)
download_check <- pca_support_validate_download(
  support_download_file, support_raw_files, features, cfg, roi_file,
  buffer_file, legacy_template
)
stopifnot(isTRUE(download_check$valid))
support_download_tampered <- support_download
support_download_tampered$privacy_gate$coverage_guarantee <- "tampered"
write_json(support_download_tampered, support_download_file)
stopifnot(!pca_support_validate_download(
  support_download_file, support_raw_files, features, cfg, roi_file,
  buffer_file, legacy_template
)$valid)
write_json(support_download, support_download_file)

points <- data.frame(code = c("A", "B"), lat = c(13.1, 13.2), lon = c(109.1, 109.2))
support_current_file <- file.path(support_dir, "pca_current_provenance.json")
support_pc_grid <- pca_support_file_grid(support_pc_files[[1]])
support_current <- list(
  schema_version = "2.0.0",
  provenance_type = "interpolation_pca_lineage",
  provenance_mode = "support_rebuild_from_verified_gee_covariates",
  project_id = cfg$project_id,
  verification_status = "verified_full_hash_chain",
  pca_reference_hash = ref_hash,
  reference_frozen = TRUE,
  reference_version = ref$reference_version,
  reference_file_sha256 = pca_support_sha256(reference_file),
  sample_coordinate_sha256 = pca_support_coordinate_sha256(points),
  source_workflow1_pca_summary_sha256 = workflow1$design_summary_sha256,
  source_workflow1_raw_provenance_sha256 = workflow1$design_raw_provenance_sha256,
  source_workflow1_pc_sha256 = workflow1$design_pc_sha256,
  source_workflow1_raw_covariate_sha256 = workflow1$design_raw_sha256,
  source_workflow1_identity_sha256 = workflow1$source_identity_sha256,
  source_workflow1_grid_sha256 = workflow1$output_grid_sha256,
  raw_covariate_sha256 = download_check$raw_covariate_sha256,
  support_download_provenance_sha256 = download_check$sidecar_sha256,
  support_geometry_provenance_sha256 = download_check$support_geometry_provenance_sha256,
  support_source_identity_sha256 = download_check$source_identity_sha256,
  support_output_grid_sha256 = download_check$output_grid_sha256,
  roi_field_area_sha256 = pca_support_sha256(roi_file),
  support_buffer_sha256 = pca_support_sha256(buffer_file),
  support_geometry_policy = cfg$support_policy$support_geometry_policy,
  support_privacy_gate_status = "verified_before_gee_initialization",
  download_geometry_is_not_prediction_domain = TRUE,
  analytical_support_mask_policy = "workflow1_pc_mask_plus_actual_sample_cells_local_only",
  actual_sample_geometry_sent_to_gee = FALSE,
  legacy_grid_template_sha256 = pca_support_sha256(legacy_template),
  gee_project_id = cfg$gee_project_id,
  start_date = cfg$legacy_parameters$start_date,
  end_date = cfg$legacy_parameters$end_date,
  crs = support_download$output_grid$crs,
  computational_grid_m = cfg$resolution_m,
  pca_output_grid = support_pc_grid,
  pca_output_grid_sha256 = pca_support_json_sha256(support_pc_grid),
  pc_file_sha256 = as.list(pca_support_named_hashes(support_pc_files, pc_file_labels))
)
write_json(support_current, support_current_file)
support_check <- pca_support_validate_current(
  support_current_file, support_pc_files, points, ref, reference_file, cfg,
  roi_file, buffer_file, support_raw_files, support_download_file,
  legacy_template, design_summary_file, design_pc_files, design_raw_files,
  design_raw_provenance_file, features
)
if (!isTRUE(support_check$valid)) stop(paste(support_check$reasons, collapse = "; "))
support_with_extra <- support_current
support_with_extra$pc_file_sha256$PC6.tif <- paste(rep("b", 64), collapse = "")
write_json(support_with_extra, support_current_file)
stopifnot(!pca_support_validate_current(
  support_current_file, support_pc_files, points, ref, reference_file, cfg,
  roi_file, buffer_file, support_raw_files, support_download_file,
  legacy_template, design_summary_file, design_pc_files, design_raw_files,
  design_raw_provenance_file, features
)$valid)
write_json(support_current, support_current_file)
changed_points <- points
changed_points$lon[[2]] <- changed_points$lon[[2]] + 0.001
stopifnot(!pca_support_validate_current(
  support_current_file, support_pc_files, changed_points, ref, reference_file, cfg,
  roi_file, buffer_file, support_raw_files, support_download_file,
  legacy_template, design_summary_file, design_pc_files, design_raw_files,
  design_raw_provenance_file, features
)$valid)

# Build a complete Workflow 1 lineage and prove the no-support exact-copy mode.
design_raw_provenance_file <- file.path(legacy_dir, "raw_covariate_provenance.json")
design_raw <- list(
  project_id = cfg$project_id,
  source_identity = list(
    gee_project_id = cfg$gee_project_id,
    roi_field_area_sha256 = pca_support_sha256(roi_file)
  ),
  output_grid = list(crs = "EPSG:32649", computational_grid_m = 10),
  temporal_window = list(
    start_date_inclusive = cfg$legacy_parameters$start_date,
    end_date_exclusive = cfg$legacy_parameters$end_date
  ),
  raw_covariate_sha256 = as.list(pca_support_named_hashes(design_raw_files, features))
)
write_json(design_raw, design_raw_provenance_file)
design_summary_file <- file.path(legacy_dir, "pca_summary.json")
design_summary <- list(
  schema_version = "2.0.0",
  pca_input_lineage_verified = TRUE,
  pca_raster_sha256 = as.list(pca_support_named_hashes(design_pc_files, pc_labels)),
  raw_covariate_sha256 = as.list(pca_support_named_hashes(design_raw_files, features)),
  raw_provenance_sha256 = pca_support_sha256(design_raw_provenance_file),
  reference_hash = ref_hash,
  reference_file_sha256 = pca_support_sha256(reference_file)
)
write_json(design_summary, design_summary_file)
workflow1 <- pca_support_validate_workflow1(
  design_summary_file, design_pc_files, design_raw_files,
  design_raw_provenance_file, features, ref, reference_file, cfg, roi_file
)
stopifnot(isTRUE(workflow1$valid))

# Prove the local, no-transfer rebuild mode and all of its fail-closed links.
local_pc_files <- file.path(local_dir, pc_file_labels)
stopifnot(all(file.copy(design_pc_files, local_pc_files, overwrite = TRUE)))
local_sidecar_file <- file.path(local_dir, "pca_current_provenance.json")
local_grid <- pca_support_file_grid(local_pc_files[[1]])
local_sidecar <- list(
  schema_version = "2.0.0",
  provenance_type = "interpolation_pca_lineage",
  provenance_mode = "local_rebuild_from_verified_workflow1_raw_covariates",
  project_id = cfg$project_id,
  verification_status = "verified_full_hash_chain",
  pca_reference_hash = ref_hash,
  reference_frozen = TRUE,
  reference_version = ref$reference_version,
  reference_file_sha256 = pca_support_sha256(reference_file),
  sample_coordinate_sha256 = pca_support_coordinate_sha256(points),
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
  pca_output_grid = local_grid,
  pca_output_grid_sha256 = pca_support_json_sha256(local_grid),
  pc_file_sha256 = as.list(pca_support_named_hashes(local_pc_files, pc_file_labels))
)
validate_local <- function(sidecar = local_sidecar, sample_points = points) {
  write_json(sidecar, local_sidecar_file)
  pca_support_validate_current(
    local_sidecar_file, local_pc_files, sample_points, ref, reference_file, cfg,
    roi_file, "unused-buffer", "unused-raw", "unused-download",
    legacy_template, design_summary_file, design_pc_files, design_raw_files,
    design_raw_provenance_file, features
  )
}
local_check <- validate_local()
if (!isTRUE(local_check$valid)) stop(paste(local_check$reasons, collapse = "; "))

# A changed actual coordinate must invalidate the local analytical-mask chain.
stopifnot(!validate_local(local_sidecar, changed_points)$valid)

# Privacy/no-transfer flags are mandatory, not descriptive-only metadata.
local_flag_tamper <- local_sidecar
local_flag_tamper$actual_sample_geometry_sent_to_gee <- TRUE
stopifnot(!validate_local(local_flag_tamper)$valid)
local_flag_tamper <- local_sidecar
local_flag_tamper$external_data_transfer_for_pca_refresh <- TRUE
stopifnot(!validate_local(local_flag_tamper)$valid)

# A byte change to an output PC must invalidate its exact hash chain.
local_pc_bytes <- readBin(
  local_pc_files[[1]], what = "raw", n = file.info(local_pc_files[[1]])$size
)
writeBin(c(local_pc_bytes, charToRaw("x")), local_pc_files[[1]])
stopifnot(!validate_local(local_sidecar)$valid)
writeBin(local_pc_bytes, local_pc_files[[1]])
stopifnot(isTRUE(validate_local(local_sidecar)$valid))

# A byte change to certified Workflow 1 raw data must invalidate local lineage.
design_raw_bytes <- readBin(
  design_raw_files[[1]], what = "raw", n = file.info(design_raw_files[[1]])$size
)
writeBin(c(design_raw_bytes, charToRaw("x")), design_raw_files[[1]])
stopifnot(!validate_local(local_sidecar)$valid)
writeBin(design_raw_bytes, design_raw_files[[1]])
stopifnot(isTRUE(validate_local(local_sidecar)$valid))

copy_pc_files <- file.path(copy_dir, pc_file_labels)
stopifnot(all(file.copy(design_pc_files, copy_pc_files, overwrite = TRUE)))
copy_sidecar_file <- file.path(copy_dir, "pca_current_provenance.json")
copy_grid <- pca_support_file_grid(copy_pc_files[[1]])
copy_sidecar <- list(
  schema_version = "2.0.0",
  provenance_type = "interpolation_pca_lineage",
  provenance_mode = "verified_workflow1_copy",
  project_id = cfg$project_id,
  verification_status = "verified_full_hash_chain",
  pca_reference_hash = ref_hash,
  reference_frozen = TRUE,
  reference_version = ref$reference_version,
  reference_file_sha256 = pca_support_sha256(reference_file),
  sample_coordinate_sha256 = pca_support_coordinate_sha256(points),
  source_workflow1_pca_summary_sha256 = workflow1$design_summary_sha256,
  source_workflow1_raw_provenance_sha256 = workflow1$design_raw_provenance_sha256,
  source_workflow1_pc_sha256 = workflow1$design_pc_sha256,
  source_workflow1_raw_covariate_sha256 = workflow1$design_raw_sha256,
  source_workflow1_identity_sha256 = workflow1$source_identity_sha256,
  source_workflow1_grid_sha256 = workflow1$output_grid_sha256,
  pca_output_grid = copy_grid,
  pca_output_grid_sha256 = pca_support_json_sha256(copy_grid),
  pc_file_sha256 = as.list(pca_support_named_hashes(copy_pc_files, pc_file_labels))
)
write_json(copy_sidecar, copy_sidecar_file)
copy_check <- pca_support_validate_current(
  copy_sidecar_file, copy_pc_files, points, ref, reference_file, cfg,
  roi_file, "unused-buffer", "unused-raw", "unused-download",
  legacy_template, design_summary_file, design_pc_files, design_raw_files,
  design_raw_provenance_file, features
)
stopifnot(isTRUE(copy_check$valid))

# A byte change to the upstream summary must invalidate the exact-copy chain.
summary_bytes <- readBin(design_summary_file, what = "raw", n = file.info(design_summary_file)$size)
writeBin(c(summary_bytes, charToRaw(" ")), design_summary_file)
stopifnot(!pca_support_validate_current(
  copy_sidecar_file, copy_pc_files, points, ref, reference_file, cfg,
  roi_file, "unused-buffer", "unused-raw", "unused-download",
  legacy_template, design_summary_file, design_pc_files, design_raw_files,
  design_raw_provenance_file, features
)$valid)

# Complete raw rasters with a mutated byte-level raster must fail download lineage.
write_fixture_raster(support_raw_files[[3]], -10, 50, -10, 50, 999)
stopifnot(!pca_support_validate_download(
  support_download_file, support_raw_files, features, cfg, roi_file,
  buffer_file, legacy_template
)$valid)

cat("PCA support provenance v2 regression passed.\n")
