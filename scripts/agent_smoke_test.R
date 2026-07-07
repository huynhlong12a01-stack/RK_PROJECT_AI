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

# 5. Test compare two fake run_result.json files.
fake_dir <- file.path(bad_dir, "fake_results")
agent_ensure_dir(fake_dir)
fake_low_rmse_bad <- list(run_id = "fake_low_rmse_bad", target_field = "pH", status = "completed", quality = list(final_grade = "B", final_score = 75), metrics = list(rk_rmse = 0.30, rk_mae = 0.20, rk_me = 0.15, rk_r2_pred = -0.10, nrmse_mean = 0.05, rpd = 1.7), model_comparison = list(regression_rmse = 0.31, ordinary_kriging_rmse = 0.29, regression_kriging_rmse = 0.30), variogram = list(nugget_sill_ratio = 0.90, range = 8000, range_hit_max = TRUE), warnings = c("Range hits maximum", "R2 negative"), files = list())
fake_good <- list(run_id = "fake_good", target_field = "pH", status = "completed", quality = list(final_grade = "B", final_score = 74), metrics = list(rk_rmse = 0.32, rk_mae = 0.21, rk_me = 0.01, rk_r2_pred = 0.25, nrmse_mean = 0.06, rpd = 1.6), model_comparison = list(regression_rmse = 0.40, ordinary_kriging_rmse = 0.33, regression_kriging_rmse = 0.32), variogram = list(nugget_sill_ratio = 0.20, range = 3500, range_hit_max = FALSE), warnings = character(0), files = list())
agent_write_json(fake_low_rmse_bad, file.path(fake_dir, "fake_low_rmse_bad_run_result.json"))
agent_write_json(fake_good, file.path(fake_dir, "fake_good_run_result.json"))
compare_out <- file.path(bad_dir, "fake_compare.json")
status <- system2(Sys.which("Rscript"), c("scripts/agent_compare_runs.R", "--results", fake_dir, "--include_output", "false", "--output", compare_out), stdout = TRUE, stderr = TRUE)
if (!file.exists(compare_out)) fail("compare runs did not produce output")
comparison <- agent_read_json(compare_out)
if (!identical(comparison$selected_run_id, "fake_good")) fail("compare runs selected lowest RMSE despite bad diagnostics")
ok("compared fake runs without choosing lowest RMSE blindly")

# 6. Test README command examples are syntactically plausible.
if (!file.exists("README.md") || !file.exists("AGENT_README.md")) fail("README files are missing")
readme <- paste(readLines("README.md", warn = FALSE), collapse = "\n")
agent_readme <- paste(readLines("AGENT_README.md", warn = FALSE), collapse = "\n")
if (!grepl("run_rk.bat", readme, fixed = TRUE) || !grepl("run_agent.ps1", readme, fixed = TRUE)) fail("README command examples are missing")
if (!grepl("agent_validate_decision.R", agent_readme, fixed = TRUE) || !grepl("agent_compare_runs.R", agent_readme, fixed = TRUE)) fail("AGENT_README command examples are missing")
ok("README command examples are present")

cat("[OK] Agent smoke test completed.\n")