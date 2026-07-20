suppressPackageStartupMessages({
  library(readr)
  library(jsonlite)
})

argument_value <- function(name, default = NULL) {
  args <- commandArgs(trailingOnly = TRUE)
  hit <- match(name, args)
  if (is.na(hit) || hit == length(args)) return(default)
  args[[hit + 1L]]
}

base <- argument_value("--project", "projects/PHU_YEN_MOCK")
models_root <- file.path(base, "_NOI_BO/work/models")
qa_dir <- file.path(models_root, "qa")
manifest_file <- file.path(qa_dir, "sensitivity_input_manifest.csv")
output_csv <- file.path(qa_dir, "outside_sample_sensitivity_comparison.csv")
output_json <- file.path(qa_dir, "outside_sample_sensitivity_summary.json")
utility_file <- file.path(
  base, "_NOI_BO/pipeline/sensitivity_comparison_utils.R")
if (!file.exists(utility_file)) stop("Missing utility file: ", utility_file)
source(utility_file)
dir.create(qa_dir, recursive = TRUE, showWarnings = FALSE)

root_abs <- normalizePath(models_root, winslash = "/", mustWork = FALSE)
evaluation_files <- if (dir.exists(models_root)) {
  list.files(
    models_root, pattern = "^evaluation_.+\\.json$", recursive = TRUE,
    full.names = TRUE
  )
} else character()

classify_path <- function(path) {
  absolute <- normalizePath(path, winslash = "/", mustWork = FALSE)
  prefix <- paste0(root_abs, "/")
  if (!startsWith(absolute, prefix)) return(NULL)
  relative <- substring(absolute, nchar(prefix) + 1L)
  parts <- strsplit(relative, "/", fixed = TRUE)[[1]]
  if (length(parts) >= 4L && parts[1] == "SENSITIVITY") {
    return(list(scenario_id = parts[2], model_branch = parts[3]))
  }
  if (length(parts) >= 3L && parts[1] %in%
      c("PC_ONLY", "PC_PLUS_SOIL")) {
    return(list(scenario_id = "PRIMARY", model_branch = parts[1]))
  }
  NULL
}

rows <- list()
modified <- numeric()
for (path in evaluation_files) {
  classification <- classify_path(path)
  if (is.null(classification)) next
  row <- try(sensitivity_read_evaluation(
    path, classification$scenario_id, classification$model_branch),
    silent = TRUE)
  if (inherits(row, "try-error")) next
  rows[[length(rows) + 1L]] <- row
  modified <- c(modified, as.numeric(file.info(path)$mtime))
}

if (length(rows)) {
  table <- do.call(rbind, rows)
  table$.modified <- modified
  key <- paste(table$scenario_id, table$model_branch, table$target, sep = "|")
  order_index <- order(key, table$.modified, decreasing = FALSE)
  table <- table[order_index, , drop = FALSE]
  key <- key[order_index]
  table <- table[!duplicated(key, fromLast = TRUE), , drop = FALSE]
  table$.modified <- NULL
  table <- sensitivity_compare_to_primary(table)
  table <- table[order(
    table$target, table$model_branch, table$scenario_id), , drop = FALSE]
} else {
  table <- data.frame(
    scenario_id = character(), model_branch = character(),
    target = character(), product_status = character(),
    prediction_method = character(), n_model_points = numeric(),
    cv_n = numeric(), cv_RMSE = numeric(), cv_MAE = numeric(),
    cv_ME = numeric(), cv_R2_pred = numeric(),
    outside_aoa_percent = numeric(), clipped_area_percent = numeric(),
    final_grade = character(), final_score = numeric(),
    n_hard_failures = integer(), evaluation_json = character(),
    stringsAsFactors = FALSE
  )
}
readr::write_csv(table, output_csv, na = "")

planned <- if (file.exists(manifest_file)) {
  as.data.frame(readr::read_csv(
    manifest_file, show_col_types = FALSE, progress = FALSE))
} else data.frame()
n_primary <- sum(table$scenario_id == "PRIMARY")
n_sensitivity <- sum(table$scenario_id != "PRIMARY")
summary <- list(
  diagnostic_id = "outside_sample_model_sensitivity_v1",
  status = if (!n_sensitivity) "pending_sensitivity_runs" else "complete",
  n_primary_evaluations = n_primary,
  n_sensitivity_evaluations = n_sensitivity,
  sensitivity_scenarios_evaluated = unique(
    table$scenario_id[table$scenario_id != "PRIMARY"]),
  planned_scenarios = if (nrow(planned)) planned$scenario_id else character(),
  comparison_csv = normalizePath(
    output_csv, winslash = "/", mustWork = FALSE),
  comparison_role = "model_development_sensitivity_not_validation",
  automatic_model_choice = FALSE,
  interpretation = paste0(
    "Scenario deltas compare outer held-out spatial-CV diagnostics after ",
    "refitting models with different declared sample sets. They quantify ",
    "sensitivity to outside samples but do not create an independent field ",
    "validation set or prove causal bias."
  ),
  review_fields = c(
    "delta_cv_RMSE", "delta_cv_MAE", "delta_cv_ME",
    "delta_cv_R2_pred", "delta_outside_aoa_percent",
    "delta_clipped_area_percent", "delta_n_hard_failures"
  ),
  generated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
)
jsonlite::write_json(
  summary, output_json, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(
  "Sensitivity comparison: ", n_primary, " primary and ",
  n_sensitivity, " scenario evaluation(s).\n", sep = ""
)
