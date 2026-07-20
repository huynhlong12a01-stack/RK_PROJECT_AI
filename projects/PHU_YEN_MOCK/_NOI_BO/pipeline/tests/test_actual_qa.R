suppressPackageStartupMessages(library(readr))
source("projects/PHU_YEN_MOCK/_NOI_BO/pipeline/actual_qa_utils.R")

codes <- c("A", "B", "V2_002")
assessment <- actual_read_assessment("path/that/does/not/exist.csv", codes)
stopifnot(all(assessment$target_population_status == "pending_manual_confirmation"))
stopifnot(all(assessment$sampling_support_status == "pending_manual_confirmation"))

assessment$planned_point_id[2] <- "V2_001"
links <- actual_resolve_plan_link(codes, assessment, c("V2_001", "V2_002"))
stopifnot(links$planned_link_status[1] == "unavailable_no_identifier")
stopifnot(is.na(links$planned_point_id[1]))
stopifnot(links$planned_link_status[2] == "matched_declared_planned_id")
stopifnot(links$planned_point_id[2] == "V2_001")
stopifnot(links$planned_link_status[3] == "matched_exact_code")

assessment$planned_point_id[1] <- "NOT_A_PLAN_ID"
links <- actual_resolve_plan_link(codes, assessment, c("V2_001", "V2_002"))
stopifnot(links$planned_link_status[1] == "invalid_declared_planned_id")
stopifnot(is.na(links$planned_point_id[1]))

review_path <- tempfile(fileext = ".csv")
readr::write_csv(data.frame(
  code = "A", planned_point_id = "V2_001",
  target_population_in_scope = "true",
  sampling_support_compatible = "true",
  relocation_reason = "user_recorded_reason",
  include_in_model_development = "true",
  reviewer = "tester", review_date = "2026-07-13", review_note = "keep",
  stringsAsFactors = FALSE
), review_path, na = "")
synced <- actual_sync_review_file(review_path, c("A", "B"), "default_reason")
stopifnot(synced$relocation_reason[synced$code == "A"] == "user_recorded_reason")
stopifnot(synced$reviewer[synced$code == "A"] == "tester")
stopifnot(synced$relocation_reason[synced$code == "B"] == "default_reason")
synced$target_population_in_scope[synced$code == "B"] <- "false"
readr::write_csv(synced, review_path, na = "")
resynced <- actual_sync_review_file(review_path, "B", "different_default")
stopifnot(nrow(resynced) == 1L, resynced$code == "B")
stopifnot(resynced$target_population_in_scope == "false")
stopifnot(resynced$relocation_reason == "default_reason")
unlink(review_path)
cat("actual QA utility tests passed\n")
