# Shared fail-closed provenance checks for interpolation PCA rasters.
# This file contains only deterministic validation helpers; it never writes
# project outputs.

pca_support_sha256 <- function(path) {
  if (!file.exists(path)) stop("Cannot hash missing file: ", path)
  tolower(unname(digest::digest(path, algo = "sha256", file = TRUE)))
}

pca_support_is_sha256 <- function(value) {
  length(value) == 1L && !is.na(value) &&
    grepl("^[0-9a-f]{64}$", as.character(value))
}

pca_support_named_hashes <- function(paths, labels) {
  if (length(paths) != length(labels) || anyDuplicated(labels)) {
    stop("Hash labels must uniquely match files.")
  }
  missing <- paths[!file.exists(paths)]
  if (length(missing)) stop("Cannot hash missing file(s): ", paste(missing, collapse = ", "))
  setNames(vapply(paths, pca_support_sha256, character(1)), labels)
}

pca_support_exact_hash_map <- function(recorded, current, labels) {
  recorded <- tryCatch(unlist(recorded, use.names = TRUE), error = function(e) character())
  current <- tryCatch(unlist(current, use.names = TRUE), error = function(e) character())
  if (!setequal(names(recorded), labels) || !setequal(names(current), labels)) return(FALSE)
  recorded <- tolower(as.character(recorded[labels]))
  current <- tolower(as.character(current[labels]))
  all(vapply(recorded, pca_support_is_sha256, logical(1))) &&
    all(vapply(current, pca_support_is_sha256, logical(1))) &&
    identical(unname(recorded), unname(current))
}

pca_support_json_sha256 <- function(value) {
  canonical <- jsonlite::toJSON(
    value, auto_unbox = TRUE, digits = 17, null = "null", na = "null",
    pretty = FALSE
  )
  tolower(digest::digest(canonical, algo = "sha256", serialize = FALSE))
}

pca_support_coordinate_sha256 <- function(points) {
  required <- c("code", "lat", "lon")
  if (!all(required %in% names(points))) stop("Coordinate hash requires code, lat and lon.")
  code <- trimws(as.character(points$code))
  lat <- suppressWarnings(as.numeric(points$lat))
  lon <- suppressWarnings(as.numeric(points$lon))
  if (any(!nzchar(code)) || any(!is.finite(lat)) || any(!is.finite(lon))) {
    stop("Coordinate hash cannot be computed from invalid coordinates.")
  }
  payload <- lapply(seq_along(code), function(i) {
    list(code = code[[i]], lat = lat[[i]], lon = lon[[i]])
  })
  pca_support_json_sha256(payload)
}

pca_support_scalar_text <- function(value) {
  if (length(value) != 1L || is.na(value)) return(NA_character_)
  as.character(value)
}

pca_support_scalar_number <- function(value) {
  value <- suppressWarnings(as.numeric(value))
  if (length(value) != 1L || !is.finite(value)) return(NA_real_)
  value
}

pca_support_same_number <- function(a, b, tolerance = 1e-8) {
  a <- pca_support_scalar_number(a)
  b <- pca_support_scalar_number(b)
  is.finite(a) && is.finite(b) && abs(a - b) <= tolerance
}

pca_support_file_grid <- function(path) {
  x <- terra::rast(path)[[1]]
  epsg <- tryCatch(as.integer(sf::st_crs(terra::crs(x))$epsg), error = function(e) NA_integer_)
  e <- terra::ext(x)
  r <- terra::res(x)
  list(
    crs = if (is.na(epsg)) terra::crs(x) else paste0("EPSG:", epsg),
    epsg = epsg,
    computational_grid_m = as.numeric(r[[1]]),
    width = terra::ncol(x),
    height = terra::nrow(x),
    transform = c(as.numeric(r[[1]]), 0, as.numeric(e$xmin), 0, -as.numeric(r[[2]]), as.numeric(e$ymax)),
    bounds = c(as.numeric(e$xmin), as.numeric(e$ymin), as.numeric(e$xmax), as.numeric(e$ymax))
  )
}

pca_support_grid_matches <- function(recorded, current, expected_epsg, expected_resolution) {
  if (!is.list(recorded)) return(FALSE)
  recorded_transform <- suppressWarnings(as.numeric(recorded$transform))
  recorded_bounds <- suppressWarnings(as.numeric(recorded$bounds))
  expected_crs <- paste0("EPSG:", as.integer(expected_epsg))
  identical(toupper(pca_support_scalar_text(recorded$crs)), toupper(expected_crs)) &&
    identical(toupper(pca_support_scalar_text(current$crs)), toupper(expected_crs)) &&
    pca_support_same_number(recorded$computational_grid_m, expected_resolution) &&
    pca_support_same_number(current$computational_grid_m, expected_resolution) &&
    identical(as.integer(recorded$width), as.integer(current$width)) &&
    identical(as.integer(recorded$height), as.integer(current$height)) &&
    length(recorded_transform) == 6L && length(recorded_bounds) == 4L &&
    isTRUE(all.equal(recorded_transform, as.numeric(current$transform), tolerance = 1e-8)) &&
    isTRUE(all.equal(recorded_bounds, as.numeric(current$bounds), tolerance = 1e-8))
}

pca_support_extent_contains <- function(container_path, contained) {
  container_raster <- terra::rast(container_path)[[1]]
  container <- terra::ext(container_raster)
  item <- if (inherits(contained, "SpatExtent")) contained else terra::ext(contained)
  tolerance <- max(terra::res(container_raster)) * 1e-6
  container$xmin <= item$xmin + tolerance &&
    container$ymin <= item$ymin + tolerance &&
    container$xmax >= item$xmax - tolerance &&
    container$ymax >= item$ymax - tolerance
}

pca_support_validate_download <- function(
    sidecar_file, raw_files, features, cfg, roi_file, buffer_file, legacy_template_file) {
  reasons <- character()
  add <- function(message) reasons <<- c(reasons, message)
  support_geometry_provenance_file <- file.path(dirname(sidecar_file), "support_geometry_privacy.json")
  required_files <- c(
    sidecar_file, raw_files, roi_file, buffer_file, legacy_template_file,
    support_geometry_provenance_file
  )
  missing <- required_files[!file.exists(required_files)]
  if (length(missing)) {
    add(paste0("missing support lineage file(s): ", paste(missing, collapse = ", ")))
    return(list(valid = FALSE, reasons = unique(reasons)))
  }
  payload <- tryCatch(
    jsonlite::read_json(sidecar_file, simplifyVector = TRUE),
    error = function(e) {
      add(paste0("invalid support download sidecar: ", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(payload)) return(list(valid = FALSE, reasons = unique(reasons)))
  if (!identical(pca_support_scalar_text(payload$schema_version), "2.0.0")) add("support sidecar schema_version must be 2.0.0")
  if (!identical(pca_support_scalar_text(payload$provenance_type), "gee_covariate_support_download")) add("support provenance_type mismatch")
  if (!identical(pca_support_scalar_text(payload$status), "complete")) add("support download is not complete")
  if (!identical(pca_support_scalar_text(payload$project_id), as.character(cfg$project_id))) add("support project_id mismatch")
  if (!identical(as.character(payload$bands), as.character(features))) add("support band order must exactly match frozen PCA feature order")
  windows <- suppressWarnings(as.integer(payload$support_windows))
  completed <- suppressWarnings(as.integer(payload$completed_windows))
  if (length(windows) != 1L || is.na(windows) || windows < 1L ||
      length(completed) != 1L || is.na(completed) || completed != windows) {
    add("support download windows are incomplete")
  }
  max_tile_side <- suppressWarnings(as.integer(payload$max_tile_side_pixels))
  max_window_pixels <- suppressWarnings(as.integer(payload$max_window_pixel_count))
  if (length(max_tile_side) != 1L || is.na(max_tile_side) || max_tile_side < 1L ||
      max_tile_side > 1024L || length(max_window_pixels) != 1L ||
      is.na(max_window_pixels) || max_window_pixels < 1L ||
      max_window_pixels > 1024L * 1024L) {
    add("support GEE request windows are missing or exceed the 1024-pixel safety bound")
  }

  support_geometry_provenance <- tryCatch(
    jsonlite::read_json(support_geometry_provenance_file, simplifyVector = TRUE),
    error = function(e) {
      add(paste0("invalid support geometry privacy provenance: ", conditionMessage(e)))
      NULL
    }
  )
  expected_attributes <- c(
    "support_geometry_policy", "support_buffer_m", "contains_sample_attributes"
  )
  if (is.null(support_geometry_provenance) ||
      !identical(pca_support_scalar_text(support_geometry_provenance$schema_version), "1.0.0") ||
      !identical(pca_support_scalar_text(support_geometry_provenance$provenance_type), "privacy_preserving_support_geometry") ||
      !identical(pca_support_scalar_text(support_geometry_provenance$status), "certified_by_preflight") ||
      !identical(pca_support_scalar_text(support_geometry_provenance$project_id), as.character(cfg$project_id)) ||
      !identical(pca_support_scalar_text(support_geometry_provenance$support_geometry_policy), as.character(cfg$support_policy$support_geometry_policy)) ||
      !identical(pca_support_scalar_text(support_geometry_provenance$geometry_source), "reviewed_roi_bounding_envelope_plus_fixed_metric_buffer") ||
      !identical(pca_support_scalar_text(support_geometry_provenance$geometry_derivation), "sf_projected_bbox_then_st_buffer_nQuadSegs_30") ||
      !identical(pca_support_scalar_text(support_geometry_provenance$coverage_guarantee), "contains_the_fixed_metric_buffer_of_the_reviewed_roi") ||
      !identical(toupper(pca_support_scalar_text(support_geometry_provenance$project_crs)), toupper(paste0("EPSG:", as.integer(cfg$crs_epsg)))) ||
      !pca_support_same_number(support_geometry_provenance$support_buffer_m, cfg$support_policy$covariate_support_buffer_m) ||
      !identical(suppressWarnings(as.integer(support_geometry_provenance$feature_count)), 1L) ||
      !setequal(as.character(support_geometry_provenance$attribute_schema), expected_attributes) ||
      !identical(support_geometry_provenance$contains_sample_attributes, FALSE) ||
      !identical(support_geometry_provenance$sample_coordinates_or_identifiers_used_to_define_geometry, FALSE) ||
      !identical(support_geometry_provenance$sample_coordinates_or_identifiers_in_attributes, FALSE) ||
      !identical(tolower(pca_support_scalar_text(support_geometry_provenance$roi_field_area_sha256)), pca_support_sha256(roi_file)) ||
      !identical(tolower(pca_support_scalar_text(support_geometry_provenance$support_geometry_file_sha256)), pca_support_sha256(buffer_file))) {
    add("support geometry privacy provenance is missing, stale or not privacy-preserving")
  }
  support_geometry_provenance_sha256 <- if (file.exists(support_geometry_provenance_file)) {
    pca_support_sha256(support_geometry_provenance_file)
  } else {
    NA_character_
  }

  source <- payload$source_identity
  if (!is.list(source)) {
    add("support source_identity must be an object")
    source <- list()
  }
  expected_source <- list(
    gee_project_id = as.character(cfg$gee_project_id),
    start_date = as.character(cfg$legacy_parameters$start_date),
    end_date = as.character(cfg$legacy_parameters$end_date),
    roi_field_area_sha256 = pca_support_sha256(roi_file),
    support_buffer_sha256 = pca_support_sha256(buffer_file),
    support_geometry_policy = as.character(cfg$support_policy$support_geometry_policy),
    support_geometry_provenance_sha256 = support_geometry_provenance_sha256,
    legacy_grid_template_sha256 = pca_support_sha256(legacy_template_file)
  )
  for (name in names(expected_source)) {
    actual <- pca_support_scalar_text(source[[name]])
    expected <- expected_source[[name]]
    if (grepl("_sha256$", name)) {
      actual <- tolower(actual)
      if (!pca_support_is_sha256(actual)) add(paste0(name, " is not lowercase SHA-256"))
    }
    if (!identical(actual, expected)) add(paste0("support ", name, " mismatch"))
  }
  privacy <- payload$privacy_gate
  expected_policy <- as.character(cfg$support_policy$support_geometry_policy)
  if (!is.list(privacy) ||
      !identical(pca_support_scalar_text(privacy$status), "verified_before_gee_initialization") ||
      !identical(pca_support_scalar_text(privacy$support_geometry_policy), expected_policy) ||
      !identical(pca_support_scalar_text(privacy$geometry_source), "reviewed_roi_bounding_envelope_plus_fixed_metric_buffer") ||
      !identical(pca_support_scalar_text(privacy$geometry_derivation), "sf_projected_bbox_then_st_buffer_nQuadSegs_30") ||
      !identical(pca_support_scalar_text(privacy$coverage_guarantee), "contains_the_fixed_metric_buffer_of_the_reviewed_roi") ||
      !pca_support_same_number(privacy$support_buffer_m, cfg$support_policy$covariate_support_buffer_m) ||
      !identical(privacy$geometry_certified_by_preflight_hash_chain, TRUE) ||
      !identical(privacy$attribute_schema_exact_and_privacy_minimal, TRUE) ||
      !identical(privacy$roi_hash_matches_current_file, TRUE) ||
      !identical(privacy$support_hash_matches_current_file, TRUE) ||
      !identical(privacy$sample_coordinates_or_identifiers_sent, FALSE) ||
      (!is.null(privacy$forbidden_sample_fields_present) && length(privacy$forbidden_sample_fields_present) != 0L) ||
      !identical(tolower(pca_support_scalar_text(privacy$preflight_geometry_provenance_sha256)), support_geometry_provenance_sha256)) {
    add("support privacy gate is missing, stale or permits sample-location disclosure")
  }

  current_hashes <- pca_support_named_hashes(raw_files, features)
  if (!pca_support_exact_hash_map(payload$raw_covariate_sha256, current_hashes, features)) {
    add("support raw covariate hashes do not exactly match current files")
  }
  common_grid <- tryCatch({
    stack <- terra::rast(raw_files)
    all(vapply(seq_len(terra::nlyr(stack)), function(i) {
      isTRUE(terra::compareGeom(stack[[1]], stack[[i]], stopOnError = FALSE))
    }, logical(1)))
  }, error = function(e) FALSE)
  if (!common_grid) add("support raw covariates do not share one grid")
  current_grid <- tryCatch(pca_support_file_grid(raw_files[[1]]), error = function(e) NULL)
  if (is.null(current_grid) || !pca_support_grid_matches(
      payload$output_grid, current_grid, cfg$crs_epsg, cfg$resolution_m)) {
    add("support output grid identity does not match current rasters/config")
  }
  if (!pca_support_extent_contains(raw_files[[1]], terra::ext(terra::rast(legacy_template_file)[[1]]))) {
    add("support grid does not contain the Workflow 1 grid extent")
  }
  buffer_extent <- tryCatch(terra::ext(terra::vect(buffer_file)), error = function(e) NULL)
  if (is.null(buffer_extent) || !pca_support_extent_contains(raw_files[[1]], buffer_extent)) {
    add("support grid does not contain the support-buffer extent")
  }
  list(
    valid = !length(reasons),
    reasons = unique(reasons),
    payload = payload,
    raw_covariate_sha256 = as.list(current_hashes),
    sidecar_sha256 = pca_support_sha256(sidecar_file),
    support_geometry_provenance_sha256 = support_geometry_provenance_sha256,
    source_identity_sha256 = pca_support_json_sha256(payload$source_identity),
    output_grid_sha256 = pca_support_json_sha256(payload$output_grid)
  )
}

pca_support_validate_workflow1 <- function(
    design_summary_file, design_pc_files, design_raw_files, design_raw_provenance_file,
    features, ref, reference_file, cfg, roi_file) {
  reasons <- character()
  add <- function(message) reasons <<- c(reasons, message)
  required <- c(design_summary_file, design_pc_files, design_raw_files, design_raw_provenance_file, reference_file, roi_file)
  missing <- required[!file.exists(required)]
  if (length(missing)) {
    add(paste0("missing Workflow 1 lineage file(s): ", paste(missing, collapse = ", ")))
    return(list(valid = FALSE, reasons = unique(reasons)))
  }
  summary <- tryCatch(jsonlite::read_json(design_summary_file, simplifyVector = TRUE), error = function(e) NULL)
  raw <- tryCatch(jsonlite::read_json(design_raw_provenance_file, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(summary) || is.null(raw)) {
    add("Workflow 1 lineage JSON is invalid")
    return(list(valid = FALSE, reasons = unique(reasons)))
  }
  pc_labels <- paste0("PC", seq_along(features))
  design_pc_hashes <- pca_support_named_hashes(design_pc_files, pc_labels)
  design_raw_hashes <- pca_support_named_hashes(design_raw_files, features)
  if (!identical(pca_support_scalar_text(summary$schema_version), "2.0.0") ||
      !isTRUE(summary$pca_input_lineage_verified)) add("Workflow 1 PCA summary is not certified schema v2")
  if (!pca_support_exact_hash_map(summary$pca_raster_sha256, design_pc_hashes, pc_labels)) add("Workflow 1 PC hashes mismatch")
  if (!pca_support_exact_hash_map(summary$raw_covariate_sha256, design_raw_hashes, features)) add("Workflow 1 raw hashes mismatch")
  if (!pca_support_exact_hash_map(raw$raw_covariate_sha256, design_raw_hashes, features)) add("Workflow 1 raw sidecar hashes mismatch")
  if (!identical(tolower(pca_support_scalar_text(summary$raw_provenance_sha256)), pca_support_sha256(design_raw_provenance_file))) {
    add("Workflow 1 raw provenance sidecar hash mismatch")
  }
  reference_hash <- tolower(pca_support_scalar_text(ref$reference_hash))
  parameter_hash <- tolower(pca_support_scalar_text(ref$parameter_hash))
  if (!pca_support_is_sha256(reference_hash) ||
      !identical(parameter_hash, reference_hash) ||
      !identical(tolower(pca_support_scalar_text(summary$reference_hash)), reference_hash) ||
      !identical(tolower(pca_support_scalar_text(summary$reference_file_sha256)), pca_support_sha256(reference_file))) {
    add("Workflow 1 frozen reference lineage mismatch")
  }
  source <- raw$source_identity
  grid <- raw$output_grid
  temporal <- raw$temporal_window
  if (!is.list(source) || !is.list(grid) || !is.list(temporal)) {
    add("Workflow 1 raw identity is malformed")
  } else {
    if (!identical(pca_support_scalar_text(raw$project_id), as.character(cfg$project_id))) add("Workflow 1 project_id mismatch")
    if (!identical(pca_support_scalar_text(source$gee_project_id), as.character(cfg$gee_project_id))) add("Workflow 1 GEE project mismatch")
    if (!identical(tolower(pca_support_scalar_text(source$roi_field_area_sha256)), pca_support_sha256(roi_file))) add("Workflow 1 ROI hash mismatch")
    if (!identical(toupper(pca_support_scalar_text(grid$crs)), toupper(paste0("EPSG:", as.integer(cfg$crs_epsg))))) add("Workflow 1 CRS mismatch")
    if (!pca_support_same_number(grid$computational_grid_m, cfg$resolution_m)) add("Workflow 1 grid resolution mismatch")
    if (!identical(pca_support_scalar_text(temporal$start_date_inclusive), as.character(cfg$legacy_parameters$start_date))) add("Workflow 1 start date mismatch")
    if (!identical(pca_support_scalar_text(temporal$end_date_exclusive), as.character(cfg$legacy_parameters$end_date))) add("Workflow 1 end date mismatch")
  }
  list(
    valid = !length(reasons),
    reasons = unique(reasons),
    summary = summary,
    raw_provenance = raw,
    design_pc_sha256 = as.list(design_pc_hashes),
    design_raw_sha256 = as.list(design_raw_hashes),
    design_summary_sha256 = pca_support_sha256(design_summary_file),
    design_raw_provenance_sha256 = pca_support_sha256(design_raw_provenance_file),
    source_identity_sha256 = pca_support_json_sha256(raw$source_identity),
    output_grid_sha256 = pca_support_json_sha256(raw$output_grid)
  )
}

pca_support_validate_current <- function(
    sidecar_file, current_pc_files, points, ref, reference_file, cfg, roi_file,
    buffer_file, support_raw_files, support_download_file, legacy_template_file,
    design_summary_file, design_pc_files, design_raw_files, design_raw_provenance_file,
    features) {
  reasons <- character()
  add <- function(message) reasons <<- c(reasons, message)
  pc_labels <- paste0("PC", seq_along(features))
  pc_file_labels <- paste0(pc_labels, ".tif")
  required <- c(sidecar_file, current_pc_files, reference_file, roi_file)
  missing <- required[!file.exists(required)]
  if (length(missing)) {
    add(paste0("missing current PCA lineage file(s): ", paste(missing, collapse = ", ")))
    return(list(valid = FALSE, reasons = unique(reasons), mode = "missing"))
  }
  payload <- tryCatch(jsonlite::read_json(sidecar_file, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(payload)) return(list(valid = FALSE, reasons = "current PCA provenance JSON is invalid", mode = "invalid"))
  mode <- pca_support_scalar_text(payload$provenance_mode)
  if (!identical(pca_support_scalar_text(payload$schema_version), "2.0.0")) add("current PCA provenance schema_version must be 2.0.0")
  if (!identical(pca_support_scalar_text(payload$provenance_type), "interpolation_pca_lineage")) add("current PCA provenance_type mismatch")
  if (!mode %in% c(
      "support_rebuild_from_verified_gee_covariates",
      "local_rebuild_from_verified_workflow1_raw_covariates",
      "verified_workflow1_copy")) add("current PCA provenance_mode is unsupported")
  if (!identical(pca_support_scalar_text(payload$project_id), as.character(cfg$project_id))) add("current PCA project_id mismatch")
  if (!identical(pca_support_scalar_text(payload$verification_status), "verified_full_hash_chain")) add("current PCA verification_status mismatch")

  current_pc_hashes <- pca_support_named_hashes(current_pc_files, pc_file_labels)
  if (!pca_support_exact_hash_map(payload$pc_file_sha256, current_pc_hashes, pc_file_labels)) add("current PC hashes do not exactly match provenance")
  current_pc_grid <- tryCatch(pca_support_file_grid(current_pc_files[[1]]), error = function(e) NULL)
  current_pc_common_grid <- tryCatch({
    stack <- terra::rast(current_pc_files)
    all(vapply(seq_len(terra::nlyr(stack)), function(i) {
      isTRUE(terra::compareGeom(stack[[1]], stack[[i]], stopOnError = FALSE))
    }, logical(1)))
  }, error = function(e) FALSE)
  if (is.null(current_pc_grid) || !current_pc_common_grid ||
      !identical(
        tolower(pca_support_scalar_text(payload$pca_output_grid_sha256)),
        pca_support_json_sha256(current_pc_grid)
      )) {
    add("current PC output-grid identity mismatch")
  }
  reference_hash <- tolower(pca_support_scalar_text(ref$reference_hash))
  parameter_hash <- tolower(pca_support_scalar_text(ref$parameter_hash))
  reference_version <- pca_support_scalar_text(ref$reference_version)
  if (!isTRUE(ref$reference_frozen) || !pca_support_is_sha256(reference_hash) ||
      !identical(parameter_hash, reference_hash)) add("current frozen PCA reference is invalid")
  if (!identical(tolower(pca_support_scalar_text(payload$pca_reference_hash)), reference_hash) ||
      !identical(pca_support_scalar_text(payload$reference_version), reference_version) ||
      !isTRUE(payload$reference_frozen) ||
      !identical(tolower(pca_support_scalar_text(payload$reference_file_sha256)), pca_support_sha256(reference_file))) {
    add("current PCA frozen-reference lineage mismatch")
  }
  coordinate_hash <- tryCatch(pca_support_coordinate_sha256(points), error = function(e) NA_character_)
  if (!pca_support_is_sha256(coordinate_hash) ||
      !identical(tolower(pca_support_scalar_text(payload$sample_coordinate_sha256)), coordinate_hash)) {
    add("current PCA sample-coordinate lineage mismatch")
  }

  if (identical(mode, "support_rebuild_from_verified_gee_covariates")) {
    download <- pca_support_validate_download(
      support_download_file, support_raw_files, features, cfg, roi_file,
      buffer_file, legacy_template_file
    )
    if (!isTRUE(download$valid)) {
      add(paste0("support download lineage invalid: ", paste(download$reasons, collapse = "; ")))
    } else {
      if (!pca_support_exact_hash_map(payload$raw_covariate_sha256, download$raw_covariate_sha256, features)) add("current PCA raw-support hashes mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$support_download_provenance_sha256)), download$sidecar_sha256)) add("current PCA support sidecar hash mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$support_geometry_provenance_sha256)), download$support_geometry_provenance_sha256)) add("current PCA support-geometry privacy provenance hash mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$support_source_identity_sha256)), download$source_identity_sha256)) add("current PCA support identity hash mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$support_output_grid_sha256)), download$output_grid_sha256)) add("current PCA support grid hash mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$roi_field_area_sha256)), pca_support_sha256(roi_file))) add("current PCA ROI hash mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$support_buffer_sha256)), pca_support_sha256(buffer_file))) add("current PCA support-buffer hash mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$legacy_grid_template_sha256)), pca_support_sha256(legacy_template_file))) add("current PCA legacy-template hash mismatch")
      source <- download$payload$source_identity
      grid <- download$payload$output_grid
      if (!identical(pca_support_scalar_text(payload$gee_project_id), pca_support_scalar_text(source$gee_project_id)) ||
          !identical(pca_support_scalar_text(payload$start_date), pca_support_scalar_text(source$start_date)) ||
          !identical(pca_support_scalar_text(payload$end_date), pca_support_scalar_text(source$end_date)) ||
          !identical(toupper(pca_support_scalar_text(payload$crs)), toupper(pca_support_scalar_text(grid$crs))) ||
          !pca_support_same_number(payload$computational_grid_m, grid$computational_grid_m) ||
          !identical(pca_support_scalar_text(payload$support_geometry_policy), pca_support_scalar_text(source$support_geometry_policy)) ||
          !identical(pca_support_scalar_text(payload$support_privacy_gate_status), "verified_before_gee_initialization") ||
          !identical(payload$download_geometry_is_not_prediction_domain, TRUE) ||
          !identical(pca_support_scalar_text(payload$analytical_support_mask_policy), "workflow1_pc_mask_plus_actual_sample_cells_local_only") ||
          !identical(payload$actual_sample_geometry_sent_to_gee, FALSE)) {
        add("current PCA support date/GEE/grid/privacy/analytical-domain identity mismatch")
      }
    }
    workflow1 <- pca_support_validate_workflow1(
      design_summary_file, design_pc_files, design_raw_files,
      design_raw_provenance_file, features, ref, reference_file, cfg, roi_file
    )
    if (!isTRUE(workflow1$valid)) {
      add(paste0("Workflow 1 hybrid source lineage invalid: ", paste(workflow1$reasons, collapse = "; ")))
    } else {
      if (!identical(tolower(pca_support_scalar_text(payload$source_workflow1_pca_summary_sha256)), workflow1$design_summary_sha256)) add("hybrid Workflow 1 PCA summary hash mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$source_workflow1_raw_provenance_sha256)), workflow1$design_raw_provenance_sha256)) add("hybrid Workflow 1 raw sidecar hash mismatch")
      if (!pca_support_exact_hash_map(payload$source_workflow1_pc_sha256, workflow1$design_pc_sha256, pc_labels)) add("hybrid Workflow 1 source PC hash set mismatch")
      if (!pca_support_exact_hash_map(payload$source_workflow1_raw_covariate_sha256, workflow1$design_raw_sha256, features)) add("hybrid Workflow 1 source raw hash set mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$source_workflow1_identity_sha256)), workflow1$source_identity_sha256)) add("hybrid Workflow 1 identity hash mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$source_workflow1_grid_sha256)), workflow1$output_grid_sha256)) add("hybrid Workflow 1 grid hash mismatch")
    }
  } else if (identical(mode, "local_rebuild_from_verified_workflow1_raw_covariates")) {
    workflow1 <- pca_support_validate_workflow1(
      design_summary_file, design_pc_files, design_raw_files,
      design_raw_provenance_file, features, ref, reference_file, cfg, roi_file
    )
    if (!isTRUE(workflow1$valid)) {
      add(paste0("Workflow 1 local-raw source lineage invalid: ", paste(workflow1$reasons, collapse = "; ")))
    } else {
      if (!pca_support_exact_hash_map(payload$raw_covariate_sha256, workflow1$design_raw_sha256, features)) add("local rebuild raw hash set mismatch")
      if (!pca_support_exact_hash_map(payload$source_workflow1_raw_covariate_sha256, workflow1$design_raw_sha256, features)) add("local rebuild Workflow 1 raw source hash mismatch")
      if (!pca_support_exact_hash_map(payload$source_workflow1_pc_sha256, workflow1$design_pc_sha256, pc_labels)) add("local rebuild Workflow 1 PC source hash mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$source_workflow1_pca_summary_sha256)), workflow1$design_summary_sha256)) add("local rebuild Workflow 1 PCA summary hash mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$source_workflow1_raw_provenance_sha256)), workflow1$design_raw_provenance_sha256)) add("local rebuild Workflow 1 raw sidecar hash mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$source_workflow1_identity_sha256)), workflow1$source_identity_sha256)) add("local rebuild Workflow 1 identity hash mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$source_workflow1_grid_sha256)), workflow1$output_grid_sha256)) add("local rebuild Workflow 1 grid identity mismatch")
      raw_grid <- tryCatch(pca_support_file_grid(design_raw_files[[1]]), error = function(e) NULL)
      if (is.null(raw_grid) || is.null(current_pc_grid) ||
          !identical(pca_support_json_sha256(raw_grid), pca_support_json_sha256(current_pc_grid))) {
        add("local rebuild PC grid is not the certified Workflow 1 raw grid")
      }
    }
    verified_count <- suppressWarnings(as.integer(payload$verified_actual_sample_count))
    if (!identical(tolower(pca_support_scalar_text(payload$roi_field_area_sha256)), pca_support_sha256(roi_file)) ||
        !identical(pca_support_scalar_text(payload$raw_covariate_source), "verified_workflow1_raw_covariates") ||
        !identical(payload$workflow1_pc_values_prioritized, TRUE) ||
        !identical(payload$download_geometry_is_not_prediction_domain, TRUE) ||
        !identical(pca_support_scalar_text(payload$analytical_support_mask_policy), "workflow1_pc_mask_plus_actual_sample_cells_local_only") ||
        !identical(payload$external_data_transfer_for_pca_refresh, FALSE) ||
        !identical(payload$actual_sample_geometry_sent_to_gee, FALSE) ||
        !identical(payload$gee_support_download_used, FALSE) ||
        length(verified_count) != 1L || is.na(verified_count) || verified_count != nrow(points)) {
      add("local rebuild privacy/source/analytical-domain policy mismatch")
    }
  } else if (identical(mode, "verified_workflow1_copy")) {
    workflow1 <- pca_support_validate_workflow1(
      design_summary_file, design_pc_files, design_raw_files,
      design_raw_provenance_file, features, ref, reference_file, cfg, roi_file
    )
    if (!isTRUE(workflow1$valid)) {
      add(paste0("Workflow 1 source lineage invalid: ", paste(workflow1$reasons, collapse = "; ")))
    } else {
      current_pc_by_component <- setNames(unname(current_pc_hashes), pc_labels)
      if (!pca_support_exact_hash_map(workflow1$design_pc_sha256, current_pc_by_component, pc_labels)) add("current PC files are not exact Workflow 1 copies")
      if (!identical(tolower(pca_support_scalar_text(payload$source_workflow1_pca_summary_sha256)), workflow1$design_summary_sha256)) add("Workflow 1 PCA summary hash mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$source_workflow1_raw_provenance_sha256)), workflow1$design_raw_provenance_sha256)) add("Workflow 1 raw sidecar hash mismatch")
      if (!pca_support_exact_hash_map(payload$source_workflow1_pc_sha256, workflow1$design_pc_sha256, pc_labels)) add("Workflow 1 source PC hash set mismatch")
      if (!pca_support_exact_hash_map(payload$source_workflow1_raw_covariate_sha256, workflow1$design_raw_sha256, features)) add("Workflow 1 source raw hash set mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$source_workflow1_identity_sha256)), workflow1$source_identity_sha256)) add("Workflow 1 source identity hash mismatch")
      if (!identical(tolower(pca_support_scalar_text(payload$source_workflow1_grid_sha256)), workflow1$output_grid_sha256)) add("Workflow 1 source grid hash mismatch")
    }
  }
  list(valid = !length(reasons), reasons = unique(reasons), mode = mode, payload = payload)
}
