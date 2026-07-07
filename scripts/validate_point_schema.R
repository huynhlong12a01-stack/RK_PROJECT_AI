# ============================================================
# Validate point CSV schema and indicator profile matching.
# This script does not modify raw input data.
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

clean_names <- function(x) {
  bom <- rawToChar(as.raw(c(0xef, 0xbb, 0xbf)))
  trimws(sub(paste0("^", bom), "", x, useBytes = TRUE))
}

count_numeric_values <- function(x) {
  x <- trimws(as.character(x))
  x <- x[!is.na(x) & nzchar(x)]
  if (length(x) == 0) return(list(n = 0L, numeric = TRUE))
  nums <- suppressWarnings(as.numeric(x))
  list(n = length(x), numeric = all(is.finite(nums)))
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
source(args$config %||% "scripts/00_config.R")

point_file <- args$point %||% POINT_FILE
output_json <- args$output %||% file.path("agent", "responses", paste0("point_schema_check_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".json"))
output_csv <- sub("\\.json$", ".csv", output_json)

if (!file.exists(point_file)) {
  stop(paste0("Point file not found: ", point_file))
}

pts <- read.csv(point_file, stringsAsFactors = FALSE, check.names = FALSE)
names(pts) <- clean_names(names(pts))

required_cols <- c(CODE_COL, LAT_COL, LON_COL)
missing_required <- setdiff(required_cols, names(pts))
analysis_cols <- setdiff(names(pts), required_cols)
profiles <- load_evaluation_profiles(EVALUATION_PROFILE_FILE %||% "config/evaluation_profiles.R")

rows <- lapply(analysis_cols, function(col) {
  prof <- match_indicator_profile(col, profiles)
  cnt <- count_numeric_values(pts[[col]])
  data.frame(
    column = col,
    n_values = cnt$n,
    is_numeric = cnt$numeric,
    profile_name = prof$profile_name %||% NA_character_,
    profile_matched = isTRUE(prof$profile_matched),
    display_name = prof$display_name %||% NA_character_,
    unit = prof$unit %||% NA_character_,
    stringsAsFactors = FALSE
  )
})
schema_table <- if (length(rows) > 0) do.call(rbind, rows) else data.frame()

warnings <- character(0)
if (length(missing_required) > 0) warnings <- c(warnings, paste0("Missing required coordinate/code column(s): ", paste(missing_required, collapse = ", ")))
if (length(analysis_cols) == 0) warnings <- c(warnings, "No analysis indicator columns found after code/lat/lon.")
if (nrow(schema_table) > 0 && any(!schema_table$is_numeric)) {
  warnings <- c(warnings, paste0("Non-numeric indicator column(s): ", paste(schema_table$column[!schema_table$is_numeric], collapse = ", ")))
}
if (nrow(schema_table) > 0 && any(!schema_table$profile_matched)) {
  warnings <- c(warnings, paste0("Column(s) using generic evaluation profile: ", paste(schema_table$column[!schema_table$profile_matched], collapse = ", ")))
}
if (nrow(schema_table) > 0 && any(schema_table$n_values < 30)) {
  warnings <- c(warnings, paste0("Column(s) with fewer than 30 non-missing values: ", paste(schema_table$column[schema_table$n_values < 30], collapse = ", ")))
}

agent_ensure_dir(dirname(output_json))
write.csv(schema_table, output_csv, row.names = FALSE, fileEncoding = "UTF-8")

result <- list(
  point_file = agent_norm_path(point_file),
  n_rows = nrow(pts),
  required_columns = required_cols,
  missing_required_columns = missing_required,
  analysis_columns = analysis_cols,
  n_analysis_columns = length(analysis_cols),
  schema_csv = agent_norm_path(output_csv),
  indicators = schema_table,
  warnings = warnings,
  valid = length(missing_required) == 0 && length(analysis_cols) > 0 && (nrow(schema_table) == 0 || all(schema_table$is_numeric))
)
agent_write_json(result, output_json)

cat("[INFO] Point schema JSON: ", agent_norm_path(output_json), "\n", sep = "")
cat("[INFO] Point schema CSV: ", agent_norm_path(output_csv), "\n", sep = "")
if (length(warnings) > 0) {
  cat("[WARN] ", paste(warnings, collapse = "\n[WARN] "), "\n", sep = "")
}
