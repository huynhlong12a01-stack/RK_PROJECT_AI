suppressPackageStartupMessages({
  library(readr)
  library(jsonlite)
})

base <- "projects/PHU_YEN_MOCK"
qa_dir <- file.path(base, "_NOI_BO/work/models/qa")
summary <- jsonlite::read_json(file.path(qa_dir, "model_input_summary.json"), simplifyVector = TRUE)
metadata <- as.data.frame(readr::read_csv(
  file.path(qa_dir, "indicator_metadata_status.csv"),
  show_col_types = FALSE, progress = FALSE
))
scenarios <- as.data.frame(readr::read_csv(
  file.path(qa_dir, "sensitivity_input_manifest.csv"),
  show_col_types = FALSE, progress = FALSE
))

expected_targets <- c("pH_H2O", "OM_pct", "P_Olsen_mgkg", "K_available_mgkg")
expected_scenarios <- c(
  "REVIEW_FILTERED_PRIMARY", "ALL_ACTUAL_AUDIT",
  "INSIDE_ROI_ONLY", "ELIGIBLE_AFTER_TARGET_SUPPORT_REVIEW"
)

stopifnot(summary$interpretation == "one average result row per sample")
stopifnot(summary$product_status == "READY_FOR_CONTINUOUS_MODEL")
stopifnot(!isTRUE(summary$classification_created))
stopifnot(!isTRUE(summary$fertilizer_recommendation_created))
stopifnot(summary$n_samples == 105L)
stopifnot(summary$n_samples_primary == summary$n_samples)
stopifnot(summary$outside_review_status == "complete")
stopifnot(summary$n_pending_outside_review == 0L)
stopifnot(summary$n_explicitly_excluded_outside == 0L)
stopifnot(summary$aoa_status == "pending_model_fit_model_dependent")
stopifnot(summary$final_map_domain == "original_roi_only")

stopifnot(setequal(metadata$indicator, expected_targets))
stopifnot(all(metadata$metadata_entry_exists))
stopifnot(all(metadata$metadata_confirmed))
stopifnot(all(metadata$has_results))
stopifnot(all(metadata$product_status == "READY_FOR_CONTINUOUS_MODEL"))

stopifnot(setequal(scenarios$scenario_id, expected_scenarios))
stopifnot(all(scenarios$n_samples == summary$n_samples))
stopifnot(all(scenarios$status == "input_ready"))

cat("PHU_YEN_MOCK model-input QA output tests passed\n")
