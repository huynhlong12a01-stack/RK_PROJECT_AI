# ============================================================
# Batch agent runner: run agent-ready RK for multiple target columns.
# ============================================================

source("scripts/agent_utils.R")
source("rk_evaluation/evaluation.R")

parse_args <- function(args) {
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

split_targets <- function(x) {
  if (is.null(x) || !nzchar(as.character(x))) return(character(0))
  targets <- trimws(unlist(strsplit(as.character(x), "[,;]"), use.names = FALSE))
  targets[nzchar(targets)]
}

count_non_missing <- function(x) {
  sum(!is.na(x) & nzchar(trimws(as.character(x))))
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
request_template <- args$request %||% "agent/requests/run_request_template.json"
target_arg <- args$targets %||% args$target %||% ""
output_summary <- args$output %||% file.path("agent", "responses", paste0("batch_summary_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".json"))
dry_run_value <- args[["dry-run"]] %||% args$dry_run %||% FALSE
dry_run <- isTRUE(dry_run_value) || tolower(as.character(dry_run_value)) %in% c("true", "1", "yes")

source("scripts/00_config.R")
check_file <- function(path) if (!file.exists(path)) stop(paste0("File not found: ", path))
check_file(POINT_FILE)
if (!file.exists(request_template)) stop(paste0("Request template not found: ", request_template))

pts <- read.csv(POINT_FILE, stringsAsFactors = FALSE, check.names = FALSE)
bom <- rawToChar(as.raw(c(0xef, 0xbb, 0xbf)))
names(pts) <- trimws(sub(paste0("^", bom), "", names(pts), useBytes = TRUE))
analysis_cols <- setdiff(names(pts), c(CODE_COL, LAT_COL, LON_COL))
if (length(analysis_cols) == 0) stop("No analysis columns found in point CSV.")

requested_targets <- split_targets(target_arg)
if (length(requested_targets) == 0) {
  if (!is.null(TARGET_FIELD) && !identical(TARGET_FIELD, "auto")) requested_targets <- TARGET_FIELD else requested_targets <- analysis_cols
}
missing_targets <- setdiff(requested_targets, analysis_cols)
if (length(missing_targets) > 0) {
  stop(paste0("Target column(s) not found in CSV: ", paste(missing_targets, collapse = ", "), ". Available: ", paste(analysis_cols, collapse = ", ")))
}

template <- agent_read_json(request_template)
rscript <- Sys.which("Rscript")
if (!nzchar(rscript)) stop("Rscript was not found on PATH.")
profiles <- load_evaluation_profiles(EVALUATION_PROFILE_FILE %||% "config/evaluation_profiles.R")

agent_ensure_dir("agent/requests")
agent_ensure_dir("agent/responses")
agent_ensure_dir(dirname(output_summary))

batch_id <- paste0("batch_", format(Sys.time(), "%Y%m%d_%H%M%S"))
batch_log_dir <- file.path("agent", "history", batch_id)
agent_ensure_dir(batch_log_dir)
results <- list()
rows <- list()

for (target in requested_targets) {
  target_name <- agent_safe_name(target)
  run_id <- paste0(target_name, "_iter_001")
  req <- template
  req$run_id <- run_id
  req$target_field <- target
  req$output_root <- req$output_root %||% "output/agent_runs"
  req$safety_limits <- agent_merge_lists(req$safety_limits %||% list(), list(max_iterations = 3, allow_delete_points = FALSE, allow_modify_raw_data = FALSE))
  req_file <- file.path("agent", "requests", paste0("run_request_", target_name, "_iter_001.json"))
  agent_write_json(req, req_file)

  cat("[INFO] Running target: ", target, "\n", sep = "")
  start_time <- Sys.time()
  target_log <- file.path(batch_log_dir, paste0("agent_run_", target_name, ".log"))
  if (dry_run) {
    writeLines(c("[DRY_RUN] Batch runner request/profile/log check only.", paste0("Target: ", target), paste0("Request: ", req_file)), target_log, useBytes = TRUE)
    status <- 0L
    response_files <- character(0)
  } else {
    status <- system2(rscript, c("scripts/agent_run.R", "--request", req_file, "--target", target), stdout = target_log, stderr = target_log)
    response_files <- list.files("agent/responses", pattern = "_run_result\\.json$", full.names = TRUE)
  }
  response_files <- response_files[file.info(response_files)$mtime >= start_time - 5]
  candidate_results <- list()
  for (f in response_files) {
    x <- try(agent_read_json(f), silent = TRUE)
    if (!inherits(x, "try-error") && identical(x$target_field, target)) {
      x$.response_file <- agent_norm_path(f)
      candidate_results[[length(candidate_results) + 1L]] <- x
    }
  }
  if (dry_run) {
    result <- list(target_field = target, status = "dry_run", run_id = run_id, warnings = "Dry run only; RK engine was not executed.", response_file = NULL)
  } else if (length(candidate_results) == 0) {
    result <- list(target_field = target, status = "failed", run_id = run_id, warnings = paste0("agent_run exited with code ", status), response_file = NULL)
  } else {
    mtimes <- vapply(candidate_results, function(x) as.numeric(file.info(x$.response_file)$mtime), numeric(1))
    result <- candidate_results[[which.max(mtimes)]]
  }

  prof <- match_indicator_profile(target, profiles)
  results[[target]] <- result
  rows[[length(rows) + 1L]] <- data.frame(
    target = target,
    run_id = result$run_id %||% run_id,
    status = result$status %||% "unknown",
    n_non_missing = count_non_missing(pts[[target]]),
    profile_name = prof$profile_name %||% NA_character_,
    profile_matched = isTRUE(prof$profile_matched),
    final_grade = result$quality$final_grade %||% NA_character_,
    final_score = result$quality$final_score %||% NA_real_,
    rk_rmse = result$metrics$rk_rmse %||% NA_real_,
    rk_mae = result$metrics$rk_mae %||% NA_real_,
    rk_me = result$metrics$rk_me %||% NA_real_,
    rk_r2_pred = result$metrics$rk_r2_pred %||% NA_real_,
    selected_nmax_neighbors = result$kriging$selected_nmax_neighbors %||% NA_real_,
    selected_search_radius = result$kriging$selected_search_radius %||% NA_real_,
    html_report = result$files$html_report %||% NA_character_,
    run_result = result$.response_file %||% NA_character_,
    target_log = agent_norm_path(target_log),
    stringsAsFactors = FALSE
  )
}

summary_table <- do.call(rbind, rows)
summary_csv <- sub("\\.json$", ".csv", output_summary)
write.csv(summary_table, summary_csv, row.names = FALSE, fileEncoding = "UTF-8")

summary <- list(
  batch_id = batch_id,
  targets = requested_targets,
  n_targets = length(requested_targets),
  dry_run = dry_run,
  batch_log_dir = agent_norm_path(batch_log_dir),
  summary_csv = agent_norm_path(summary_csv),
  results = results
)
agent_write_json(summary, output_summary)
cat("[INFO] Batch summary JSON: ", agent_norm_path(output_summary), "\n", sep = "")
cat("[INFO] Batch summary CSV: ", agent_norm_path(summary_csv), "\n", sep = "")