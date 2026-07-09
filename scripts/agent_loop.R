# ============================================================
# Controlled file-based agent loop for Regression Kriging runs.
# No LLM/API is called here. External AI can drop ai_decision.json files,
# or the loop can use a conservative local heuristic when enabled.
# ============================================================

source("scripts/agent_utils.R")

agent_parse_args <- function(args) {
  out <- list()
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (startsWith(key, "--")) {
      nm <- sub("^--", "", key)
      val <- TRUE
      if (i + 1L <= length(args) && !startsWith(args[[i + 1L]], "--")) {
        val <- args[[i + 1L]]
        i <- i + 1L
      }
      out[[nm]] <- val
    }
    i <- i + 1L
  }
  out
}

as_bool <- function(x, default = FALSE) {
  if (is.null(x)) return(default)
  if (is.logical(x)) return(isTRUE(x))
  tolower(as.character(x)[1]) %in% c("true", "1", "yes", "y")
}

as_num <- function(x, default = NA_real_) {
  y <- suppressWarnings(as.numeric(x %||% default))
  if (length(y) == 0 || !is.finite(y[1])) default else y[1]
}

merge_request_parameters <- function(request, accepted_parameters) {
  request$parameters <- agent_merge_lists(request$parameters %||% list(), accepted_parameters %||% list())
  request
}

make_iteration_request <- function(base_request, target_field, run_id, max_iterations, accepted_parameters = list(), output_root = NULL) {
  req <- merge_request_parameters(base_request, accepted_parameters)
  req$run_id <- run_id
  req$target_field <- target_field
  if (!is.null(output_root) && nzchar(output_root)) req$output_root <- output_root
  req$output_root <- req$output_root %||% "output/agent_runs"
  req$safety_limits <- agent_merge_lists(req$safety_limits %||% list(), list(max_iterations = max_iterations, allow_delete_points = FALSE, allow_modify_raw_data = FALSE))
  req
}

result_warning_count <- function(result) length(result$warnings %||% character(0))

result_has_severe_warning <- function(result) {
  txt <- paste(result$warnings %||% character(0), collapse = " ")
  grepl("R²_pred âm|R2_pred am|range.*max|Range hits maximum|Nugget/Sill is high|không tìm được candidate|No valid variogram|in-sample", txt, ignore.case = TRUE)
}

should_accept_result <- function(result) {
  grade <- result$quality$final_grade %||% NA_character_
  hint <- result$quality$decision_hint %||% NA_character_
  r2 <- as_num(result$metrics$rk_r2_pred)
  grade %in% c("A", "B") && identical(hint, "ACCEPTABLE") && is.finite(r2) && r2 > 0 && !result_has_severe_warning(result)
}

heuristic_decision <- function(result, request, iter_index, max_more_iterations = 1L) {
  p <- request$parameters %||% list()
  safety <- agent_merge_lists(agent_default_safety_limits(), request$safety_limits %||% list())
  vg <- result$variogram %||% list()
  kr <- result$kriging %||% list()
  warnings_text <- paste(result$warnings %||% character(0), collapse = " ")

  current_range <- as_num(p$MANUAL_RANGE %||% vg$range, 4000)
  current_range_max <- as_num(p$VARIOGRAM_RANGE_MAX, safety$max_range)
  current_radius <- as_num(kr$selected_search_radius %||% p$SEARCH_RADIUS, p$SEARCH_RADIUS %||% 12000)
  current_nmax <- as_num(kr$selected_nmax_neighbors %||% p$NMAX_NEIGHBORS, p$NMAX_NEIGHBORS %||% 12)
  nug_ratio <- as_num(vg$nugget_sill_ratio)
  r2 <- as_num(result$metrics$rk_r2_pred)

  next_params <- list()
  range_problem <- isTRUE(vg$range_hit_max) || grepl("range|cutoff|candidate|variogram", warnings_text, ignore.case = TRUE)
  missing_problem <- grepl("thiếu|missing|neighbor|lân cận|SEARCH_RADIUS", warnings_text, ignore.case = TRUE)
  noisy_problem <- grepl("nhiễu|đốm|spot", warnings_text, ignore.case = TRUE)

  if (range_problem) {
    new_range_max <- max(safety$min_range, min(current_range_max * 0.75, safety$max_range))
    new_range <- max(safety$min_range, min(current_range * 0.85, new_range_max * 0.85))
    next_params$VARIOGRAM_MODE <- "manual"
    next_params$VARIOGRAM_MODEL <- if (identical(p$VARIOGRAM_MODEL %||% vg$model %||% "Exp", "Sph")) "Exp" else "Sph"
    next_params$MANUAL_RANGE <- round(new_range)
    next_params$VARIOGRAM_RANGE_MAX <- round(new_range_max)
  }

  if (is.finite(nug_ratio) && nug_ratio > 0.75) {
    next_params$VARIOGRAM_MODE <- "manual"
    next_params$VARIOGRAM_MODEL <- if (identical(p$VARIOGRAM_MODEL %||% vg$model %||% "Exp", "Gau")) "Sph" else "Gau"
  }

  if (missing_problem || noisy_problem || (is.finite(r2) && r2 < 0)) {
    next_params$AUTO_NEIGHBORS <- TRUE
    next_params$SEARCH_RADIUS <- round(min(safety$max_range, max(current_radius * 1.15, current_radius + 1000)))
    next_params$NMAX_NEIGHBORS <- as.integer(min(safety$max_neighbors, max(current_nmax + 4, current_nmax)))
    next_params$CV_METHODS <- c("spatial_kmeans")
  }

  if (length(next_params) == 0) {
    return(list(
      decision = "MANUAL_REVIEW",
      confidence = "medium",
      reason = "The loop could not infer a safe whitelist-only rerun from diagnostics; manual variogram/map review is required.",
      next_parameters = list(),
      must_keep = list(RUN_CROSS_VALIDATION = TRUE, CV_METHODS = c("spatial_kmeans")),
      stop_condition = list(max_more_iterations = max_more_iterations),
      human_review_required = TRUE
    ))
  }

  list(
    decision = "RERUN",
    confidence = "medium",
    reason = paste0("Conservative local heuristic after iteration ", iter_index, ": adjust only whitelisted variogram/neighborhood parameters and keep spatial CV."),
    next_parameters = next_params,
    must_keep = list(RUN_CROSS_VALIDATION = TRUE, CV_METHODS = c("spatial_kmeans")),
    stop_condition = list(accept_if_rmse_improves_percent = 5, accept_if_warnings_reduce = TRUE, max_more_iterations = max_more_iterations),
    human_review_required = FALSE
  )
}

find_external_decision <- function(decisions_dir, target_name, run_id, iter_index) {
  candidates <- c(
    file.path(decisions_dir, sprintf("ai_decision_%s_iter_%03d.json", target_name, iter_index)),
    file.path(decisions_dir, paste0("ai_decision_", run_id, ".json")),
    file.path("agent", "decisions", sprintf("ai_decision_%s_iter_%03d.json", target_name, iter_index)),
    file.path("agent", "decisions", paste0("ai_decision_", run_id, ".json"))
  )
  candidates[file.exists(candidates)][1] %||% NA_character_
}

run_validator <- function(decision_file, request_file, output_file, rscript) {
  status <- system2(rscript, c("scripts/agent_validate_decision.R", "--decision", decision_file, "--request", request_file, "--output", output_file), stdout = TRUE, stderr = TRUE)
  if (!file.exists(output_file)) {
    return(list(status = 99L, output = status, validated = list(valid = FALSE, decision = "MANUAL_REVIEW", warnings = "Validator did not produce output.")))
  }
  list(status = attr(status, "status") %||% 0L, output = status, validated = agent_read_json(output_file))
}

args <- agent_parse_args(commandArgs(trailingOnly = TRUE))
request_template <- args$request %||% "agent/requests/run_request_template.json"
if (!file.exists(request_template)) stop(paste0("Request JSON not found: ", request_template))
base_request <- agent_read_json(request_template)

target_field <- args$target %||% base_request$target_field %||% ""
if (!nzchar(target_field) || identical(target_field, "auto")) {
  source("scripts/00_config.R")
  target_field <- if (!is.null(TARGET_FIELD) && !identical(TARGET_FIELD, "auto")) TARGET_FIELD else "pH"
}

target_name <- agent_safe_name(target_field)
max_iterations <- as.integer(args$max_iterations %||% base_request$safety_limits$max_iterations %||% 3L)
if (!is.finite(max_iterations) || max_iterations < 1L) max_iterations <- 1L
max_iterations <- min(max_iterations, as.integer(base_request$safety_limits$max_iterations %||% max_iterations))
loop_id <- args$loop_id %||% paste0(target_name, "_loop_", format(Sys.time(), "%Y%m%d_%H%M%S"))
output_root <- args$output_root %||% base_request$output_root %||% "output/agent_runs"
decisions_dir <- args$decisions_dir %||% file.path("agent", "decisions", loop_id)
auto_decision <- as_bool(args$auto_decision, FALSE)
dry_run <- as_bool(args$dry_run, FALSE)

rscript <- Sys.which("Rscript")
if (!nzchar(rscript)) stop("Rscript was not found on PATH.")

loop_dir <- file.path("agent", "history", loop_id)
requests_dir <- file.path(loop_dir, "requests")
results_dir <- file.path(loop_dir, "results")
logs_dir <- file.path(loop_dir, "logs")
validated_dir <- file.path(loop_dir, "validated_decisions")
agent_ensure_dir(requests_dir)
agent_ensure_dir(results_dir)
agent_ensure_dir(logs_dir)
agent_ensure_dir(validated_dir)
agent_ensure_dir(decisions_dir)
agent_ensure_dir("agent/responses")

cat("[INFO] Starting controlled agent loop...\n")
cat("[INFO] Loop ID: ", loop_id, "\n", sep = "")
cat("[INFO] Target: ", target_field, "\n", sep = "")
cat("[INFO] Max iterations: ", max_iterations, "\n", sep = "")
cat("[INFO] Auto decision: ", auto_decision, "\n", sep = "")

iteration_rows <- list()
run_results <- list()
accepted_parameters <- list()
stop_reason <- NULL
final_decision <- "MANUAL_REVIEW"
human_review_required <- FALSE
no_improve_streak <- 0L
previous_rmse <- NA_real_
previous_warning_count <- NA_integer_
last_request_file <- NULL
last_result <- NULL

for (iter in seq_len(max_iterations)) {
  run_id <- sprintf("%s_%s_iter_%03d", target_name, loop_id, iter)
  req <- make_iteration_request(base_request, target_field, run_id, max_iterations, accepted_parameters, output_root)
  req_file <- file.path(requests_dir, paste0("run_request_", run_id, ".json"))
  agent_write_json(req, req_file)
  last_request_file <- req_file

  cat("[INFO] Iteration ", iter, ": ", run_id, "\n", sep = "")
  if (dry_run) {
    iteration_rows[[length(iteration_rows) + 1L]] <- data.frame(iteration = iter, run_id = run_id, status = "dry_run", rmse = NA_real_, r2_pred = NA_real_, warnings = 0L, decision = "DRY_RUN", request = agent_norm_path(req_file), result_file = NA_character_, stringsAsFactors = FALSE)
    stop_reason <- "DRY_RUN_ONLY"
    final_decision <- "DRY_RUN"
    break
  }

  run_log <- file.path(logs_dir, paste0("agent_run_", run_id, ".log"))
  status <- system2(rscript, c("scripts/agent_run.R", "--request", req_file, "--target", target_field), stdout = run_log, stderr = run_log)
  response_file <- file.path("agent", "responses", paste0(run_id, "_run_result.json"))
  if (!file.exists(response_file)) {
    stop_reason <- paste0("RUN_FAILED_NO_RESULT: expected ", agent_norm_path(response_file))
    final_decision <- "MANUAL_REVIEW"
    human_review_required <- TRUE
    iteration_rows[[length(iteration_rows) + 1L]] <- data.frame(iteration = iter, run_id = run_id, status = "failed", rmse = NA_real_, r2_pred = NA_real_, warnings = NA_integer_, decision = final_decision, request = agent_norm_path(req_file), result_file = NA_character_, stringsAsFactors = FALSE)
    break
  }

  result <- agent_read_json(response_file)
  result$.response_file <- agent_norm_path(response_file)
  result$.loop_result_file <- agent_norm_path(file.path(results_dir, paste0(run_id, "_run_result.json")))
  agent_write_json(result, file.path(results_dir, paste0(run_id, "_run_result.json")))
  run_results[[length(run_results) + 1L]] <- result
  last_result <- result

  rmse <- as_num(result$metrics$rk_rmse)
  r2 <- as_num(result$metrics$rk_r2_pred)
  warn_n <- result_warning_count(result)
  decision_for_row <- result$quality$decision_hint %||% NA_character_

  if (should_accept_result(result)) {
    stop_reason <- "ACCEPTABLE_RESULT"
    final_decision <- "FINAL_ACCEPT"
    human_review_required <- FALSE
  } else if (iter >= max_iterations) {
    stop_reason <- "MAX_ITERATIONS_REACHED"
    final_decision <- "MANUAL_REVIEW"
    human_review_required <- TRUE
  }

  if (is.null(stop_reason) && is.finite(previous_rmse) && is.finite(rmse)) {
    improvement <- (previous_rmse - rmse) / max(previous_rmse, 1e-9) * 100
    warnings_reduced <- is.finite(previous_warning_count) && warn_n < previous_warning_count
    if (improvement < 3 && !warnings_reduced) no_improve_streak <- no_improve_streak + 1L else no_improve_streak <- 0L
    if (no_improve_streak >= 2L) {
      stop_reason <- "NO_MEANINGFUL_IMPROVEMENT"
      final_decision <- "MANUAL_REVIEW"
      human_review_required <- TRUE
    }
  }
  previous_rmse <- rmse
  previous_warning_count <- warn_n

  if (!is.null(stop_reason)) {
    iteration_rows[[length(iteration_rows) + 1L]] <- data.frame(iteration = iter, run_id = run_id, status = result$status %||% "unknown", rmse = rmse, r2_pred = r2, warnings = warn_n, decision = final_decision, request = agent_norm_path(req_file), result_file = agent_norm_path(response_file), stringsAsFactors = FALSE)
    break
  }

  decision_file <- find_external_decision(decisions_dir, target_name, run_id, iter)
  if (is.na(decision_file) && auto_decision) {
    decision_obj <- heuristic_decision(result, req, iter, max_iterations - iter)
    decision_file <- file.path(decisions_dir, sprintf("ai_decision_%s_iter_%03d.json", target_name, iter))
    agent_write_json(decision_obj, decision_file)
  }

  if (is.na(decision_file)) {
    need_file <- file.path(decisions_dir, sprintf("ai_decision_%s_iter_%03d_needed.json", target_name, iter))
    agent_write_json(list(
      status = "WAITING_FOR_AI_DECISION",
      loop_id = loop_id,
      target_field = target_field,
      iteration = iter,
      run_id = run_id,
      run_result_json = agent_norm_path(response_file),
      expected_decision_files = c(
        agent_norm_path(file.path(decisions_dir, sprintf("ai_decision_%s_iter_%03d.json", target_name, iter))),
        agent_norm_path(file.path("agent", "decisions", sprintf("ai_decision_%s_iter_%03d.json", target_name, iter)))
      ),
      whitelist_parameters = agent_allowed_parameters(),
      protected_parameters = agent_protected_parameters()
    ), need_file)
    stop_reason <- "WAITING_FOR_AI_DECISION"
    final_decision <- "MANUAL_REVIEW"
    human_review_required <- TRUE
    iteration_rows[[length(iteration_rows) + 1L]] <- data.frame(iteration = iter, run_id = run_id, status = result$status %||% "unknown", rmse = rmse, r2_pred = r2, warnings = warn_n, decision = stop_reason, request = agent_norm_path(req_file), result_file = agent_norm_path(response_file), stringsAsFactors = FALSE)
    break
  }

  validated_file <- file.path(validated_dir, paste0("validated_decision_iter_", sprintf("%03d", iter), ".json"))
  validation <- run_validator(decision_file, req_file, validated_file, rscript)
  validated <- validation$validated
  if (!isTRUE(validated$valid)) {
    stop_reason <- "VALIDATOR_REJECTED_DECISION"
    final_decision <- "MANUAL_REVIEW"
    human_review_required <- TRUE
    iteration_rows[[length(iteration_rows) + 1L]] <- data.frame(iteration = iter, run_id = run_id, status = result$status %||% "unknown", rmse = rmse, r2_pred = r2, warnings = warn_n, decision = stop_reason, request = agent_norm_path(req_file), result_file = agent_norm_path(response_file), stringsAsFactors = FALSE)
    break
  }

  if (identical(validated$decision, "ACCEPT")) {
    stop_reason <- "AI_ACCEPTED_RESULT"
    final_decision <- "FINAL_ACCEPT"
    human_review_required <- FALSE
    iteration_rows[[length(iteration_rows) + 1L]] <- data.frame(iteration = iter, run_id = run_id, status = result$status %||% "unknown", rmse = rmse, r2_pred = r2, warnings = warn_n, decision = stop_reason, request = agent_norm_path(req_file), result_file = agent_norm_path(response_file), stringsAsFactors = FALSE)
    break
  }
  if (validated$decision %in% c("MANUAL_REVIEW", "REJECT")) {
    stop_reason <- paste0("AI_", validated$decision)
    final_decision <- if (identical(validated$decision, "REJECT")) "REJECT" else "MANUAL_REVIEW"
    human_review_required <- TRUE
    iteration_rows[[length(iteration_rows) + 1L]] <- data.frame(iteration = iter, run_id = run_id, status = result$status %||% "unknown", rmse = rmse, r2_pred = r2, warnings = warn_n, decision = stop_reason, request = agent_norm_path(req_file), result_file = agent_norm_path(response_file), stringsAsFactors = FALSE)
    break
  }

  accepted_parameters <- validated$accepted_parameters %||% list()
  decision_for_row <- "RERUN_VALIDATED"
  iteration_rows[[length(iteration_rows) + 1L]] <- data.frame(iteration = iter, run_id = run_id, status = result$status %||% "unknown", rmse = rmse, r2_pred = r2, warnings = warn_n, decision = decision_for_row, request = agent_norm_path(req_file), result_file = agent_norm_path(response_file), stringsAsFactors = FALSE)
}

if (is.null(stop_reason)) {
  stop_reason <- "LOOP_ENDED"
  final_decision <- "MANUAL_REVIEW"
  human_review_required <- TRUE
}

iteration_table <- if (length(iteration_rows) > 0) do.call(rbind, iteration_rows) else data.frame()
iteration_csv <- file.path(loop_dir, "iteration_summary.csv")
agent_write_csv(iteration_table, iteration_csv)

comparison_file <- NULL
comparison <- NULL
if (!dry_run && length(run_results) > 0) {
  comparison_file <- file.path(loop_dir, "run_comparison.json")
  compare_log <- system2(rscript, c("scripts/agent_compare_runs.R", "--results", results_dir, "--target", target_field, "--include_output", "false", "--output", comparison_file), stdout = TRUE, stderr = TRUE)
  if (file.exists(comparison_file)) comparison <- agent_read_json(comparison_file)
}

selected_run_id <- comparison$selected_run_id %||% last_result$run_id %||% NA_character_
selected_files <- comparison$selected_files %||% last_result$files %||% list()
reason <- paste0("Loop stopped because: ", stop_reason, ".")
if (!is.null(comparison$reason)) reason <- paste(reason, comparison$reason)

final <- list(
  target_field = target_field,
  loop_id = loop_id,
  selected_run_id = selected_run_id,
  decision = final_decision,
  reason = reason,
  stop_reason = stop_reason,
  iterations_run = nrow(iteration_table),
  max_iterations = max_iterations,
  auto_decision = auto_decision,
  human_review_required = human_review_required,
  iteration_summary_csv = agent_norm_path(iteration_csv),
  comparison_json = if (!is.null(comparison_file) && file.exists(comparison_file)) agent_norm_path(comparison_file) else NULL,
  why_not_lowest_rmse = comparison$why_not_lowest_rmse %||% NULL,
  selected_outputs = selected_files,
  loop_history_dir = agent_norm_path(loop_dir),
  decisions_dir = agent_norm_path(decisions_dir)
)

final_file <- file.path("agent", "responses", paste0("final_decision_", target_name, "_", loop_id, ".json"))
history_final_file <- file.path(loop_dir, "final_decision.json")
agent_write_json(final, final_file)
agent_write_json(final, history_final_file)

cat("[INFO] Agent loop finished.\n")
cat("[INFO] Stop reason: ", stop_reason, "\n", sep = "")
cat("[INFO] Final decision JSON: ", agent_norm_path(final_file), "\n", sep = "")
if (!is.null(comparison_file) && file.exists(comparison_file)) cat("[INFO] Comparison JSON: ", agent_norm_path(comparison_file), "\n", sep = "")
if (identical(final_decision, "REJECT")) quit(status = 3L)
if (identical(stop_reason, "VALIDATOR_REJECTED_DECISION")) quit(status = 2L)