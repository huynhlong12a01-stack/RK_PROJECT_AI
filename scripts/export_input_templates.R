# ============================================================
# Export point input templates from the active evaluation profiles.
# ============================================================

source("rk_evaluation/evaluation.R")

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) > 0) args[[1]] else "input/points"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

source("scripts/00_config.R")
profiles <- load_evaluation_profiles(EVALUATION_PROFILE_FILE %||% "config/evaluation_profiles.R")
profiles <- profiles[setdiff(names(profiles), "generic_continuous")]

indicator_rows <- lapply(names(profiles), function(nm) {
  p <- profiles[[nm]]
  data.frame(
    canonical_column = nm,
    display_name = p$display_name %||% "",
    unit = p$unit %||% "",
    aliases = paste(p$aliases %||% character(0), collapse = "; "),
    default_transform = p$default_transform %||% "",
    has_class_bins = isTRUE(p$class_bins$enabled),
    stringsAsFactors = FALSE
  )
})
indicator_table <- do.call(rbind, indicator_rows)

template_cols <- c(CODE_COL, LAT_COL, LON_COL, indicator_table$canonical_column)
template <- as.data.frame(setNames(rep(list(character(0)), length(template_cols)), template_cols), stringsAsFactors = FALSE)

instructions <- data.frame(
  item = c(
    "required_columns",
    "coordinate_columns",
    "indicator_columns",
    "missing_values",
    "normal_run",
    "batch_agent_run"
  ),
  note = c(
    paste(c(CODE_COL, LAT_COL, LON_COL), collapse = ", "),
    "Use the coordinate columns configured in scripts/00_config.R. Do not rename them unless you also update config.",
    "Prefer canonical_column names from the Indicator Profiles sheet/CSV so each soil property uses the correct evaluation profile.",
    "Leave missing indicator values blank. Do not write text such as NA, none, or '-' inside numeric indicator columns.",
    "Rscript scripts/main.R runs one target at a time. If TARGET_FIELD is auto and there is only one indicator column, it is selected automatically.",
    ".\\run_agent_batch.ps1 runs all detected indicator columns, or use -Targets \"pH,Humus,CEC\" for selected columns."
  ),
  stringsAsFactors = FALSE
)

write.csv(template, file.path(out_dir, "soil_points_template.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(indicator_table, file.path(out_dir, "indicator_profiles.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(instructions, file.path(out_dir, "soil_points_template_instructions.csv"), row.names = FALSE, fileEncoding = "UTF-8")

cat("[INFO] Wrote template CSV: ", normalizePath(file.path(out_dir, "soil_points_template.csv"), winslash = "/", mustWork = FALSE), "\n", sep = "")
cat("[INFO] Wrote indicator profiles CSV: ", normalizePath(file.path(out_dir, "indicator_profiles.csv"), winslash = "/", mustWork = FALSE), "\n", sep = "")
