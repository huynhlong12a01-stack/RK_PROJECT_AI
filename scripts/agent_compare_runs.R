# ============================================================
# Compare multiple agent run_result.json files and select a defensible final run.
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

as_num <- function(x) suppressWarnings(as.numeric(x %||% NA_real_))
score_run <- function(r) {
  m <- r$metrics %||% list()
  vg <- r$variogram %||% list()
  cmp <- r$model_comparison %||% list()
  warnings <- r$warnings %||% character(0)
  rmse <- as_num(m$rk_rmse)
  mae <- as_num(m$rk_mae)
  me <- as_num(m$rk_me)
  r2 <- as_num(m$rk_r2_pred)
  nrmse <- as_num(m$nrmse_mean)
  rpd <- as_num(m$rpd)
  nug_ratio <- as_num(vg$nugget_sill_ratio)
  range_hit <- isTRUE(vg$range_hit_max)
  reg_rmse <- as_num(cmp$regression_rmse)
  ok_rmse <- as_num(cmp$ordinary_kriging_rmse)
  rk_rmse <- as_num(cmp$regression_kriging_rmse)
  score <- 50
  reasons <- character(0)
  penalties <- character(0)
  if (is.finite(r2) && r2 > 0) { score <- score + 12; reasons <- c(reasons, "R2_pred is positive.") } else { score <- score - 20; penalties <- c(penalties, "R2_pred is not positive.") }
  if (is.finite(me) && is.finite(rmse) && abs(me) <= 0.15 * max(rmse, 1e-9)) { score <- score + 8; reasons <- c(reasons, "Bias ME is small relative to RMSE.") } else { score <- score - 8; penalties <- c(penalties, "Bias ME is not small relative to RMSE.") }
  if (is.finite(rk_rmse) && is.finite(reg_rmse) && rk_rmse < 0.97 * reg_rmse) { score <- score + 10; reasons <- c(reasons, "RK improves over regression-only.") } else if (is.finite(rk_rmse) && is.finite(reg_rmse)) { score <- score - 8; penalties <- c(penalties, "RK does not clearly improve over regression-only.") }
  if (is.finite(rk_rmse) && is.finite(ok_rmse) && rk_rmse <= 1.03 * ok_rmse) { score <- score + 6; reasons <- c(reasons, "RK is competitive with ordinary kriging.") } else if (is.finite(rk_rmse) && is.finite(ok_rmse)) { score <- score - 8; penalties <- c(penalties, "RK is clearly worse than ordinary kriging.") }
  if (is.finite(nug_ratio) && nug_ratio <= 0.50) { score <- score + 8; reasons <- c(reasons, "Nugget/Sill is good.") } else if (is.finite(nug_ratio) && nug_ratio <= 0.75) { score <- score + 2; reasons <- c(reasons, "Nugget/Sill is acceptable.") } else { score <- score - 12; penalties <- c(penalties, "Nugget/Sill is high.") }
  if (!range_hit) { score <- score + 6; reasons <- c(reasons, "Range does not hit configured maximum.") } else { score <- score - 15; penalties <- c(penalties, "Range hits maximum limit.") }
  if (is.finite(nrmse) && nrmse <= 0.25) score <- score + 5
  if (is.finite(rpd) && rpd >= 1.4) score <- score + 5
  warning_count <- length(warnings)
  score <- score - min(20, warning_count * 2)
  if (warning_count > 0) penalties <- c(penalties, paste0(warning_count, " warning(s) were reported."))
  list(score = max(0, min(100, score)), reasons = reasons, penalties = penalties, rmse = rmse)
}

args <- agent_parse_args(commandArgs(trailingOnly = TRUE))
results_dir <- args$results %||% "agent/responses"
output_path <- args$output %||% "agent/history/run_comparison.json"
summary_csv <- args$csv %||% sub("\\.json$", ".csv", output_path)

files <- character(0)
if (dir.exists(results_dir)) files <- c(files, list.files(results_dir, pattern = "run_result\\.json$|_run_result\\.json$", full.names = TRUE, recursive = TRUE))
include_output <- !identical(tolower(as.character(args$include_output %||% "true")), "false")
if (include_output && dir.exists("output/agent_runs")) files <- c(files, list.files("output/agent_runs", pattern = "run_result\\.json$", full.names = TRUE, recursive = TRUE))
files <- unique(files[file.exists(files)])
if (length(files) == 0) stop("No run_result.json files found.")

runs <- lapply(files, function(f) { x <- agent_read_json(f); x$.source_file <- agent_norm_path(f); x })
run_ids <- vapply(runs, function(r) as.character(r$run_id %||% r$.source_file), character(1))
runs <- runs[!duplicated(run_ids)]
completed <- Filter(function(r) identical(r$status, "completed"), runs)
if (length(completed) == 0) stop("No completed run_result.json files found.")

scored <- lapply(completed, score_run)
scores <- vapply(scored, function(x) x$score, numeric(1))
rmse_vals <- vapply(scored, function(x) x$rmse, numeric(1))
best_idx <- which.max(scores)
lowest_rmse_idx <- if (all(!is.finite(rmse_vals))) NA_integer_ else which.min(ifelse(is.finite(rmse_vals), rmse_vals, Inf))
selected <- completed[[best_idx]]
lowest <- if (is.na(lowest_rmse_idx)) NULL else completed[[lowest_rmse_idx]]
why_not_lowest <- "Selected run is also the lowest-RMSE completed run."
if (!is.null(lowest) && !identical(lowest$run_id, selected$run_id)) {
  low_score <- scored[[lowest_rmse_idx]]
  why_not_lowest <- paste0("Lowest RMSE run ", lowest$run_id, " scored lower scientifically because: ", paste(low_score$penalties, collapse = " "))
}

human_review <- scores[best_idx] < 65 || any(grepl("R2_pred is not positive|Range hits maximum|Nugget/Sill is high", scored[[best_idx]]$penalties))
decision <- if (human_review) "MANUAL_REVIEW" else "FINAL_ACCEPT"
reason <- paste0("Selected ", selected$run_id, " with scientific score ", round(scores[best_idx], 1), "/100. ", paste(c(scored[[best_idx]]$reasons, scored[[best_idx]]$penalties), collapse = " "))

summary <- data.frame(
  run_id = vapply(completed, function(r) r$run_id %||% NA_character_, character(1)),
  status = vapply(completed, function(r) r$status %||% NA_character_, character(1)),
  final_grade = vapply(completed, function(r) as.character(r$quality$final_grade %||% NA_character_), character(1)),
  final_score = vapply(completed, function(r) as_num(r$quality$final_score), numeric(1)),
  scientific_score = scores,
  rk_rmse = vapply(completed, function(r) as_num(r$metrics$rk_rmse), numeric(1)),
  rk_mae = vapply(completed, function(r) as_num(r$metrics$rk_mae), numeric(1)),
  rk_me = vapply(completed, function(r) as_num(r$metrics$rk_me), numeric(1)),
  rk_r2_pred = vapply(completed, function(r) as_num(r$metrics$rk_r2_pred), numeric(1)),
  nrmse_mean = vapply(completed, function(r) as_num(r$metrics$nrmse_mean), numeric(1)),
  rpd = vapply(completed, function(r) as_num(r$metrics$rpd), numeric(1)),
  nugget_sill_ratio = vapply(completed, function(r) as_num(r$variogram$nugget_sill_ratio), numeric(1)),
  variogram_range = vapply(completed, function(r) as_num(r$variogram$range), numeric(1)),
  range_hit_max = vapply(completed, function(r) isTRUE(r$variogram$range_hit_max), logical(1)),
  n_warnings = vapply(completed, function(r) length(r$warnings %||% character(0)), integer(1)),
  source_file = vapply(completed, function(r) r$.source_file, character(1)),
  stringsAsFactors = FALSE
)

result <- list(
  selected_run_id = selected$run_id,
  decision = decision,
  reason = reason,
  why_not_lowest_rmse = why_not_lowest,
  human_review_required = human_review,
  compared_run_count = length(completed),
  comparison_csv = agent_norm_path(summary_csv),
  selected_files = selected$files %||% list(),
  stop_conditions = c("Grade A/B without severe warnings", "No useful improvement after repeated reruns", "RMSE improves but variogram diagnostics degrade", "max_iterations reached", "AI requested MANUAL_REVIEW", "R2_pred remains negative", "No valid variogram candidate", "Validator rejects AI decision")
)
agent_ensure_dir(dirname(output_path))
agent_write_json(result, output_path)
write.csv(summary, summary_csv, row.names = FALSE)
cat("[INFO] Run comparison written to ", agent_norm_path(output_path), "\n", sep = "")
cat("[INFO] Selected run: ", selected$run_id, "\n", sep = "")