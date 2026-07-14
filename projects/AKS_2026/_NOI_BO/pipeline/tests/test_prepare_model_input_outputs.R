suppressPackageStartupMessages({
  library(readr)
  library(jsonlite)
})

base <- "projects/AKS_2026"
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

stopifnot(summary$product_status == "WAITING_LAB")
stopifnot(!isTRUE(summary$classification_created))
stopifnot(!isTRUE(summary$fertilizer_recommendation_created))
stopifnot(nrow(metadata) == 17L)
stopifnot(all(metadata$metadata_entry_exists))
stopifnot(!any(metadata$has_results))
stopifnot(all(metadata$product_status == "WAITING_LAB"))
stopifnot(setequal(
  scenarios$scenario_id,
  c("REVIEW_FILTERED_PRIMARY", "ALL_ACTUAL_AUDIT", "INSIDE_ROI_ONLY", "ELIGIBLE_AFTER_TARGET_SUPPORT_REVIEW")
))
stopifnot(scenarios$n_samples[scenarios$scenario_id == "REVIEW_FILTERED_PRIMARY"] == 94L)
stopifnot(scenarios$n_samples[scenarios$scenario_id == "ALL_ACTUAL_AUDIT"] == 94L)
stopifnot(scenarios$n_samples[scenarios$scenario_id == "INSIDE_ROI_ONLY"] == 72L)
stopifnot(scenarios$n_samples[scenarios$scenario_id == "ELIGIBLE_AFTER_TARGET_SUPPORT_REVIEW"] == 72L)
stopifnot(all(scenarios$status == "pending_lab_results"))
stopifnot(summary$outside_review_status == "pending_manual_confirmation")
stopifnot(summary$n_pending_outside_review == 22L)
stopifnot(summary$n_explicitly_excluded_outside == 0L)
stopifnot(summary$n_samples_primary == 94L)
stopifnot(summary$aoa_status == "pending_model_fit_model_dependent")
stopifnot(summary$final_map_domain == "original_roi_only")

cat("model-input QA output tests passed\n")
