# ============================================================
# Export point input templates from the active evaluation profiles.
# ============================================================

source("rk_evaluation/evaluation.R")

for (pkg in c("readr", "openxlsx2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(
      "Missing package '", pkg,
      "'. Install the tidy_io profile before exporting templates: ",
      "install_dependencies.ps1 -Profile tidy_io"
    )
  }
}

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
    transform_requires_nonnegative = isTRUE(p$transform_requires_nonnegative %||% FALSE),
    has_class_bins = isTRUE(p$class_bins$enabled),
    classification_approved = isTRUE(p$class_bins$approved),
    classification_source = p$class_bins$source %||% "",
    laboratory_method = p$class_bins$method %||% "",
    classification_region = p$class_bins$region %||% "",
    classification_crop = p$class_bins$crop %||% "",
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
    "Dùng đúng cột tọa độ trong scripts/00_config.R; không đổi tên nếu chưa cập nhật config.",
    "Ưu tiên canonical_column trong sheet/CSV Indicator Profiles để mỗi chỉ tiêu dùng đúng profile đánh giá.",
    "Để ô trống khi thiếu giá trị; không nhập NA, none hoặc '-' vào cột chỉ tiêu numeric.",
    "Rscript scripts/main.R chạy từng chỉ tiêu. TARGET_FIELD = auto chỉ tự chọn khi CSV có đúng một cột chỉ tiêu.",
    ".\\run_agent_batch.ps1 chạy các cột được phát hiện; dùng -Targets \"pH_H2O,OM_pct,CEC\" để chọn cụ thể."
  ),
  stringsAsFactors = FALSE
)

template_csv <- file.path(out_dir, "soil_points_template.csv")
profiles_csv <- file.path(out_dir, "indicator_profiles.csv")
instructions_csv <- file.path(out_dir, "soil_points_template_instructions.csv")
xlsx_path <- file.path(out_dir, "soil_points_template.xlsx")

readr::write_csv(template, template_csv, na = "")
readr::write_csv(indicator_table, profiles_csv, na = "")
readr::write_csv(instructions, instructions_csv, na = "")

wb <- openxlsx2::wb_workbook(creator = "RK_PROJECT_AI")
for (sheet in c("Template", "Indicator Profiles", "Instructions")) {
  wb <- openxlsx2::wb_add_worksheet(wb, sheet, grid_lines = FALSE)
}

template_xlsx <- as.data.frame(
  setNames(rep(list(rep(NA_character_, 100L)), length(template_cols)),
    template_cols),
  stringsAsFactors = FALSE, check.names = FALSE
)
wb <- openxlsx2::wb_add_data(
  wb, "Template", template_xlsx, na = "", with_filter = TRUE
)
wb <- openxlsx2::wb_add_data(
  wb, "Indicator Profiles", indicator_table, na = "", with_filter = TRUE
)
wb <- openxlsx2::wb_add_data(
  wb, "Instructions", instructions, na = "", with_filter = TRUE
)

sheet_columns <- setNames(
  c(ncol(template_xlsx), ncol(indicator_table), ncol(instructions)),
  c("Template", "Indicator Profiles", "Instructions")
)
for (sheet in names(sheet_columns)) {
  header_dims <- paste0(
    "A1:", openxlsx2::int2col(sheet_columns[[sheet]]), "1")
  wb <- openxlsx2::wb_add_fill(
    wb, sheet, dims = header_dims,
    color = openxlsx2::wb_color(hex = "FFD9EAD3")
  )
  wb <- openxlsx2::wb_add_font(
    wb, sheet, dims = header_dims, bold = TRUE
  )
  wb <- openxlsx2::wb_freeze_pane(wb, sheet, first_row = TRUE)
}
wb <- openxlsx2::wb_set_col_widths(
  wb, "Template", cols = seq_along(template_cols),
  widths = c(14, 12, 12, rep(18, max(0, length(template_cols) - 3L)))
)
wb <- openxlsx2::wb_set_col_widths(
  wb, "Indicator Profiles", cols = seq_len(ncol(indicator_table)),
  widths = 22
)
wb <- openxlsx2::wb_set_col_widths(
  wb, "Instructions", cols = seq_len(ncol(instructions)),
  widths = c(24, 90)
)
lat_index <- match(LAT_COL, template_cols)
lon_index <- match(LON_COL, template_cols)
if (is.finite(lat_index)) {
  lat_col <- openxlsx2::int2col(lat_index)
  wb <- openxlsx2::wb_add_data_validation(
    wb, "Template", dims = paste0(lat_col, "2:", lat_col, "101"),
    type = "decimal", operator = "between", value = c(-90, 90)
  )
}
if (is.finite(lon_index)) {
  lon_col <- openxlsx2::int2col(lon_index)
  wb <- openxlsx2::wb_add_data_validation(
    wb, "Template", dims = paste0(lon_col, "2:", lon_col, "101"),
    type = "decimal", operator = "between", value = c(-180, 180)
  )
}
openxlsx2::wb_save(wb, xlsx_path, overwrite = TRUE)

cat("[INFO] Wrote template CSV: ",
  normalizePath(template_csv, winslash = "/", mustWork = FALSE), "\n", sep = "")
cat("[INFO] Wrote indicator profiles CSV: ",
  normalizePath(profiles_csv, winslash = "/", mustWork = FALSE), "\n", sep = "")
cat("[INFO] Wrote Excel template: ",
  normalizePath(xlsx_path, winslash = "/", mustWork = FALSE), "\n", sep = "")
