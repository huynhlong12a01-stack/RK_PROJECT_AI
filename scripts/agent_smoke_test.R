# ============================================================
# Lightweight smoke tests for the agent-ready RK workflow.
# Does not run the full raster RK engine.
# ============================================================

source("scripts/agent_utils.R")

ok <- function(label) cat("[OK] ", label, "\n", sep = "")
fail <- function(label) stop(paste0("[FAIL] ", label), call. = FALSE)

# 1. Test load run_request.json.
req <- agent_read_json("agent/requests/run_request_template.json")
if (is.null(req$run_id) || is.null(req$parameters)) fail("run_request_template.json did not load correctly")
ok("loaded run_request_template.json")

# 2. Test validate ai_decision.json.
valid_out <- "agent/decisions/validated_decision_smoke.json"
status <- system2(Sys.which("Rscript"), c("scripts/agent_validate_decision.R", "--decision", "agent/decisions/ai_decision_template.json", "--request", "agent/requests/run_request_template.json", "--output", valid_out), stdout = TRUE, stderr = TRUE)
if (!file.exists(valid_out)) fail("validator did not produce output for valid decision")
validated <- agent_read_json(valid_out)
if (!isTRUE(validated$valid) || validated$decision != "RERUN") fail("valid decision was not accepted")
ok("validated a good ai_decision.json")

# 3. Test reject non-whitelisted parameter.
bad_dir <- "agent/history/smoke_test"
agent_ensure_dir(bad_dir)
bad_decision <- req
bad_decision <- list(decision = "RERUN", confidence = "medium", reason = "test", next_parameters = list(POINT_FILE = "input/points/other.csv"), must_keep = list(RUN_CROSS_VALIDATION = TRUE), human_review_required = FALSE)
bad_file <- file.path(bad_dir, "bad_protected_decision.json")
bad_out <- file.path(bad_dir, "bad_protected_validated.json")
agent_write_json(bad_decision, bad_file)
status <- suppressWarnings(system2(Sys.which("Rscript"), c("scripts/agent_validate_decision.R", "--decision", bad_file, "--request", "agent/requests/run_request_template.json", "--output", bad_out), stdout = TRUE, stderr = TRUE))
if (!file.exists(bad_out)) fail("validator did not produce output for protected parameter")
bad_validated <- agent_read_json(bad_out)
if (isTRUE(bad_validated$valid) || !("POINT_FILE" %in% names(bad_validated$rejected_parameters))) fail("protected parameter was not rejected")
ok("rejected protected/non-whitelisted parameter")

# 4. Test reject out-of-range parameter.
bad_range <- list(decision = "RERUN", confidence = "medium", reason = "test", next_parameters = list(MANUAL_RANGE = 999999), must_keep = list(RUN_CROSS_VALIDATION = TRUE), human_review_required = FALSE)
bad_range_file <- file.path(bad_dir, "bad_range_decision.json")
bad_range_out <- file.path(bad_dir, "bad_range_validated.json")
agent_write_json(bad_range, bad_range_file)
status <- suppressWarnings(system2(Sys.which("Rscript"), c("scripts/agent_validate_decision.R", "--decision", bad_range_file, "--request", "agent/requests/run_request_template.json", "--output", bad_range_out), stdout = TRUE, stderr = TRUE))
bad_range_validated <- agent_read_json(bad_range_out)
if (isTRUE(bad_range_validated$valid) || !("MANUAL_RANGE" %in% names(bad_range_validated$rejected_parameters))) fail("out-of-range MANUAL_RANGE was not rejected")
ok("rejected out-of-range parameter")

# 5. Test TARGET_TRANSFORM is accepted when valid and rejected when invalid.
transform_decision <- list(decision = "RERUN", confidence = "medium", reason = "test transform", next_parameters = list(TARGET_TRANSFORM = "log1p"), must_keep = list(RUN_CROSS_VALIDATION = TRUE), human_review_required = FALSE)
transform_file <- file.path(bad_dir, "transform_decision.json")
transform_out <- file.path(bad_dir, "transform_validated.json")
agent_write_json(transform_decision, transform_file)
status <- system2(Sys.which("Rscript"), c("scripts/agent_validate_decision.R", "--decision", transform_file, "--request", "agent/requests/run_request_template.json", "--output", transform_out), stdout = TRUE, stderr = TRUE)
transform_validated <- agent_read_json(transform_out)
if (!isTRUE(transform_validated$valid) || !identical(transform_validated$accepted_parameters$TARGET_TRANSFORM, "log1p")) fail("valid TARGET_TRANSFORM was not accepted")
invalid_transform <- list(decision = "RERUN", confidence = "medium", reason = "test transform", next_parameters = list(TARGET_TRANSFORM = "sqrt"), must_keep = list(RUN_CROSS_VALIDATION = TRUE), human_review_required = FALSE)
invalid_transform_file <- file.path(bad_dir, "invalid_transform_decision.json")
invalid_transform_out <- file.path(bad_dir, "invalid_transform_validated.json")
agent_write_json(invalid_transform, invalid_transform_file)
status <- suppressWarnings(system2(Sys.which("Rscript"), c("scripts/agent_validate_decision.R", "--decision", invalid_transform_file, "--request", "agent/requests/run_request_template.json", "--output", invalid_transform_out), stdout = TRUE, stderr = TRUE))
invalid_transform_validated <- agent_read_json(invalid_transform_out)
if (isTRUE(invalid_transform_validated$valid) || !("TARGET_TRANSFORM" %in% names(invalid_transform_validated$rejected_parameters))) fail("invalid TARGET_TRANSFORM was not rejected")
ok("validated TARGET_TRANSFORM parameter")

# 6. Test LOG_BACKTRANSFORM_BIAS_CORRECTION is accepted only as boolean.
bias_decision <- list(decision = "RERUN", confidence = "medium", reason = "test log bias correction", next_parameters = list(LOG_BACKTRANSFORM_BIAS_CORRECTION = TRUE), must_keep = list(RUN_CROSS_VALIDATION = TRUE), human_review_required = FALSE)
bias_file <- file.path(bad_dir, "bias_correction_decision.json")
bias_out <- file.path(bad_dir, "bias_correction_validated.json")
agent_write_json(bias_decision, bias_file)
status <- system2(Sys.which("Rscript"), c("scripts/agent_validate_decision.R", "--decision", bias_file, "--request", "agent/requests/run_request_template.json", "--output", bias_out), stdout = TRUE, stderr = TRUE)
bias_validated <- agent_read_json(bias_out)
if (!isTRUE(bias_validated$valid) || !isTRUE(bias_validated$accepted_parameters$LOG_BACKTRANSFORM_BIAS_CORRECTION)) fail("valid LOG_BACKTRANSFORM_BIAS_CORRECTION was not accepted")
invalid_bias <- list(decision = "RERUN", confidence = "medium", reason = "test log bias correction", next_parameters = list(LOG_BACKTRANSFORM_BIAS_CORRECTION = "yes"), must_keep = list(RUN_CROSS_VALIDATION = TRUE), human_review_required = FALSE)
invalid_bias_file <- file.path(bad_dir, "invalid_bias_correction_decision.json")
invalid_bias_out <- file.path(bad_dir, "invalid_bias_correction_validated.json")
agent_write_json(invalid_bias, invalid_bias_file)
status <- suppressWarnings(system2(Sys.which("Rscript"), c("scripts/agent_validate_decision.R", "--decision", invalid_bias_file, "--request", "agent/requests/run_request_template.json", "--output", invalid_bias_out), stdout = TRUE, stderr = TRUE))
invalid_bias_validated <- agent_read_json(invalid_bias_out)
if (isTRUE(invalid_bias_validated$valid) || !("LOG_BACKTRANSFORM_BIAS_CORRECTION" %in% names(invalid_bias_validated$rejected_parameters))) fail("invalid LOG_BACKTRANSFORM_BIAS_CORRECTION was not rejected")
ok("validated LOG_BACKTRANSFORM_BIAS_CORRECTION parameter")
# 7. Test compare two fake run_result.json files.
fake_dir <- file.path(bad_dir, "fake_results")
agent_ensure_dir(fake_dir)
fake_low_rmse_bad <- list(run_id = "fake_low_rmse_bad", target_field = "pH", status = "completed", quality = list(final_grade = "B", final_score = 75), metrics = list(rk_rmse = 0.30, rk_mae = 0.20, rk_me = 0.15, rk_r2_pred = -0.10, nrmse_mean = 0.05, rpd = 1.7), model_comparison = list(regression_rmse = 0.31, ordinary_kriging_rmse = 0.29, regression_kriging_rmse = 0.30), variogram = list(nugget_sill_ratio = 0.90, range = 8000, range_hit_max = TRUE, singular = FALSE), cross_validation = list(strict_outer_cv = TRUE, outer_repeats = 5, stability = list(rk_better_than_regression_fraction = 0.2)), hard_failures = c("Range hits maximum"), warnings = c("Range hits maximum", "R2 negative"), files = list())
fake_good <- list(run_id = "fake_good", target_field = "pH", status = "completed", quality = list(final_grade = "B", final_score = 74), metrics = list(rk_rmse = 0.32, rk_mae = 0.21, rk_me = 0.01, rk_r2_pred = 0.25, nrmse_mean = 0.06, rpd = 1.6), model_comparison = list(regression_rmse = 0.40, ordinary_kriging_rmse = 0.33, regression_kriging_rmse = 0.32), variogram = list(nugget_sill_ratio = 0.20, range = 3500, range_hit_max = FALSE, singular = FALSE), cross_validation = list(strict_outer_cv = TRUE, outer_repeats = 5, stability = list(rk_better_than_regression_fraction = 0.9)), hard_failures = character(0), warnings = character(0), files = list())
agent_write_json(fake_low_rmse_bad, file.path(fake_dir, "fake_low_rmse_bad_run_result.json"))
agent_write_json(fake_good, file.path(fake_dir, "fake_good_run_result.json"))
compare_out <- file.path(bad_dir, "fake_compare.json")
status <- system2(Sys.which("Rscript"), c("scripts/agent_compare_runs.R", "--results", fake_dir, "--include_output", "false", "--output", compare_out), stdout = TRUE, stderr = TRUE)
if (!file.exists(compare_out)) fail("compare runs did not produce output")
comparison <- agent_read_json(compare_out)
if (!identical(comparison$selected_run_id, "fake_good")) fail("compare runs selected lowest RMSE despite bad diagnostics")
ok("compared fake runs without choosing lowest RMSE blindly")

pure_nugget_result <- fake_good
pure_nugget_result$prediction_method <-
  "regression_only_pure_nugget_fallback"
pure_nugget_result$variogram$model <- "Nug"
pure_nugget_result$variogram$nugget_sill_ratio <- 1
pure_nugget_result$hard_failures <-
  "Residual variogram is pure nugget."
pure_nugget_result$uncertainty <- list(
  available = FALSE, calibrated = FALSE, used_in_grade = FALSE)
if (!identical(
    agent_decision_hint(pure_nugget_result),
    "MANUAL_REVIEW_REQUIRED")) {
  fail("pure-nugget regression fallback was not blocked from ACCEPT")
}
ok("blocked pure-nugget regression fallback from ACCEPT")

# 8. Test compare uses only approved class accuracy; residual q80 uncertainty is informational.
fake_class_dir <- file.path(bad_dir, "fake_class_uncertainty_results")
agent_ensure_dir(fake_class_dir)
fake_low_rmse_class_bad <- list(
  run_id = "fake_low_rmse_class_bad", target_field = "P", status = "completed",
  quality = list(final_grade = "B", final_score = 78),
  metrics = list(rk_rmse = 0.25, rk_mae = 0.18, rk_me = 0.00, rk_r2_pred = 0.40, nrmse_mean = 0.08, rpd = 1.8),
  model_comparison = list(regression_rmse = 0.40, ordinary_kriging_rmse = 0.28, regression_kriging_rmse = 0.25),
  variogram = list(nugget_sill_ratio = 0.20, range = 3500, range_hit_max = FALSE, singular = FALSE),
  cross_validation = list(strict_outer_cv = TRUE, outer_repeats = 5, stability = list(rk_better_than_regression_fraction = 0.9)),
  hard_failures = character(0),
  class_evaluation = list(enabled = TRUE, approved = TRUE, class_accuracy = 0.35, within_one_class_rate = 0.65, severe_misclassification_rate = 0.25),
  uncertainty = list(available = TRUE, calibrated = FALSE, used_in_grade = FALSE, mean_sd = 0.12, high_uncertainty_area_percent = 65),
  warnings = c("Class accuracy is low", "High uncertainty area is large"), files = list()
)
fake_higher_rmse_class_good <- list(
  run_id = "fake_higher_rmse_class_good", target_field = "P", status = "completed",
  quality = list(final_grade = "B", final_score = 76),
  metrics = list(rk_rmse = 0.29, rk_mae = 0.19, rk_me = 0.01, rk_r2_pred = 0.35, nrmse_mean = 0.09, rpd = 1.7),
  model_comparison = list(regression_rmse = 0.40, ordinary_kriging_rmse = 0.30, regression_kriging_rmse = 0.29),
  variogram = list(nugget_sill_ratio = 0.22, range = 3400, range_hit_max = FALSE, singular = FALSE),
  cross_validation = list(strict_outer_cv = TRUE, outer_repeats = 5, stability = list(rk_better_than_regression_fraction = 0.9)),
  hard_failures = character(0),
  class_evaluation = list(enabled = TRUE, approved = TRUE, class_accuracy = 0.78, within_one_class_rate = 0.93, severe_misclassification_rate = 0.02),
  uncertainty = list(available = TRUE, calibrated = FALSE, used_in_grade = FALSE, mean_sd = 0.10, high_uncertainty_area_percent = 10),
  warnings = character(0), files = list()
)
agent_write_json(fake_low_rmse_class_bad, file.path(fake_class_dir, "fake_low_rmse_class_bad_run_result.json"))
agent_write_json(fake_higher_rmse_class_good, file.path(fake_class_dir, "fake_higher_rmse_class_good_run_result.json"))
class_compare_out <- file.path(bad_dir, "fake_class_uncertainty_compare.json")
status <- system2(Sys.which("Rscript"), c("scripts/agent_compare_runs.R", "--results", fake_class_dir, "--include_output", "false", "--output", class_compare_out), stdout = TRUE, stderr = TRUE)
if (!file.exists(class_compare_out)) fail("compare runs did not produce class/uncertainty output")
class_comparison <- agent_read_json(class_compare_out)
if (!identical(class_comparison$selected_run_id, "fake_higher_rmse_class_good")) fail("compare runs ignored class accuracy/uncertainty penalties")
ok("compared fake runs with approved class accuracy and informational residual uncertainty")
# 9. Test README command examples are syntactically plausible.
if (!file.exists("README.md") || !file.exists("AGENT_README.md")) fail("README files are missing")
readme <- paste(readLines("README.md", warn = FALSE), collapse = "\n")
agent_readme <- paste(readLines("AGENT_README.md", warn = FALSE), collapse = "\n")
if (!grepl("CREATE_NEW_PROJECT.bat", readme, fixed = TRUE) ||
    !grepl("projects/TEN_DU_AN/README.md", readme, fixed = TRUE)) {
  fail("README project-workflow examples are missing")
}
if (!grepl("projects/TEN_DU_AN/RUN.ps1 design", agent_readme, fixed = TRUE) ||
    !grepl("projects/TEN_DU_AN/RUN.ps1 status", agent_readme, fixed = TRUE)) fail("AGENT_README command examples are missing")
ok("README command examples are present")

cat("[OK] Agent smoke test completed.\n")