# ============================================================
# Validate raster covariate schema before running full RK.
# This script is read-only and does not modify input rasters.
# ============================================================

source("_UNG_DUNG/engine/scripts/agent_utils.R")

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

safe_num <- function(x) suppressWarnings(as.numeric(x))

args <- parse_args(commandArgs(trailingOnly = TRUE))
source(args$config %||% "_UNG_DUNG/engine/scripts/00_config.R")
agent_require_package("terra")
agent_require_package("readr")

raster_dir <- args$raster_dir %||% RASTER_DIR
pattern <- args$pattern %||% RASTER_PATTERN
point_file <- args$point %||% POINT_FILE
output_json <- args$output %||% file.path("agent", "responses", paste0("raster_schema_check_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".json"))
output_csv <- sub("\\.json$", ".csv", output_json)

warnings <- character(0)
hard_failures <- character(0)
if (!dir.exists(raster_dir)) {
  hard_failures <- c(
    hard_failures,
    paste0("Không tìm thấy thư mục raster: ", raster_dir)
  )
  files <- character(0)
} else {
  files <- list.files(raster_dir, pattern = pattern, full.names = TRUE, ignore.case = TRUE)
}

rows <- list()
for (i in seq_along(files)) {
  f <- files[[i]]
  r_try <- try(terra::rast(f), silent = TRUE)
  if (inherits(r_try, "try-error")) {
    rows[[length(rows) + 1L]] <- data.frame(
      file = agent_norm_path(f), layer_name = NA_character_, crs = NA_character_,
      xmin = NA_real_, xmax = NA_real_, ymin = NA_real_, ymax = NA_real_,
      res_x = NA_real_, res_y = NA_real_, n_cells = NA_real_, non_na_cells = NA_real_,
      status = "read_failed", stringsAsFactors = FALSE
    )
    hard_failures <- c(
      hard_failures,
      paste0("Không đọc được raster: ", f)
    )
    next
  }
  r <- r_try[[1]]
  crs_txt <- terra::crs(r, describe = FALSE)
  ext <- terra::ext(r)
  res <- terra::res(r)
  non_na <- try(terra::global(!is.na(r), "sum", na.rm = TRUE)[1, 1], silent = TRUE)
  if (inherits(non_na, "try-error")) non_na <- NA_real_
  rows[[length(rows) + 1L]] <- data.frame(
    file = agent_norm_path(f),
    layer_name = names(r)[1],
    crs = crs_txt,
    xmin = ext$xmin, xmax = ext$xmax, ymin = ext$ymin, ymax = ext$ymax,
    res_x = res[1], res_y = res[2],
    n_cells = terra::ncell(r),
    non_na_cells = as.numeric(non_na),
    status = "ok",
    stringsAsFactors = FALSE
  )
}

schema_table <- if (length(rows) > 0) do.call(rbind, rows) else data.frame()
if (nrow(schema_table) == 0) {
  hard_failures <- c(
    hard_failures,
    paste0(
      "Không có raster khớp pattern ", pattern, " trong ", raster_dir)
  )
}
if (nrow(schema_table) > 0) {
  if (any(is.na(schema_table$crs) | !nzchar(schema_table$crs))) {
    hard_failures <- c(
      hard_failures, "Một hoặc nhiều raster không có CRS.")
  }
  ok_rows <- schema_table$status == "ok"
  if (sum(ok_rows) > 1) {
    crs_unique <- unique(schema_table$crs[ok_rows])
    crs_unique <- crs_unique[!is.na(crs_unique) & nzchar(crs_unique)]
    if (length(crs_unique) > 1) {
      hard_failures <- c(
        hard_failures, "CRS không nhất quán giữa các raster covariate.")
    }
    res_key <- paste(round(schema_table$res_x[ok_rows], 8), round(schema_table$res_y[ok_rows], 8), sep = "x")
    if (length(unique(res_key)) > 1) {
      warnings <- c(
        warnings,
        "Độ phân giải không nhất quán giữa các raster; engine sẽ resample.")
    }
    ext_key <- paste(round(schema_table$xmin[ok_rows], 4), round(schema_table$xmax[ok_rows], 4), round(schema_table$ymin[ok_rows], 4), round(schema_table$ymax[ok_rows], 4), sep = ";")
    if (length(unique(ext_key)) > 1) {
      warnings <- c(
        warnings,
        paste0(
          "Extent không giống nhau giữa các raster. Engine sẽ project/resample; ",
          "cần kiểm tra alignment cẩn thận."
        )
      )
    }
  }
  if (any(schema_table$non_na_cells <= 0, na.rm = TRUE)) {
    hard_failures <- c(
      hard_failures, "Một hoặc nhiều raster không có cell hợp lệ.")
  }
}

point_overlap <- list(checked = FALSE, point_file = agent_norm_path(point_file), n_points = NULL, n_points_with_first_raster_value = NULL, first_raster = NULL)
if (length(files) > 0 && file.exists(point_file)) {
  pts_try <- try(as.data.frame(readr::read_csv(point_file, show_col_types = FALSE, progress = FALSE)), silent = TRUE)
  if (!inherits(pts_try, "try-error")) {
    names(pts_try) <- clean_names(names(pts_try))
    if (all(c(LON_COL, LAT_COL) %in% names(pts_try))) {
      lon <- safe_num(pts_try[[LON_COL]])
      lat <- safe_num(pts_try[[LAT_COL]])
      ok <- is.finite(lon) & is.finite(lat)
      point_overlap$checked <- TRUE
      point_overlap$n_points <- sum(ok)
      if (sum(ok) > 0) {
        first <- terra::rast(files[[1]])[[1]]
        v <- terra::vect(data.frame(lon = lon[ok], lat = lat[ok]), geom = c("lon", "lat"), crs = "EPSG:4326")
        if (!is.na(terra::crs(first)) && nzchar(terra::crs(first))) {
          v <- try(terra::project(v, terra::crs(first)), silent = TRUE)
        }
        if (!inherits(v, "try-error")) {
          ex <- try(terra::extract(first, v)[, 2], silent = TRUE)
          if (!inherits(ex, "try-error")) {
            point_overlap$n_points_with_first_raster_value <- sum(!is.na(ex))
            point_overlap$first_raster <- agent_norm_path(files[[1]])
            if (point_overlap$n_points_with_first_raster_value == 0) {
              hard_failures <- c(
                hard_failures,
                paste0(
                  "Không có điểm mẫu nào overlap cell hợp lệ của raster đầu tiên; ",
                  "cần kiểm tra CRS, extent và tọa độ input."
                )
              )
            }
          }
        }
      }
    } else {
      hard_failures <- c(
        hard_failures,
        "File điểm thiếu cột lon/lat; không thể kiểm tra overlap raster-điểm."
      )
    }
  } else {
    hard_failures <- c(
      hard_failures,
      "Không đọc được file điểm; không thể kiểm tra overlap raster-điểm."
    )
  }
} else if (!file.exists(point_file)) {
  hard_failures <- c(
    hard_failures,
    paste0("Không tìm thấy file điểm để kiểm tra overlap raster: ", point_file)
  )
}

agent_ensure_dir(dirname(output_json))
agent_write_csv(schema_table, output_csv)
result <- list(
  raster_dir = agent_norm_path(raster_dir),
  raster_pattern = pattern,
  n_rasters = length(files),
  raster_table_csv = agent_norm_path(output_csv),
  rasters = schema_table,
  point_overlap = point_overlap,
  messages = character(0),
  warnings = unique(warnings),
  hard_failures = unique(hard_failures),
  valid = length(files) > 0 &&
    nrow(schema_table) > 0 &&
    all(schema_table$status == "ok") &&
    length(hard_failures) == 0
)
agent_write_json(result, output_json)

cat("[INFO] Raster schema JSON: ", agent_norm_path(output_json), "\n", sep = "")
cat("[INFO] Raster schema CSV: ", agent_norm_path(output_csv), "\n", sep = "")
if (length(warnings) > 0) {
  cat("[WARN] ", paste(unique(warnings), collapse = "\n[WARN] "),
    "\n", sep = "")
}
if (length(hard_failures) > 0) {
  cat("[HARD-FAIL] ",
    paste(unique(hard_failures), collapse = "\n[HARD-FAIL] "),
    "\n", sep = "")
}