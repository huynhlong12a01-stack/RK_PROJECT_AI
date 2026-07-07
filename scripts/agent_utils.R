# ============================================================
# Agent utility functions for file-based Regression Kriging API.
# Prefer jsonlite when available; otherwise use a small base-R JSON reader/writer.
# ============================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

agent_safe_name <- function(x) {
  x <- gsub("[^A-Za-z0-9_-]+", "_", as.character(x))
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  if (!nzchar(x)) x <- "run"
  x
}

agent_norm_path <- function(path) {
  if (is.null(path) || length(path) == 0 || is.na(path)) return(NA_character_)
  gsub("\\\\", "/", path)
}

agent_ensure_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  invisible(path)
}

agent_json_escape <- function(x) {
  x <- as.character(x)
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub('"', '\\"', x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x <- gsub("\r", "\\r", x, fixed = TRUE)
  x <- gsub("\t", "\\t", x, fixed = TRUE)
  x
}

agent_to_json <- function(x, pretty = TRUE, level = 0) {
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    return(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = pretty, null = "null", na = "null"))
  }
  indent <- function(n) paste(rep("  ", n), collapse = "")
  nl <- if (pretty) "\n" else ""
  sp <- if (pretty) " " else ""
  if (is.null(x)) return("null")
  if (!is.list(x) && length(x) == 0) return("[]")
  if (inherits(x, "table") || is.matrix(x)) x <- as.data.frame.matrix(x)
  if (is.data.frame(x)) {
    rows <- lapply(seq_len(nrow(x)), function(i) as.list(x[i, , drop = FALSE]))
    return(agent_to_json(rows, pretty, level))
  }
  if (is.list(x)) {
    if (length(x) == 0) return(if (is.null(names(x))) "[]" else "{}")
    if (is.null(names(x))) {
      vals <- vapply(x, agent_to_json, character(1), pretty = pretty, level = level + 1)
      return(paste0("[", nl, indent(level + 1), paste(vals, collapse = paste0(",", nl, indent(level + 1))), nl, indent(level), "]"))
    }
    vals <- vapply(names(x), function(nm) {
      paste0('"', agent_json_escape(nm), '":', sp, agent_to_json(x[[nm]], pretty, level + 1))
    }, character(1))
    return(paste0("{", nl, indent(level + 1), paste(vals, collapse = paste0(",", nl, indent(level + 1))), nl, indent(level), "}"))
  }
  if (is.character(x)) {
    vals <- paste0('"', agent_json_escape(x), '"')
    vals[is.na(x)] <- "null"
    return(if (length(vals) == 1) vals else paste0("[", paste(vals, collapse = ","), "]"))
  }
  if (is.logical(x)) {
    vals <- ifelse(is.na(x), "null", tolower(as.character(x)))
    return(if (length(vals) == 1) vals else paste0("[", paste(vals, collapse = ","), "]"))
  }
  if (is.numeric(x) || is.integer(x)) {
    vals <- ifelse(is.na(x) | !is.finite(x), "null", as.character(x))
    return(if (length(vals) == 1) vals else paste0("[", paste(vals, collapse = ","), "]"))
  }
  paste0('"', agent_json_escape(as.character(x)), '"')
}

agent_write_json <- function(x, path) {
  agent_ensure_dir(dirname(path))
  writeLines(agent_to_json(x, pretty = TRUE), path, useBytes = TRUE)
  invisible(path)
}

agent_read_json <- function(path) {
  if (!file.exists(path)) stop(paste0("JSON file not found: ", path))
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    return(jsonlite::fromJSON(path, simplifyVector = FALSE))
  }
  txt <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  i <- 1L
  n <- nchar(txt)
  chr <- function() substr(txt, i, i)
  skip_ws <- function() while (i <= n && grepl("[[:space:]]", chr())) i <<- i + 1L
  parse_string <- function() {
    i <<- i + 1L
    out <- character(0)
    while (i <= n) {
      ch <- chr()
      if (ch == '"') { i <<- i + 1L; return(paste(out, collapse = "")) }
      if (ch == "\\") {
        i <<- i + 1L
        esc <- chr()
        out <- c(out, switch(esc, '"'='"', '\\'='\\', '/'='/', 'b'='\b', 'f'='\f', 'n'='\n', 'r'='\r', 't'='\t', esc))
        i <<- i + 1L
      } else {
        out <- c(out, ch)
        i <<- i + 1L
      }
    }
    stop("Unterminated JSON string")
  }
  parse_number <- function() {
    start <- i
    while (i <= n && grepl("[0-9eE+.-]", chr())) i <<- i + 1L
    as.numeric(substr(txt, start, i - 1L))
  }
  parse_literal <- function(lit, val) {
    if (substr(txt, i, i + nchar(lit) - 1L) != lit) stop(paste0("Invalid JSON near: ", substr(txt, i, min(n, i + 20L))))
    i <<- i + nchar(lit)
    val
  }
  parse_array <- function() {
    i <<- i + 1L
    out <- list()
    skip_ws()
    if (i <= n && chr() == "]") { i <<- i + 1L; return(out) }
    repeat {
      out[[length(out) + 1L]] <- parse_value()
      skip_ws()
      if (chr() == "]") { i <<- i + 1L; return(out) }
      if (chr() != ",") stop("Expected comma in JSON array")
      i <<- i + 1L
    }
  }
  parse_object <- function() {
    i <<- i + 1L
    out <- list()
    skip_ws()
    if (i <= n && chr() == "}") { i <<- i + 1L; return(out) }
    repeat {
      skip_ws()
      if (chr() != '"') stop("Expected string key in JSON object")
      key <- parse_string()
      skip_ws()
      if (chr() != ":") stop("Expected colon in JSON object")
      i <<- i + 1L
      out[[key]] <- parse_value()
      skip_ws()
      if (chr() == "}") { i <<- i + 1L; return(out) }
      if (chr() != ",") stop("Expected comma in JSON object")
      i <<- i + 1L
    }
  }
  parse_value <- function() {
    skip_ws()
    ch <- chr()
    if (ch == '"') return(parse_string())
    if (ch == "{") return(parse_object())
    if (ch == "[") return(parse_array())
    if (grepl("[-0-9]", ch)) return(parse_number())
    if (substr(txt, i, i + 3L) == "true") return(parse_literal("true", TRUE))
    if (substr(txt, i, i + 4L) == "false") return(parse_literal("false", FALSE))
    if (substr(txt, i, i + 3L) == "null") return(parse_literal("null", NULL))
    stop(paste0("Invalid JSON value near: ", substr(txt, i, min(n, i + 20L))))
  }
  value <- parse_value()
  skip_ws()
  if (i <= n) stop("Trailing content after JSON value")
  value
}

agent_allowed_parameters <- function() {
  c("VARIOGRAM_MODE", "VARIOGRAM_MODEL", "MANUAL_NUGGET", "MANUAL_PSILL", "MANUAL_RANGE",
    "VARIOGRAM_CUTOFF", "VARIOGRAM_WIDTH", "VARIOGRAM_RANGE_MIN", "VARIOGRAM_RANGE_MAX",
    "NMAX_NEIGHBORS", "SEARCH_RADIUS", "AUTO_NEIGHBORS", "AUTO_NEIGHBOR_NMAX_CANDIDATES",
    "AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES", "AUTO_NEIGHBOR_CV_METHOD", "AUTO_NEIGHBOR_MAX_CANDIDATES",
    "CV_METHODS", "CV_K_FOLDS", "CLAMP_TO_SAMPLE_RANGE", "TARGET_TRANSFORM")
}
agent_protected_parameters <- function() {
  c("POINT_FILE", "RASTER_DIR", "ROI_FILE", "UTM_EPSG", "EXPORT_EPSG", "CODE_COL", "LAT_COL", "LON_COL",
    "RASTER_PATTERN", "OUTPUT_RESOLUTION", "USE_COMPLETE_PC_MASK", "REGRESSION_FORMULA", "raw_input_data", "source_scripts")
}

agent_default_safety_limits <- function() {
  list(max_iterations = 5, allow_delete_points = FALSE, allow_modify_raw_data = FALSE,
       min_range = 500, max_range = 25000, min_neighbors = 4, max_neighbors = 50)
}

agent_merge_lists <- function(a, b) {
  a <- a %||% list()
  b <- b %||% list()
  for (nm in names(b)) a[[nm]] <- b[[nm]]
  a
}

agent_as_vector <- function(x) {
  if (is.null(x)) return(character(0))
  if (is.list(x)) return(unlist(x, use.names = FALSE))
  x
}

agent_validate_parameter <- function(name, value, safety_limits = list()) {
  safety <- agent_merge_lists(agent_default_safety_limits(), safety_limits)
  err <- NULL
  val_vec <- agent_as_vector(value)
  num1 <- function(v) is.numeric(v) && length(v) == 1 && is.finite(v)
  int1 <- function(v) num1(v) && abs(v - round(v)) < 1e-9
  if (name == "VARIOGRAM_MODE" && !(value %in% c("manual", "auto_select", "auto"))) err <- "VARIOGRAM_MODE must be manual, auto_select, or auto."
  if (name == "VARIOGRAM_MODEL" && !(value %in% c("Exp", "Sph", "Gau"))) err <- "VARIOGRAM_MODEL must be Exp, Sph, or Gau."
  if (name %in% c("MANUAL_NUGGET", "MANUAL_PSILL") && (!num1(value) || value < 0)) err <- paste0(name, " must be a non-negative number.")
  if (name %in% c("MANUAL_RANGE", "VARIOGRAM_CUTOFF", "VARIOGRAM_WIDTH", "VARIOGRAM_RANGE_MIN", "VARIOGRAM_RANGE_MAX", "SEARCH_RADIUS")) {
    if (!num1(value) || value < safety$min_range || value > safety$max_range) err <- paste0(name, " must be between min_range and max_range.")
  }
  if (name == "AUTO_NEIGHBORS" && (!is.logical(value) || length(value) != 1)) err <- "AUTO_NEIGHBORS must be true or false."
  if (name == "AUTO_NEIGHBOR_NMAX_CANDIDATES") {
    vals <- suppressWarnings(as.numeric(val_vec))
    if (length(vals) == 0 || any(!is.finite(vals)) || any(vals < safety$min_neighbors) || any(vals > safety$max_neighbors)) err <- "AUTO_NEIGHBOR_NMAX_CANDIDATES is outside safety limits."
  }
  if (name == "AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES") {
    vals <- suppressWarnings(as.numeric(val_vec))
    if (length(vals) == 0 || any(!is.finite(vals)) || any(vals < safety$min_range) || any(vals > safety$max_range)) err <- "AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES is outside safety limits."
  }
  if (name == "AUTO_NEIGHBOR_CV_METHOD" && !(value %in% c("random", "spatial_kmeans"))) err <- "AUTO_NEIGHBOR_CV_METHOD must be random or spatial_kmeans."
  if (name == "AUTO_NEIGHBOR_MAX_CANDIDATES" && (!int1(value) || value < 1 || value > 250)) err <- "AUTO_NEIGHBOR_MAX_CANDIDATES must be an integer from 1 to 250."
  if (name == "NMAX_NEIGHBORS" && (!int1(value) || value < safety$min_neighbors || value > safety$max_neighbors)) err <- "NMAX_NEIGHBORS is outside safety limits."
  if (name == "CV_K_FOLDS" && (!int1(value) || value < 2 || value > 20)) err <- "CV_K_FOLDS must be an integer from 2 to 20."
  if (name == "CV_METHODS" && (!all(val_vec %in% c("random", "spatial_kmeans")) || length(val_vec) == 0)) err <- "CV_METHODS must contain random and/or spatial_kmeans."
  if (name == "CLAMP_TO_SAMPLE_RANGE" && (!is.logical(value) || length(value) != 1)) err <- "CLAMP_TO_SAMPLE_RANGE must be true or false."
  if (name == "TARGET_TRANSFORM") err <- "TARGET_TRANSFORM is whitelisted for future use but this project does not implement transforms yet."
  err
}

agent_validate_parameter_list <- function(params, safety_limits = list()) {
  allowed <- agent_allowed_parameters()
  protected <- agent_protected_parameters()
  accepted <- list()
  rejected <- list()
  warnings <- character(0)
  if (is.null(params) || length(params) == 0) return(list(accepted = accepted, rejected = rejected, warnings = warnings))
  for (nm in names(params)) {
    if (nm %in% protected) {
      rejected[[nm]] <- "AI is not allowed to modify protected input, CRS, or source settings."
      warnings <- c(warnings, "Decision contains protected parameter.")
    } else if (!(nm %in% allowed)) {
      rejected[[nm]] <- "Parameter is not whitelisted for AI modification."
      warnings <- c(warnings, "Decision contains non-whitelisted parameter.")
    } else {
      err <- agent_validate_parameter(nm, params[[nm]], safety_limits)
      if (is.null(err)) accepted[[nm]] <- params[[nm]] else rejected[[nm]] <- err
    }
  }
  list(accepted = accepted, rejected = rejected, warnings = unique(warnings))
}

agent_r_literal <- function(x) {
  if (is.null(x)) return("NULL")
  if (is.character(x)) return(paste0('"', agent_json_escape(x), '"'))
  if (is.logical(x)) return(ifelse(isTRUE(x), "TRUE", "FALSE"))
  if (is.numeric(x) || is.integer(x)) return(as.character(x))
  if (is.list(x)) return(paste0("c(", paste(vapply(agent_as_vector(x), agent_r_literal, character(1)), collapse = ", "), ")"))
  paste0('"', agent_json_escape(as.character(x)), '"')
}

agent_read_csv_if_exists <- function(path) {
  if (!file.exists(path)) return(data.frame())
  tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) data.frame())
}

agent_pick_model_metric <- function(model_comparison, model, field = "RMSE", preferred_method = "spatial_kmeans") {
  if (is.null(model_comparison) || nrow(model_comparison) == 0) return(NA_real_)
  d <- model_comparison
  if (!(field %in% names(d)) || !("model" %in% names(d))) return(NA_real_)
  if ("cv_method" %in% names(d) && preferred_method %in% d$cv_method) d <- d[d$cv_method == preferred_method, , drop = FALSE]
  row <- d[d$model == model, , drop = FALSE]
  if (nrow(row) == 0) return(NA_real_)
  suppressWarnings(as.numeric(row[[field]][1]))
}

agent_decision_hint <- function(result) {
  grade <- result$quality$final_grade %||% NA_character_
  warnings <- paste(result$warnings %||% character(0), collapse = " ")
  r2 <- result$metrics$rk_r2_pred %||% NA_real_
  if (is.finite(r2) && r2 < 0) return("MANUAL_REVIEW_REQUIRED")
  if (grepl("Range chạm|Range cham|fit ép|fit ep|không cải thiện|khong cai thien|R²_pred âm|R2_pred am|không tìm được candidate|khong co candidate", warnings, ignore.case = TRUE)) return("RERUN_RECOMMENDED")
  if (grade %in% c("A", "B")) return("ACCEPTABLE")
  "RERUN_RECOMMENDED"
}