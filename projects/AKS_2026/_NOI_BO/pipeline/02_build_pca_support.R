suppressPackageStartupMessages({
  library(sf)
  library(terra)
  library(yaml)
  library(jsonlite)
  library(readr)
})

cfg <- yaml::read_yaml("projects/AKS_2026/_NOI_BO/config/project.yml")
pca_ref <- jsonlite::read_json(
  "projects/AKS_2026/_NOI_BO/config/pca_model_reference.json",
  simplifyVector = TRUE
)

pca_reference_hash <- as.character(pca_ref$reference_hash)
pca_reference_frozen <- isTRUE(pca_ref$reference_frozen)
pca_reference_version <- as.character(pca_ref$reference_version)
if (length(pca_reference_hash) != 1L || !grepl("^[0-9a-f]{64}$", pca_reference_hash)) {
  stop("Frozen PCA reference lacks a valid SHA-256 reference_hash.")
}
if (!pca_reference_frozen) stop("PCA support rebuild requires reference_frozen=true.")
if (length(pca_reference_version) != 1L || is.na(pca_reference_version) || !nzchar(pca_reference_version)) {
  stop("Frozen PCA reference lacks reference_version.")
}
if (!requireNamespace("digest", quietly = TRUE)) stop("Package 'digest' is required for PCA provenance hashes.")

source_dir <- cfg$runtime$expanded_covariate_dir
aligned_dir <- cfg$runtime$aligned_covariate_dir
output_dir <- cfg$runtime$pca_support_dir
qa_dir <- cfg$runtime$qa_dir
dir.create(aligned_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(qa_dir, recursive = TRUE, showWarnings = FALSE)

feature_order <- as.character(pca_ref$feature_order)
source_files <- file.path(source_dir, paste0(feature_order, ".tif"))
missing <- source_files[!file.exists(source_files)]
if (length(missing) > 0) {
  stop(
    "Expanded covariates are not ready. Missing: ",
    paste(basename(missing), collapse = ", "),
    ". Re-fetch them with the legacy date range and EPSG:32649, covering the original ROI plus support buffers."
  )
}

legacy_pc_files <- file.path(cfg$source$legacy_pca_dir, paste0("PC", seq_len(5), ".tif"))
if (any(!file.exists(legacy_pc_files))) stop("Legacy PC rasters are incomplete.")
template <- rast(legacy_pc_files[[1]])

align_one <- function(path, method = "bilinear") {
  x <- rast(path)[[1]]
  same_crs <- terra::same.crs(x, template)
  same_geom <- isTRUE(terra::compareGeom(x, template, stopOnError = FALSE))
  if (same_geom) return(x)
  if (same_crs) return(terra::resample(x, template, method = method))
  terra::project(x, template, method = method)
}

aligned <- vector("list", length(feature_order))
for (i in seq_along(feature_order)) {
  aligned[[i]] <- align_one(source_files[[i]], "bilinear")
  names(aligned[[i]]) <- feature_order[[i]]
  writeRaster(
    aligned[[i]], file.path(aligned_dir, paste0(feature_order[[i]], ".tif")),
    overwrite = TRUE, datatype = "FLT4S", gdal = c("COMPRESS=LZW")
  )
}
covs <- rast(aligned)
names(covs) <- feature_order

# Preserve the original valid PC mask and add only the verified 300 m support
# buffers around outside samples. This keeps the prediction population tied to
# the original sugarcane ROI while allowing extraction at every field sample.
legacy_mask <- ifel(!is.na(template), 1, NA)
buffers_path <- cfg$runtime$support_buffers_gpkg
if (!file.exists(buffers_path)) {
  stop("Support buffers are missing. Run 01_preflight_samples.R first.")
}
buffers <- terra::vect(buffers_path)
buffer_mask <- terra::rasterize(buffers, template, field = 1, background = NA, touches = TRUE)
support_mask <- terra::cover(legacy_mask, buffer_mask)

means <- as.numeric(pca_ref$scaler_mean)
scales <- as.numeric(pca_ref$scaler_scale)
components <- as.matrix(pca_ref$pca_components)
if (length(means) != nlyr(covs) || ncol(components) != nlyr(covs)) {
  stop("PCA reference dimensions do not match expanded covariates.")
}

z <- vector("list", nlyr(covs))
for (i in seq_len(nlyr(covs))) z[[i]] <- (covs[[i]] - means[[i]]) / scales[[i]]

for (j in seq_len(nrow(components))) {
  computed_pc <- z[[1]] * components[j, 1]
  if (nlyr(covs) > 1) {
    for (i in 2:nlyr(covs)) computed_pc <- computed_pc + z[[i]] * components[j, i]
  }
  computed_pc <- terra::mask(computed_pc, support_mask)
  legacy_pc <- rast(legacy_pc_files[[j]])[[1]]
  hybrid_pc <- terra::cover(legacy_pc, computed_pc)
  hybrid_pc <- terra::mask(hybrid_pc, support_mask)
  names(hybrid_pc) <- paste0("PC", j)
  writeRaster(
    hybrid_pc, file.path(output_dir, paste0("PC", j, ".tif")),
    overwrite = TRUE, datatype = "FLT4S", gdal = c("COMPRESS=LZW")
  )
}

pc_output_files <- file.path(output_dir, paste0("PC", 1:5, ".tif"))
pc_output_hashes <- setNames(
  vapply(pc_output_files, digest::digest, character(1), file = TRUE, algo = "sha256"),
  basename(pc_output_files)
)
pca_provenance <- list(
  project_id = cfg$project_id,
  pca_reference_hash = pca_reference_hash,
  reference_frozen = pca_reference_frozen,
  reference_version = pca_reference_version,
  verification_status = "generated_by_frozen_reference_support_rebuild",
  generated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  pc_file_sha256 = as.list(pc_output_hashes)
)
jsonlite::write_json(
  pca_provenance, file.path(qa_dir, "pca_current_provenance.json"),
  pretty = TRUE, auto_unbox = TRUE
)
# Soil class is retained as an audit/stratification layer; the current RK engine
# continues to use PC1-PC5 as predictors unless explicitly extended later.
soil_source <- file.path(source_dir, "Soil_Class.tif")
if (file.exists(soil_source)) {
  soil <- align_one(soil_source, "near")
  soil <- terra::mask(soil, support_mask)
  writeRaster(
    soil, file.path(aligned_dir, "Soil_Class_support.tif"),
    overwrite = TRUE, datatype = "INT2S", gdal = c("COMPRESS=LZW")
  )
}

points_file <- cfg$runtime$standardized_points_csv
if (!file.exists(points_file)) stop("Standardized points are missing. Run preflight first.")
points <- as.data.frame(readr::read_csv(points_file, show_col_types = FALSE, progress = FALSE))
pts <- terra::vect(points, geom = c("lon", "lat"), crs = "EPSG:4326")
pts <- terra::project(pts, paste0("EPSG:", cfg$crs_epsg))
pc_stack <- rast(file.path(output_dir, paste0("PC", 1:5, ".tif")))
pc_values <- terra::extract(pc_stack, pts)[, -1, drop = FALSE]
complete <- stats::complete.cases(pc_values)
coverage <- data.frame(code = points$code, complete_pca_support = complete, pc_values)
coverage_path <- file.path(qa_dir, "pca_support_point_coverage.csv")
readr::write_csv(coverage, coverage_path, na = "")

summary <- list(
  project_id = cfg$project_id,
  feature_order = feature_order,
  pca_policy = cfg$support_policy$pca_policy,
  pca_reference_hash = pca_reference_hash,
  reference_frozen = pca_reference_frozen,
  reference_version = pca_reference_version,
  provenance_sidecar = normalizePath(file.path(qa_dir, "pca_current_provenance.json"), winslash = "/", mustWork = FALSE),
  legacy_pc_priority = cfg$support_policy$legacy_pc_priority_inside_existing_mask,
  n_points = nrow(points),
  n_points_with_complete_pc = sum(complete),
  n_points_missing_pc = sum(!complete),
  output_dir = normalizePath(output_dir, winslash = "/", mustWork = FALSE),
  coverage_csv = normalizePath(coverage_path, winslash = "/", mustWork = FALSE)
)
jsonlite::write_json(
  summary, file.path(qa_dir, "pca_support_summary.json"),
  pretty = TRUE, auto_unbox = TRUE
)
if (any(!complete)) {
  stop("PCA support remains missing for ", sum(!complete), " sample(s). See ", coverage_path)
}
cat("PCA support build complete: all ", nrow(points), " samples covered.\n", sep = "")
