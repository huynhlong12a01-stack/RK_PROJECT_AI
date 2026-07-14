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
stopifnot(all(qa$covariate_support_status %in% c("ready_current_pca_verified", "current_pca_available_unverified_requires_refresh", "covered_workflow1_pca")))
stopifnot(sum(qa$soil_other) == 10L)
stopifnot(all(qa$planned_link_status == "unavailable_no_identifier"))
stopifnot(all(is.na(qa$planned_to_actual_distance_m)))
stopifnot(all(qa$relocation_reason_status[qa$inside_roi] == "unavailable_not_recorded"))
stopifnot(all(qa$relocation_reason_status[!qa$inside_roi] == "recorded"))
stopifnot(all(qa$target_population_status[qa$inside_roi] == "inside_original_sampling_frame"))
stopifnot(all(qa$analysis_role[qa$inside_roi] == "model_development_inside_sampling_frame"))
stopifnot(all(qa$analysis_role[!qa$inside_roi] == "model_development_pending_review"))
stopifnot(all(qa$sampling_support_status[qa$inside_roi] == "inside_sampling_frame_support"))
stopifnot(all(qa$target_population_status[!qa$inside_roi] == "pending_manual_confirmation"))
stopifnot(all(qa$sampling_support_status[!qa$inside_roi] == "pending_manual_confirmation"))
stopifnot(all(qa$aoa_assessment_status == "pending_model_fit_model_dependent"))
stopifnot(isTRUE(summary$geographic_status_is_separate_from_covariate_support))
stopifnot(summary$n_outside_roi == 22L)
stopifnot(summary$n_requiring_covariate_support_for_execution == 0L)
stopifnot(summary$n_requiring_covariate_support == 0L)
stopifnot(summary$n_workflow1_grid_support_gap == sum(qa$workflow1_grid_support_gap))
stopifnot(summary$n_soil_other == 10L)
stopifnot(summary$n_planned_links_available == 0L)
stopifnot(summary$n_pending_manual_assessment == 22L)
stopifnot(summary$final_map_domain == "original_roi_only")
buffer_file <- file.path(base, "_NOI_BO/work/interpolation/covariate_support_buffers.gpkg")
stopifnot(file.exists(buffer_file) == (summary$n_requiring_pca_support_rebuild > 0L))
stopifnot(summary$n_requiring_gee_download == 0L)
stopifnot(file.exists(file.path(base, "_NOI_BO/work/interpolation/outside_samples.gpkg")))

outside_codes <- qa$code[!qa$inside_roi]
stopifnot(nrow(review) == 22L)
stopifnot(identical(as.character(review$code), as.character(outside_codes)))
stopifnot(all(review$relocation_reason == "access_constraint_near_planned_location"))
stopifnot(all(is.na(review$target_population_in_scope)))
stopifnot(all(is.na(review$include_in_model_development)))

cat("actual preflight integration tests passed\n")