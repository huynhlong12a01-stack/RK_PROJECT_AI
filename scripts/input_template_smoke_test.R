# Smoke test for dependency-based CSV/XLSX input template generation.

required_packages <- c("readr", "openxlsx2")
missing <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing) > 0) {
  stop(
    "Missing template smoke-test packages: ",
    paste(missing, collapse = ", "),
    ". Install profile tidy_io first."
  )
}

out_dir <- file.path(".tmp", "input_template_smoke")
if (dir.exists(out_dir)) unlink(out_dir, recursive = TRUE, force = TRUE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

rscript <- Sys.which("Rscript")
if (!nzchar(rscript)) stop("Rscript was not found on PATH.")
output <- system2(
  rscript,
  c("scripts/export_input_templates.R", out_dir),
  stdout = TRUE, stderr = TRUE
)
status <- attr(output, "status")
if (is.null(status)) status <- 0L
if (!identical(as.integer(status), 0L)) {
  stop("Template exporter failed:\n", paste(output, collapse = "\n"))
}

paths <- file.path(out_dir, c(
  "soil_points_template.csv",
  "indicator_profiles.csv",
  "soil_points_template_instructions.csv",
  "soil_points_template.xlsx"
))
missing_files <- paths[!file.exists(paths)]
if (length(missing_files) > 0) {
  stop("Template exporter missed: ", paste(missing_files, collapse = ", "))
}

template_csv <- suppressMessages(readr::read_csv(
  paths[1], show_col_types = FALSE, progress = FALSE))
template_xlsx <- openxlsx2::read_xlsx(paths[4], sheet = "Template")
profiles <- openxlsx2::read_xlsx(paths[4], sheet = "Indicator Profiles")
instructions <- openxlsx2::read_xlsx(paths[4], sheet = "Instructions")

canonical <- c(
  "code", "lat", "lon", "pH_H2O", "P_Olsen_mgkg",
  "P_Mehlich3_mgkg", "ECe_dSm"
)
if (!identical(names(template_csv), names(template_xlsx))) {
  stop("CSV and XLSX template headers differ.")
}
if (!all(canonical %in% names(template_xlsx))) {
  stop("XLSX template is missing canonical columns.")
}
if (nrow(template_xlsx) != 100L) {
  stop("XLSX template must provide exactly 100 blank input rows.")
}
if (!all(c("canonical_column", "classification_approved") %in% names(profiles)) ||
    !all(c("pH_H2O", "P_Mehlich3_mgkg") %in% profiles$canonical_column)) {
  stop("Indicator Profiles sheet is incomplete.")
}
if (!all(c("item", "note") %in% names(instructions)) ||
    !all(c("required_columns", "coordinate_columns") %in% instructions$item) ||
    !any(grepl("scripts/00_config.R", as.character(instructions$note),
      fixed = TRUE, useBytes = TRUE))) {
  stop("Vietnamese Instructions sheet is missing or incorrectly encoded.")
}

cat("[OK] input template CSV/XLSX smoke test passed\n")
