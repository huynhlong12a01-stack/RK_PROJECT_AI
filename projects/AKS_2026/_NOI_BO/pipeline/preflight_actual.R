suppressPackageStartupMessages({
  library(sf)
  library(terra)
  library(readr)
  library(jsonlite)
  library(yaml)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
base <- "projects/AKS_2026"
internal <- file.path(base, "_NOI_BO")
source(file.path(internal, "pipeline/actual_qa_utils.R"))

sample_file <- file.path(base, "02_NOI_SUY_BAN_DO/01_DAU_VAO/sample_actual.csv")
roi_file <- file.path(base, "00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson")
clhs_file <- file.path(base, "01_THIET_KE_LAY_MAU/02_KET_QUA/sample_cLHS_FULL.csv")
soil_file <- file.path(base, "01_THIET_KE_LAY_MAU/01_DAU_VAO/soil_type.geojson")
sampling_file <- file.path(base, "01_THIET_KE_LAY_MAU/01_DAU_VAO/sampling.yml")
design_dir <- file.path(internal, "work/design")
work_dir <- file.path(internal, "work/interpolation")
output_file <- file.path(work_dir, "sample_actual_clean.csv")
qa_dir <- file.path(work_dir, "qa")

cfg <- yaml::read_yaml(file.path(internal, "config/project.yml"))
source(file.path(internal, "pipeline/pca_support_provenance_utils.R"))
epsg <- as.integer(cfg$crs_epsg)
buffer_m <- as.numeric(cfg$support_policy$covariate_support_buffer_m)
support_geometry_policy <- as.character(cfg$support_policy$support_geometry_policy %||% "fixed_roi_buffer_no_sample_geometry")
if (!identical(support_geometry_policy, "fixed_roi_buffer_no_sample_geometry")) {
  stop("Unsupported support_geometry_policy; sample-derived GEE support geometries are prohibited.")
}
qa_file <- cfg$runtime$sample_qa_csv %||% file.path(qa_dir, "sample_roi_status.csv")
outside_file <- cfg$runtime$outside_points_gpkg %||% file.path(work_dir, "outside_samples.gpkg")
buffers_file <- cfg$runtime$support_buffers_gpkg %||% file.path(work_dir, "covariate_support_buffers.gpkg")
assessment_file <- cfg$runtime$actual_assessment_csv %||% file.path(base, "02_NOI_SUY_BAN_DO/01_DAU_VAO/outside_sample_review.csv")
default_relocation_reason <- cfg$outside_sample_review$default_relocation_reason %||% NA_character_
pca_reference_file <- file.path(internal, "config/pca_model_reference.json")
pca_provenance_file <- file.path(qa_dir, "pca_current_provenance.json")
support_download_file <- file.path(qa_dir, "gee_support_download_summary.json")
support_geometry_privacy_file <- file.path(qa_dir, "support_geometry_privacy.json")
design_pca_summary_file <- file.path(design_dir, "qa/pca_summary.json")
design_raw_provenance_file <- file.path(design_dir, "qa/raw_covariate_provenance.json")
legacy_template_file <- file.path(design_dir, "PC1.tif")
pca_ref <- jsonlite::read_json(pca_reference_file, simplifyVector = TRUE)
pca_reference_hash <- as.character(pca_ref$reference_hash)
pca_reference_version <- as.character(pca_ref$reference_version)
pca_reference_frozen <- isTRUE(pca_ref$reference_frozen)
if (length(pca_reference_hash) != 1L || !grepl("^[0-9a-f]{64}$", pca_reference_hash)) {
  stop("Frozen PCA reference lacks a valid SHA-256 reference_hash.")
}
if (!pca_reference_frozen) stop("PCA reference must be frozen before actual-sample preparation.")
if (length(pca_reference_version) != 1L || is.na(pca_reference_version) || !nzchar(pca_reference_version)) {
  stop("Frozen PCA reference lacks reference_version.")
}
if (!requireNamespace("digest", quietly = TRUE)) stop("Package 'digest' is required for PCA provenance checks.")

required <- c(sample_file, roi_file, clhs_file)
missing <- required[!file.exists(required)]
if (length(missing)) stop("Missing input(s): ", paste(missing, collapse = ", "))

raw <- as.data.frame(readr::read_csv(sample_file, show_col_types = FALSE, progress = FALSE))
find_col <- function(candidates) {
  hit <- match(tolower(candidates), tolower(trimws(names(raw))), nomatch = 0L)
  hit <- hit[hit > 0L]
  if (length(hit)) names(raw)[hit[1]] else NA_character_
}
code_col <- find_col(c("code", "sample_code", "sample_id"))
lat_col <- find_col(c("lat", "latitude"))
lon_col <- find_col(c("lon", "longitude", "long"))
if (any(is.na(c(code_col, lat_col, lon_col)))) stop("sample_actual.csv must contain code, lat and lon.")

core <- data.frame(
  code = trimws(as.character(raw[[code_col]])),
  lat = suppressWarnings(as.numeric(raw[[lat_col]])),
  lon = suppressWarnings(as.numeric(raw[[lon_col]])),
  stringsAsFactors = FALSE
)
if (any(!nzchar(core$code)) || any(!is.finite(core$lat)) || any(!is.finite(core$lon))) {
  stop("Missing code or invalid coordinate in sample_actual.csv.")
}
if (anyDuplicated(core$code)) stop("Duplicate sample code detected.")
if (anyDuplicated(paste(round(core$lon, 7), round(core$lat, 7)))) stop("Duplicate sample coordinate detected.")

indicator_cols <- setdiff(names(raw), c(code_col, lat_col, lon_col))
clean <- core
for (nm in indicator_cols) {
  text <- trimws(as.character(raw[[nm]]))
  blank <- is.na(raw[[nm]]) | text == ""
  value <- suppressWarnings(as.numeric(text))
  if (any(!blank & !is.finite(value))) stop("Non-numeric value in indicator column: ", nm)
  clean[[nm]] <- value
}

pts_wgs <- st_as_sf(core, coords = c("lon", "lat"), crs = 4326, remove = FALSE)
pts_utm <- st_transform(pts_wgs, epsg)
roi_info <- file.info(roi_file)
roi_signature <- paste(as.numeric(roi_info$size), as.numeric(roi_info$mtime), sep = ":")
geographic_cache_status <- "not_used"
inside <- NULL
distance_to_roi <- NULL
if (file.exists(qa_file)) {
  prior_qa <- tryCatch(
    as.data.frame(readr::read_csv(qa_file, show_col_types = FALSE, progress = FALSE)),
    error = function(e) NULL
  )
  cache_columns <- c("code", "lat", "lon", "inside_roi", "distance_to_roi_m")
  cache_matches <- !is.null(prior_qa) && all(cache_columns %in% names(prior_qa)) &&
    identical(as.character(prior_qa$code), core$code) &&
    isTRUE(all.equal(as.numeric(prior_qa$lat), core$lat, tolerance = 0)) &&
    isTRUE(all.equal(as.numeric(prior_qa$lon), core$lon, tolerance = 0))
  if (cache_matches) {
    prior_summary_file <- file.path(qa_dir, "preflight_summary.json")
    prior_summary <- if (file.exists(prior_summary_file)) {
      tryCatch(jsonlite::read_json(prior_summary_file, simplifyVector = TRUE), error = function(e) list())
    } else list()
    signature_ok <- is.null(prior_summary$roi_signature) || identical(as.character(prior_summary$roi_signature), roi_signature)
    if (signature_ok) {
      inside <- as.logical(prior_qa$inside_roi)
      distance_to_roi <- as.numeric(prior_qa$distance_to_roi_m)
      geographic_cache_status <- if (is.null(prior_summary$roi_signature)) "legacy_cache_reused_coordinates_match" else "verified_cache_reused"
    }
  }
}
if (is.null(inside)) {
  roi <- st_make_valid(st_transform(st_read(roi_file, quiet = TRUE), epsg))
  inside <- lengths(st_intersects(pts_utm, roi)) > 0
  outside_idx <- which(!inside)
  distance_to_roi <- numeric(nrow(core))
  if (length(outside_idx)) {
    nearest <- st_nearest_feature(pts_utm[outside_idx, ], roi)
    distance_to_roi[outside_idx] <- as.numeric(st_distance(pts_utm[outside_idx, ], roi[nearest, ], by_element = TRUE))
  }
  geographic_cache_status <- "computed_from_roi"
}
outside_idx <- which(!inside)
clhs <- as.data.frame(readr::read_csv(clhs_file, show_col_types = FALSE, progress = FALSE))
if (!"Point_ID" %in% names(clhs)) stop("sample_cLHS_FULL.csv must contain Point_ID.")
if (all(c("X_UTM", "Y_UTM") %in% names(clhs))) {
  clhs_sf <- st_as_sf(clhs, coords = c("X_UTM", "Y_UTM"), crs = epsg, remove = FALSE)
} else if (all(c("Longitude", "Latitude") %in% names(clhs))) {
  clhs_sf <- st_transform(st_as_sf(clhs, coords = c("Longitude", "Latitude"), crs = 4326, remove = FALSE), epsg)
} else stop("sample_cLHS_FULL.csv has no supported coordinate columns.")

invisible(actual_sync_review_file(assessment_file, core$code[outside_idx], default_relocation_reason))
assessment <- actual_read_assessment(assessment_file, core$code)
assessment$target_population_status[inside] <- "inside_original_sampling_frame"
assessment$sampling_support_status[inside] <- "inside_sampling_frame_support"
assessment$include_in_model_development[inside] <- TRUE
assessment_file_status <- attr(assessment, "file_status")
links <- actual_resolve_plan_link(core$code, assessment, as.character(clhs$Point_ID))
planned_distance <- rep(NA_real_, nrow(core))
linked_idx <- which(!is.na(links$planned_point_id))
if (length(linked_idx)) {
  plan_idx <- match(links$planned_point_id[linked_idx], as.character(clhs$Point_ID))
  planned_distance[linked_idx] <- as.numeric(st_distance(pts_utm[linked_idx, ], clhs_sf[plan_idx, ], by_element = TRUE))
}
relocation_reason_status <- ifelse(is.na(assessment$relocation_reason), "unavailable_not_recorded", "recorded")

extract_values <- function(files, points) {
  if (!all(file.exists(files))) return(NULL)
  point_vect <- terra::vect(points)
  values <- lapply(files, function(path) {
    terra::extract(rast(path)[[1]], point_vect)[, 2]
  })
  as.data.frame(values, stringsAsFactors = FALSE)
}
continuous_names <- c("CHIRPS", "DEM", "NDVI", "Slope", "TWI")
cov_values <- extract_values(file.path(design_dir, paste0(continuous_names, ".tif")), pts_utm)
if (is.null(cov_values)) {
  cov_valid_count <- rep(0L, nrow(core))
  missing_covariates <- rep(paste(continuous_names, collapse = ";"), nrow(core))
} else {
  names(cov_values) <- continuous_names
  cov_valid <- !is.na(cov_values)
  cov_valid_count <- rowSums(cov_valid)
  missing_covariates <- apply(cov_valid, 1, function(x) paste(continuous_names[!x], collapse = ";"))
}
cov_complete <- cov_valid_count == length(continuous_names)
current_cov_values <- extract_values(file.path(work_dir, paste0(continuous_names, ".tif")), pts_utm)
if (is.null(current_cov_values)) {
  current_cov_valid_count <- rep(0L, nrow(core))
  missing_current_covariates <- rep(paste(continuous_names, collapse = ";"), nrow(core))
} else {
  names(current_cov_values) <- continuous_names
  current_cov_valid <- !is.na(current_cov_values)
  current_cov_valid_count <- rowSums(current_cov_valid)
  missing_current_covariates <- apply(current_cov_valid, 1, function(x) paste(continuous_names[!x], collapse = ";"))
}
current_cov_complete <- current_cov_valid_count == length(continuous_names)

pc_values <- extract_values(file.path(design_dir, paste0("PC", 1:5, ".tif")), pts_utm)
pc_valid_count <- if (is.null(pc_values)) rep(0L, nrow(core)) else rowSums(!is.na(pc_values))
pc_complete <- pc_valid_count == 5L
actual_pc_files <- file.path(work_dir, paste0("PC", 1:5, ".tif"))
actual_pc_values <- extract_values(actual_pc_files, pts_utm)
actual_pc_valid_count <- if (is.null(actual_pc_values)) rep(0L, nrow(core)) else rowSums(!is.na(actual_pc_values))
actual_pc_complete <- actual_pc_valid_count == 5L
support_raw_files <- file.path(work_dir, paste0(continuous_names, ".tif"))
design_pc_files <- file.path(design_dir, paste0("PC", 1:5, ".tif"))
design_raw_files <- file.path(design_dir, paste0(continuous_names, ".tif"))
support_download_check <- tryCatch(
  pca_support_validate_download(
    support_download_file, support_raw_files, continuous_names, cfg, roi_file,
    buffers_file, legacy_template_file
  ),
  error = function(e) list(valid = FALSE, reasons = conditionMessage(e))
)
support_download_provenance_valid <- isTRUE(support_download_check$valid)
support_download_provenance_status <- if (support_download_provenance_valid) {
  "verified"
} else if (!file.exists(support_download_file)) {
  "missing"
} else {
  "mismatch_or_invalid"
}

provenance_check <- tryCatch(
  pca_support_validate_current(
    pca_provenance_file, actual_pc_files, core, pca_ref, pca_reference_file,
    cfg, roi_file, buffers_file, support_raw_files, support_download_file,
    legacy_template_file, design_pca_summary_file, design_pc_files,
    design_raw_files, design_raw_provenance_file, continuous_names
  ),
  error = function(e) list(valid = FALSE, reasons = conditionMessage(e), mode = "invalid")
)
pca_provenance_valid <- isTRUE(provenance_check$valid) && all(file.exists(actual_pc_files))
pca_provenance_mode <- as.character(provenance_check$mode %||% "missing")
pca_provenance_status <- if (pca_provenance_valid) {
  paste0("verified:", pca_provenance_mode)
} else if (!file.exists(pca_provenance_file)) {
  "missing"
} else {
  "mismatch_or_invalid"
}
pca_provenance_reasons <- as.character(provenance_check$reasons %||% character())
current_actual_pca_trusted <- actual_pc_complete & pca_provenance_valid
requires_pca_refresh <- !current_actual_pca_trusted
workflow1_grid_support_gap <- !pc_complete
requires_local_workflow1_raw_pca_rebuild <-
  requires_pca_refresh & workflow1_grid_support_gap & cov_complete
requires_external_covariate_support <-
  requires_pca_refresh & workflow1_grid_support_gap & !cov_complete
requires_covariate_support_for_execution <- requires_external_covariate_support
requires_pca_support_rebuild <- requires_external_covariate_support
requires_gee_download <- requires_external_covariate_support &
  (!current_cov_complete | !support_download_provenance_valid)
external_beyond_fixed_support <- requires_external_covariate_support &
  distance_to_roi > buffer_m
if (any(external_beyond_fixed_support)) {
  stop(
    "Actual sample support exceeds covariate_support_buffer_m for ",
    sum(external_beyond_fixed_support),
    " sample(s); maximum ROI distance is ",
    round(max(distance_to_roi[external_beyond_fixed_support]), 1),
    " m. Review target scope, then increase covariate_support_buffer_m only in THONG_SO_DU_AN.yml before any GEE request."
  )
}
covariate_support_status <- ifelse(
  current_actual_pca_trusted, "ready_current_pca_verified",
  ifelse(pc_complete, "covered_workflow1_pca",
    ifelse(cov_complete, "verified_workflow1_raw_ready_for_local_pca_rebuild",
      ifelse(actual_pc_complete, "current_pca_available_unverified_requires_refresh", "missing_requires_external_support_extension")))
)
soil_source_class <- rep(NA_character_, nrow(core))
soil_model_group <- rep(NA_character_, nrow(core))
soil_other_reason <- rep("soil_type_not_configured", nrow(core))
soil_assessment_status <- rep("not_configured", nrow(core))
if (file.exists(soil_file)) {
  sampling_cfg <- if (file.exists(sampling_file)) yaml::read_yaml(sampling_file) else list()
  soil_field <- sampling_cfg$soil_group_field %||% "Ma1"
  soil <- st_make_valid(st_read(soil_file, quiet = TRUE))
  if (!soil_field %in% names(soil)) stop("Soil Type file lacks field: ", soil_field)
  soil <- st_transform(soil[, soil_field, drop = FALSE], epsg)
  hit <- st_within(pts_utm, soil)
  if (any(lengths(hit) > 1L)) stop("Soil polygons overlap at one or more sample locations.")
  hit_idx <- vapply(hit, function(x) if (length(x)) x[[1]] else NA_integer_, integer(1))
  present <- !is.na(hit_idx)
  soil_source_class[present] <- trimws(as.character(soil[[soil_field]][hit_idx[present]]))
  soil_source_class[is.na(soil_source_class) | soil_source_class == ""] <- "Unmapped"
  counts <- sort(table(soil_source_class[soil_source_class != "Unmapped"]), decreasing = TRUE)
  retained <- names(counts[counts >= 5L])
  soil_model_group <- ifelse(
    soil_source_class == "Unmapped", "Unmapped",
    ifelse(soil_source_class %in% retained, soil_source_class, "Other")
  )
  soil_other_reason <- ifelse(
    soil_source_class == "Unmapped", "outside_or_unclassified_soil_polygon",
    ifelse(soil_model_group == "Other", "rare_mapped_class_collapsed", "not_other")
  )
  soil_assessment_status <- ifelse(
    soil_model_group == "Unmapped", "unmapped",
    ifelse(soil_model_group == "Other", "other", "known_model_group")
  )
}
soil_other <- soil_model_group == "Other"
soil_unmapped <- soil_model_group == "Unmapped"

target_status <- assessment$target_population_status
sampling_support_status <- assessment$sampling_support_status
manual_status <- ifelse(
  inside,
  "not_required_inside_sampling_frame",
  ifelse(
    grepl("^confirmed_", target_status) & grepl("^confirmed_", sampling_support_status) &
      !is.na(assessment$include_in_model_development),
    "confirmed", "pending_manual_confirmation"
  )
)
analysis_role <- ifelse(
  !is.na(assessment$include_in_model_development) & !assessment$include_in_model_development,
  "exclude_by_manual_review",
  ifelse(
    target_status == "confirmed_out_of_scope" | sampling_support_status == "confirmed_incompatible",
    "exclude_by_manual_assessment",
    ifelse(inside, "model_development_inside_sampling_frame",
      ifelse(manual_status == "confirmed", "model_development_confirmed", "model_development_pending_review"))
  )
)

qa <- data.frame(
  core,
  geographic_status = ifelse(inside, "inside_roi", "outside_roi"),
  inside_roi = inside,
  distance_to_roi_m = round(distance_to_roi, 3),
  workflow1_covariate_valid_count = cov_valid_count,
  workflow1_covariate_complete = cov_complete,
  missing_workflow1_covariates = missing_covariates,
  current_support_covariate_valid_count = current_cov_valid_count,
  current_support_covariate_complete = current_cov_complete,
  missing_current_support_covariates = missing_current_covariates,
  workflow1_pc_valid_count = pc_valid_count,
  workflow1_pca_complete = pc_complete,
  current_actual_pc_valid_count = actual_pc_valid_count,
  current_actual_pca_complete = actual_pc_complete,
  current_pca_provenance_status = pca_provenance_status,
  current_pca_provenance_mode = pca_provenance_mode,
  support_download_provenance_status = support_download_provenance_status,
  current_actual_pca_trusted = current_actual_pca_trusted,
  requires_pca_refresh = requires_pca_refresh,
  covariate_support_status = covariate_support_status,
  workflow1_grid_support_gap = workflow1_grid_support_gap,
  requires_covariate_support_for_execution = requires_covariate_support_for_execution,
  requires_local_workflow1_raw_pca_rebuild = requires_local_workflow1_raw_pca_rebuild,
  requires_external_covariate_support = requires_external_covariate_support,
  requires_pca_support_rebuild = requires_pca_support_rebuild,
  requires_gee_download = requires_gee_download,
  requires_covariate_support = requires_covariate_support_for_execution,
  soil_source_class = soil_source_class,
  soil_model_group = soil_model_group,
  soil_other = soil_other,
  soil_unmapped = soil_unmapped,
  soil_other_reason = soil_other_reason,
  soil_assessment_status = soil_assessment_status,
  planned_link_status = links$planned_link_status,
  planned_point_id = links$planned_point_id,
  planned_to_actual_distance_m = round(planned_distance, 3),
  relocation_reason_status = relocation_reason_status,
  relocation_reason = assessment$relocation_reason,
  target_population_status = target_status,
  sampling_support_status = sampling_support_status,
  manual_assessment_status = manual_status,
  include_in_model_development = assessment$include_in_model_development,
  reviewer = assessment$reviewer,
  review_date = assessment$review_date,
  assessment_note = assessment$assessment_note,
  analysis_role = analysis_role,
  aoa_assessment_status = "pending_model_fit_model_dependent",
  stringsAsFactors = FALSE
)

dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
dir.create(qa_dir, recursive = TRUE, showWarnings = FALSE)
readr::write_csv(clean, output_file, na = "")
readr::write_csv(qa, qa_file, na = "")

if (file.exists(outside_file)) unlink(outside_file)
if (length(outside_idx)) {
  outside <- pts_utm[outside_idx, ]
  outside$distance_to_roi_m <- round(distance_to_roi[outside_idx], 3)
  outside$covariate_support_status <- covariate_support_status[outside_idx]
  outside$target_population_status <- target_status[outside_idx]
  outside$sampling_support_status <- sampling_support_status[outside_idx]
  st_write(outside, outside_file, layer = "outside_roi_samples", quiet = TRUE)
}

support_idx <- which(requires_pca_support_rebuild)
preserve_verified_support_buffer <- pca_provenance_valid &&
  identical(pca_provenance_mode, "support_rebuild_from_verified_gee_covariates")
reuse_certified_support_geometry <- length(support_idx) > 0L &&
  support_download_provenance_valid &&
  file.exists(buffers_file) && file.exists(support_geometry_privacy_file)
if (length(support_idx)) {
  if (!reuse_certified_support_geometry) {
  if (file.exists(buffers_file)) unlink(buffers_file)
  if (file.exists(support_geometry_privacy_file)) unlink(support_geometry_privacy_file)
  # Privacy-preserving compact support: a fixed metric buffer around the
  # bounding envelope of the reviewed ROI. Because ROI is contained by its
  # envelope, this also contains every location within buffer_m of the ROI.
  # No actual sample point, code, latitude or longitude defines this geometry.
  support_roi <- st_make_valid(st_transform(st_read(roi_file, quiet = TRUE), epsg))
  support_envelope <- st_as_sfc(st_bbox(support_roi))
  support_geometry <- st_sf(
    support_geometry_policy = support_geometry_policy,
    support_buffer_m = buffer_m,
    contains_sample_attributes = FALSE,
    geometry = st_buffer(support_envelope, dist = buffer_m, nQuadSegs = 30)
  )
  st_write(
    support_geometry, buffers_file,
    layer = "roi_fixed_covariate_support", quiet = TRUE
  )
  support_privacy <- list(
    schema_version = "1.0.0",
    provenance_type = "privacy_preserving_support_geometry",
    status = "certified_by_preflight",
    project_id = as.character(cfg$project_id),
    support_geometry_policy = support_geometry_policy,
    geometry_source = "reviewed_roi_bounding_envelope_plus_fixed_metric_buffer",
    geometry_derivation = "sf_projected_bbox_then_st_buffer_nQuadSegs_30",
    coverage_guarantee = "contains_the_fixed_metric_buffer_of_the_reviewed_roi",
    project_crs = paste0("EPSG:", epsg),
    support_buffer_m = buffer_m,
    feature_count = nrow(support_geometry),
    attribute_schema = c(
      "support_geometry_policy", "support_buffer_m", "contains_sample_attributes"
    ),
    contains_sample_attributes = FALSE,
    sample_coordinates_or_identifiers_used_to_define_geometry = FALSE,
    sample_coordinates_or_identifiers_in_attributes = FALSE,
    roi_field_area_sha256 = digest::digest(
      file = roi_file, algo = "sha256", serialize = FALSE
    ),
    support_geometry_file_sha256 = digest::digest(
      file = buffers_file, algo = "sha256", serialize = FALSE
    )
  )
  privacy_tmp <- paste0(support_geometry_privacy_file, ".tmp")
  jsonlite::write_json(
    support_privacy, privacy_tmp, pretty = TRUE, auto_unbox = TRUE,
    digits = 17, null = "null", na = "null"
  )
  if (file.exists(support_geometry_privacy_file)) unlink(support_geometry_privacy_file)
  if (!file.rename(privacy_tmp, support_geometry_privacy_file)) {
    stop("Could not atomically publish support geometry privacy provenance.")
  }
  }
} else if (!preserve_verified_support_buffer) {
  if (file.exists(buffers_file)) unlink(buffers_file)
  if (file.exists(support_geometry_privacy_file)) unlink(support_geometry_privacy_file)
}

filled <- indicator_cols[vapply(clean[indicator_cols], function(x) any(is.finite(x)), logical(1))]
explicitly_excluded_outside <- !inside & !is.na(assessment$include_in_model_development) & !assessment$include_in_model_development
outside_review_pending <- !inside & manual_status == "pending_manual_confirmation"
confirmed_for_sensitivity <- inside | (
  target_status == "confirmed_in_scope" &
  sampling_support_status == "confirmed_compatible" &
  !is.na(assessment$include_in_model_development) & assessment$include_in_model_development
)
sensitivity_plan <- list(
  project_id = cfg$project_id,
  status = if (length(filled)) "ready_for_model_runs" else "pending_lab_results",
  primary_scenario = list(
    id = "REVIEW_FILTERED_PRIMARY", n_samples = sum(!explicitly_excluded_outside),
    role = "primary candidate set; pending outside reviews retained as DRAFT and explicit include=false decisions excluded"
  ),
  scenarios = list(
    list(
      id = "ALL_ACTUAL_AUDIT", n_samples = nrow(core),
      status = "hook_available",
      purpose = "all actual coordinates retained for audit/sensitivity; not a validation set"
    ),
    list(
      id = "INSIDE_ROI_ONLY", n_samples = sum(inside),
      status = if (sum(inside) > 0L) "hook_available" else "unavailable",
      purpose = "geographic sensitivity comparison only; outside points are not a validation set"
    ),
    list(
      id = "ELIGIBLE_AFTER_TARGET_SUPPORT_REVIEW", n_samples = sum(confirmed_for_sensitivity),
      status = if (sum(confirmed_for_sensitivity) > 0L) "hook_available" else "pending_manual_confirmation",
      purpose = "inside-frame samples plus outside samples explicitly accepted after target-population and sampling-support review"
    )
  ),
  aoa_status = "pending_model_fit_model_dependent",
  final_map_domain = "original_roi_only"
)
jsonlite::write_json(sensitivity_plan, file.path(qa_dir, "sensitivity_plan.json"), pretty = TRUE, auto_unbox = TRUE)

summary <- list(
  project_id = cfg$project_id,
  n_samples = nrow(core),
  coordinates_policy = "actual coordinates retained without snapping",
  roi_signature = roi_signature,
  geographic_cache_status = geographic_cache_status,
  n_inside_roi = sum(inside),
  n_outside_roi = sum(!inside),
  n_pending_outside_review = sum(outside_review_pending),
  n_explicitly_excluded_outside = sum(explicitly_excluded_outside),
  primary_sample_count_after_review = sum(!explicitly_excluded_outside),
  geographic_status_is_separate_from_covariate_support = TRUE,
  n_with_complete_workflow1_covariates = sum(cov_complete),
  n_with_complete_current_support_covariates = sum(current_cov_complete),
  n_with_complete_workflow1_pc = sum(pc_complete),
  n_workflow1_grid_support_gap = sum(workflow1_grid_support_gap),
  n_requiring_covariate_support_for_execution = sum(requires_covariate_support_for_execution),
  n_requiring_covariate_support = sum(requires_covariate_support_for_execution),
  n_requiring_local_workflow1_raw_pca_rebuild = sum(requires_local_workflow1_raw_pca_rebuild),
  n_requiring_external_covariate_support = sum(requires_external_covariate_support),
  n_requiring_pca_support_rebuild = sum(requires_pca_support_rebuild),
  n_requiring_gee_download = sum(requires_gee_download),
  support_buffer_m = buffer_m,
  support_geometry_policy = support_geometry_policy,
  support_geometry_source = if (file.exists(support_geometry_privacy_file)) "reviewed_roi_bounding_envelope_plus_fixed_metric_buffer" else "not_required_verified_workflow1_raw_local_rebuild",
  download_geometry_is_prediction_domain = FALSE,
  analytical_support_mask_policy = "workflow1_pc_mask_plus_actual_sample_cells_local_only",
  support_geometry_contains_sample_attributes = FALSE,
  support_geometry_privacy_provenance_status = if (file.exists(support_geometry_privacy_file)) "certified_by_preflight" else "not_required_or_missing",
  support_geometry_privacy_provenance_file = normalizePath(support_geometry_privacy_file, winslash = "/", mustWork = FALSE),
  n_with_complete_current_actual_pc = sum(actual_pc_complete),
  pca_reference_hash = pca_reference_hash,
  pca_reference_frozen = pca_reference_frozen,
  pca_reference_version = pca_reference_version,
  current_pca_provenance_status = pca_provenance_status,
  current_pca_provenance_mode = pca_provenance_mode,
  current_pca_provenance_valid = pca_provenance_valid,
  current_pca_provenance_reasons = pca_provenance_reasons,
  support_download_provenance_status = support_download_provenance_status,
  support_download_provenance_valid = support_download_provenance_valid,
  support_download_provenance_reasons = as.character(support_download_check$reasons %||% character()),
  n_with_trusted_current_actual_pc = sum(current_actual_pca_trusted),
  n_requiring_pca_refresh = sum(requires_pca_refresh),
  n_soil_other = sum(soil_other, na.rm = TRUE),
  n_soil_unmapped = sum(soil_unmapped, na.rm = TRUE),
  soil_type_status = if (file.exists(soil_file)) "configured" else "not_configured",
  planned_link_policy = "distance computed only for exact code or declared planned_point_id; no nearest-point substitution",
  n_planned_links_available = sum(!is.na(links$planned_point_id)),
  n_relocation_reasons_recorded = sum(relocation_reason_status == "recorded"),
  assessment_file = assessment_file,
  assessment_file_status = assessment_file_status,
  target_population_assessment_status = if (all(target_status != "pending_manual_confirmation")) "provided" else "pending_manual_confirmation",
  sampling_support_assessment_status = if (all(sampling_support_status != "pending_manual_confirmation")) "provided" else "pending_manual_confirmation",
  n_pending_manual_assessment = sum(manual_status == "pending_manual_confirmation"),
  aoa_assessment_status = "pending_model_fit_model_dependent",
  outside_points_role = "calibration candidates subject to target-population, sampling-support, covariate-support and model-dependent AOA review; not a validation set",
  final_map_domain = "original_roi_only",
  indicator_columns = indicator_cols,
  indicators_with_results = filled,
  point_qa_csv = normalizePath(qa_file, winslash = "/", mustWork = FALSE),
  outside_roi_gpkg = if (length(outside_idx)) normalizePath(outside_file, winslash = "/", mustWork = FALSE) else NA_character_,
  sensitivity_plan_json = normalizePath(file.path(qa_dir, "sensitivity_plan.json"), winslash = "/", mustWork = FALSE)
)
jsonlite::write_json(summary, file.path(qa_dir, "preflight_summary.json"), pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(
  "sample_actual preflight complete: ", nrow(core),
  " samples; outside ROI: ", sum(!inside),
  "; covariate support required for execution: ", sum(requires_covariate_support_for_execution),
  "; manual assessment pending: ", sum(manual_status == "pending_manual_confirmation"),
  "; indicators with results: ", length(filled), "\n", sep = ""
)
