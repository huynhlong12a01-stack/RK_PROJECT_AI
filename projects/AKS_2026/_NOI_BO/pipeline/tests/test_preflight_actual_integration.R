suppressPackageStartupMessages({
  library(readr)
  library(jsonlite)
})

base <- "projects/AKS_2026"
raw <- as.data.frame(readr::read_csv(
  file.path(base, "02_NOI_SUY_BAN_DO/01_DAU_VAO/sample_actual.csv"),
  show_col_types = FALSE, progress = FALSE
))
clean <- as.data.frame(readr::read_csv(
  file.path(base, "_NOI_BO/work/interpolation/sample_actual_clean.csv"),
  show_col_types = FALSE, progress = FALSE
))
qa <- as.data.frame(readr::read_csv(
  file.path(base, "_NOI_BO/work/interpolation/qa/sample_roi_status.csv"),
  show_col_types = FALSE, progress = FALSE
))
summary <- jsonlite::read_json(
  file.path(base, "_NOI_BO/work/interpolation/qa/preflight_summary.json"),
  simplifyVector = TRUE
)
review <- as.data.frame(readr::read_csv(
  file.path(base, "02_NOI_SUY_BAN_DO/01_DAU_VAO/outside_sample_review.csv"),
  show_col_types = FALSE, progress = FALSE,
  col_types = readr::cols(.default = "c")
))

stopifnot(identical(as.character(raw$code), as.character(clean$code)))
stopifnot(isTRUE(all.equal(as.numeric(raw$lat), as.numeric(clean$lat), tolerance = 0)))
stopifnot(isTRUE(all.equal(as.numeric(raw$lon), as.numeric(clean$lon), tolerance = 0)))
stopifnot(nrow(qa) == 94L)
stopifnot(sum(qa$inside_roi) == 72L)
stopifnot(sum(!qa$inside_roi) == 22L)
stopifnot(all(qa$distance_to_roi_m[qa$inside_roi] == 0))
stopifnot(all(qa$distance_to_roi_m[!qa$inside_roi] > 0))
stopifnot(all(qa$current_actual_pca_complete))
stopifnot(all(!qa$requires_covariate_support_for_execution))
stopifnot(all(qa$covariate_support_status == "ready_current_pca_verified"))
stopifnot(all(
  qa$current_pca_provenance_mode ==
    "local_rebuild_from_verified_workflow1_raw_covariates"
))
stopifnot(all(!qa$requires_local_workflow1_raw_pca_rebuild))
stopifnot(all(!qa$requires_external_covariate_support))
stopifnot("soil_unmapped" %in% names(qa))
stopifnot(all(qa$soil_model_group[qa$soil_source_class == "Unmapped"] == "Unmapped"))
stopifnot(all(!qa$soil_other[qa$soil_source_class == "Unmapped"]))
stopifnot(all(qa$soil_source_class[qa$soil_other] != "Unmapped"))
stopifnot(sum(qa$soil_other) == as.integer(summary$n_soil_other))
stopifnot(sum(qa$soil_unmapped) == as.integer(summary$n_soil_unmapped))
stopifnot(all(qa$planned_link_status == "unavailable_no_identifier"))
stopifnot(all(is.na(qa$planned_to_actual_distance_m)))
stopifnot(all(qa$relocation_reason_status[qa$inside_roi] == "unavailable_not_recorded"))
stopifnot(all(qa$relocation_reason_status[!qa$inside_roi] == "recorded"))
stopifnot(all(qa$target_population_status[qa$inside_roi] == "inside_original_sampling_frame"))
stopifnot(all(qa$analysis_role[qa$inside_roi] == "model_development_inside_sampling_frame"))
stopifnot(all(qa$analysis_role[!qa$inside_roi] == "model_development_confirmed"))
stopifnot(all(qa$sampling_support_status[qa$inside_roi] == "inside_sampling_frame_support"))
stopifnot(all(qa$target_population_status[!qa$inside_roi] == "confirmed_in_scope"))
stopifnot(all(qa$sampling_support_status[!qa$inside_roi] == "confirmed_compatible"))
stopifnot(all(qa$manual_assessment_status[!qa$inside_roi] == "confirmed"))
stopifnot(all(qa$include_in_model_development[!qa$inside_roi]))
stopifnot(all(qa$aoa_assessment_status == "pending_model_fit_model_dependent"))
stopifnot(isTRUE(summary$geographic_status_is_separate_from_covariate_support))
stopifnot(summary$n_outside_roi == 22L)
stopifnot(summary$n_requiring_covariate_support_for_execution == 0L)
stopifnot(summary$n_requiring_covariate_support == 0L)
stopifnot(summary$n_with_complete_workflow1_covariates == 94L)
stopifnot(summary$n_workflow1_grid_support_gap == sum(qa$workflow1_grid_support_gap))
stopifnot(summary$n_soil_other == sum(qa$soil_other))
stopifnot(summary$n_soil_unmapped == sum(qa$soil_unmapped))
stopifnot(summary$n_planned_links_available == 0L)
stopifnot(summary$n_pending_manual_assessment == 0L)
stopifnot(summary$n_pending_outside_review == 0L)
stopifnot(summary$n_explicitly_excluded_outside == 0L)
stopifnot(summary$primary_sample_count_after_review == 94L)
stopifnot(summary$final_map_domain == "original_roi_only")
buffer_file <- file.path(base, "_NOI_BO/work/interpolation/covariate_support_buffers.gpkg")
privacy_file <- file.path(base, "_NOI_BO/work/interpolation/qa/support_geometry_privacy.json")
stopifnot(isTRUE(summary$current_pca_provenance_valid))
stopifnot(summary$n_with_trusted_current_actual_pc == 94L)
stopifnot(summary$n_requiring_pca_refresh == 0L)
stopifnot(summary$n_requiring_pca_support_rebuild == 0L)
stopifnot(summary$n_requiring_local_workflow1_raw_pca_rebuild == 0L)
stopifnot(summary$n_requiring_external_covariate_support == 0L)
stopifnot(summary$n_requiring_gee_download == 0L)
stopifnot(
  summary$current_pca_provenance_mode ==
    "local_rebuild_from_verified_workflow1_raw_covariates"
)
stopifnot(summary$support_geometry_policy == "fixed_roi_buffer_no_sample_geometry")
stopifnot(summary$support_geometry_source == "not_required_verified_workflow1_raw_local_rebuild")
stopifnot(identical(summary$support_geometry_contains_sample_attributes, FALSE))
stopifnot(summary$support_geometry_privacy_provenance_status == "not_required_or_missing")
stopifnot(!file.exists(buffer_file), !file.exists(privacy_file))
pca_provenance <- jsonlite::read_json(
  file.path(base, "_NOI_BO/work/interpolation/qa/pca_current_provenance.json"),
  simplifyVector = TRUE
)
stopifnot(
  pca_provenance$provenance_mode ==
    "local_rebuild_from_verified_workflow1_raw_covariates"
)
stopifnot(
  pca_provenance$raw_covariate_source ==
    "verified_workflow1_raw_covariates"
)
stopifnot(identical(pca_provenance$external_data_transfer_for_pca_refresh, FALSE))
stopifnot(identical(pca_provenance$actual_sample_geometry_sent_to_gee, FALSE))
stopifnot(identical(pca_provenance$gee_support_download_used, FALSE))
stopifnot(identical(pca_provenance$download_geometry_is_not_prediction_domain, TRUE))
stopifnot(
  pca_provenance$analytical_support_mask_policy ==
    "workflow1_pc_mask_plus_actual_sample_cells_local_only"
)
stopifnot(as.integer(pca_provenance$verified_actual_sample_count) == 94L)
stopifnot(file.exists(file.path(base, "_NOI_BO/work/interpolation/outside_samples.gpkg")))

outside_codes <- qa$code[!qa$inside_roi]
stopifnot(nrow(review) == 22L)
stopifnot(identical(as.character(review$code), as.character(outside_codes)))
stopifnot(all(review$relocation_reason == "access_constraint_near_planned_location"))
stopifnot(all(tolower(review$target_population_in_scope) == "true"))
stopifnot(all(tolower(review$sampling_support_compatible) == "true"))
stopifnot(all(tolower(review$include_in_model_development) == "true"))
stopifnot(all(review$reviewer == "project_owner"))
stopifnot(all(review$review_date == "2026-07-15"))

cat("actual preflight integration tests passed\n")
