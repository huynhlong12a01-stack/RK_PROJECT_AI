cat("\n============================================\n")
cat("REGRESSION KRIGING - R PURE CODE\n")
cat("============================================\n\n")

source("_UNG_DUNG/engine/scripts/00_config.R")

rk_config_override <- Sys.getenv("RK_CONFIG_OVERRIDE", unset = "")
if (nzchar(rk_config_override)) {
  if (!file.exists(rk_config_override)) {
    stop(paste0("RK_CONFIG_OVERRIDE file not found: ", rk_config_override))
  }
  source(rk_config_override)
}

source("_UNG_DUNG/engine/rk_evaluation/evaluation.R")
source("_UNG_DUNG/engine/scripts/transform_utils.R")
source("_UNG_DUNG/engine/scripts/spatial_validation.R")

packages <- c("sf", "terra", "gstat", "sp")

for (p in packages) {
  if (!requireNamespace(p, quietly = TRUE)) {
    stop(paste0("Missing R package: ", p))
  }
}

suppressPackageStartupMessages({
  library(sf)
  library(terra)
  library(gstat)
  library(sp)
})

safe_name <- function(x) {
  x <- gsub("[^A-Za-z0-9_]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  if (nchar(x) == 0) x <- "run"
  return(x)
}

bt <- function(x) {
  paste0("`", gsub("`", "", x), "`")
}

check_file <- function(path) {
  if (length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop(
      "Project workflow did not provide an input file. Start the workflow from the project's RUN.ps1 or .bat launcher; do not run the internal engine directly."
    )
  }
  if (!file.exists(path)) {
    stop(paste0("File not found: ", path))
  }
}

check_directory <- function(path, label) {
  if (length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop(paste0(
      "Project workflow did not provide ", label,
      ". Start the workflow from the project's RUN.ps1 or .bat launcher; do not run the internal engine directly."
    ))
  }
  if (!dir.exists(path)) stop(paste0("Directory not found: ", path))
}

save_plot_done <- function(path) {
  invisible(dev.off())
  cat("Saved plot: ", path, "\n", sep = "")
}

detect_pc_files <- function() {
  files <- list.files(
    RASTER_DIR,
    pattern = RASTER_PATTERN,
    full.names = TRUE,
    ignore.case = TRUE
  )

  if (length(files) == 0) {
    stop(paste0(
      "No raster file found in folder: ",
      RASTER_DIR,
      " with pattern: ",
      RASTER_PATTERN
    ))
  }

  base_names <- basename(files)

  # regmatches() drops elements that have no match, which can shorten the sort
  # key and silently omit categorical rasters such as SoilDummy_Fa.tif.
  has_number <- grepl("[0-9]+", base_names)
  first_number <- rep(NA_real_, length(base_names))
  first_number[has_number] <- suppressWarnings(as.numeric(
    sub("^[^0-9]*([0-9]+).*$", "\\1", base_names[has_number])
  ))

  sort_number <- ifelse(is.na(first_number), Inf, first_number)
  ord <- order(sort_number, base_names)

  files <- files[ord]
  base_names <- base_names[ord]

  predictor_names <- tools::file_path_sans_ext(base_names)
  predictor_names <- make.names(predictor_names, unique = TRUE)

  names(files) <- predictor_names
  return(files)
}

utm_epsg_from_lonlat <- function(lon, lat) {
  lon <- suppressWarnings(as.numeric(lon))
  lat <- suppressWarnings(as.numeric(lat))
  if (!is.finite(lon) || !is.finite(lat)) return(NA_integer_)
  zone <- floor((lon + 180) / 6) + 1
  zone <- max(1, min(60, zone))
  if (lat >= 0) 32600L + zone else 32700L + zone
}

resolve_utm_epsg <- function(points_df, lon_col, lat_col, configured_epsg) {
  lon <- suppressWarnings(as.numeric(points_df[[lon_col]]))
  lat <- suppressWarnings(as.numeric(points_df[[lat_col]]))
  lon <- lon[is.finite(lon)]
  lat <- lat[is.finite(lat)]
  center_lon <- if (length(lon) > 0) stats::median(lon, na.rm = TRUE) else NA_real_
  center_lat <- if (length(lat) > 0) stats::median(lat, na.rm = TRUE) else NA_real_
  auto_epsg <- utm_epsg_from_lonlat(center_lon, center_lat)

  if (is.character(configured_epsg) && tolower(trimws(configured_epsg[1])) == "auto") {
    if (!is.finite(auto_epsg)) stop("Cannot auto-detect UTM_EPSG because lon/lat coordinates are not valid.")
    return(list(epsg = as.integer(auto_epsg), auto_epsg = as.integer(auto_epsg), mode = "auto", warning = NULL, center_lon = center_lon, center_lat = center_lat))
  }

  epsg <- suppressWarnings(as.integer(configured_epsg[1]))
  if (!is.finite(epsg)) stop("UTM_EPSG must be a numeric EPSG code or 'auto'.")
  warning <- NULL
  if (is.finite(auto_epsg) && !identical(as.integer(epsg), as.integer(auto_epsg))) {
    warning <- paste0("UTM_EPSG config = ", epsg, " nhưng tâm điểm mẫu gợi ý EPSG:", auto_epsg, ". Hãy kiểm tra lại zone UTM trước khi dùng kết quả chính thức.")
  }
  list(epsg = as.integer(epsg), auto_epsg = as.integer(auto_epsg), mode = "configured", warning = warning, center_lon = center_lon, center_lat = center_lat)
}
replace_formula_lhs <- function(formula_obj, lhs_name) {
  rhs <- paste(deparse(formula_obj[[3]]), collapse = " ")
  as.formula(paste(bt(lhs_name), "~", rhs))
}
ask_output_name <- function(target_name = "run") {
  if (exists("RUN_NAME_OVERRIDE") && !is.null(RUN_NAME_OVERRIDE) && nzchar(as.character(RUN_NAME_OVERRIDE))) {
    return(safe_name(as.character(RUN_NAME_OVERRIDE)))
  }

  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  default_base <- OUTPUT_NAME_PREFIX
  target_name <- safe_name(target_name)

  if (isTRUE(ASK_OUTPUT_FOLDER)) {
    cat("\nNhập tên dự án/output nếu muốn, rồi nhấn Enter.\n")
    cat("Có thể bỏ trống; khi bỏ trống folder sẽ là: ", target_name, "-", timestamp, "\n", sep = "")
    cat("Nếu nhập tên, folder sẽ là: <ten_du_an>_", target_name, "-", timestamp, "\n", sep = "")
    cat("Tên dự án/output: ")

    ans <- tryCatch(
      readLines(con = "stdin", n = 1),
      error = function(e) ""
    )

    if (length(ans) == 0 || is.na(ans)) ans <- ""
  } else {
    ans <- default_base
  }

  ans <- safe_name(trimws(ans))
  if (nzchar(ans)) {
    paste0(ans, "_", target_name, "-", timestamp)
  } else {
    paste0(target_name, "-", timestamp)
  }
}

make_output_folders <- function(out_dir) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "01_clean_data"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "02_regression_model"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "03_variogram"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "04_kriging_residual"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "05_final_rk"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "06_report"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "06_report", "tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "06_report", "json"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "06_report", "figures"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "06_report", "interactive"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "06_report", "logs"), recursive = TRUE, showWarnings = FALSE)
}

out_path <- function(...) {
  file.path(OUT_DIR, ...)
}

get_vgm_params <- function(vgm_obj) {
  nugget <- 0

  nug_rows <- which(as.character(vgm_obj$model) == "Nug")
  if (length(nug_rows) > 0) {
    nugget <- vgm_obj$psill[nug_rows[1]]
  }

  struct <- vgm_obj[as.character(vgm_obj$model) != "Nug", , drop = FALSE]

  if (nrow(struct) == 0) {
    return(list(
      model = "Nug",
      nugget = nugget,
      psill = 0,
      range = 0
    ))
  }

  return(list(
    model = as.character(struct$model[1]),
    nugget = nugget,
    psill = struct$psill[1],
    range = struct$range[1]
  ))
}

variogram_practical_range <- function(model, range) {
  model <- as.character(model %||% "")
  range <- suppressWarnings(as.numeric(range))
  if (!is.finite(range)) return(NA_real_)
  if (identical(model, "Exp")) return(3 * range)
  if (identical(model, "Gau")) return(sqrt(3) * range)
  range
}

variogram_candidate_score <- function(sse, params, experimental_vgm, singular = FALSE) {
  nugget <- suppressWarnings(as.numeric(params$nugget %||% NA_real_))
  psill <- suppressWarnings(as.numeric(params$psill %||% NA_real_))
  total_sill <- nugget + psill
  nugget_sill <- if (is.finite(total_sill) && total_sill > 0) nugget / total_sill else NA_real_
  practical <- variogram_practical_range(params$model, params$range)
  range_hit <- is.finite(params$range) && params$range >= 0.98 * VARIOGRAM_RANGE_MAX
  practical_ratio <- if (is.finite(practical) && is.finite(VARIOGRAM_CUTOFF) &&
      VARIOGRAM_CUTOFF > 0) practical / VARIOGRAM_CUTOFF else NA_real_
  nugget_penalty <- if (!is.finite(nugget_sill)) 0.5 else
    pmin(1, pmax(0, (nugget_sill - 0.50) / 0.50))
  range_penalty <- if (range_hit) 1 else if (is.finite(practical_ratio))
    pmin(1, pmax(0, (practical_ratio - 0.60) / 0.40)) else 0.5
  low_pair_fraction <- 0
  if ("np" %in% names(experimental_vgm) && nrow(experimental_vgm) > 0) {
    low_pair_fraction <- mean(experimental_vgm$np < MIN_PAIRS_PER_VARIOGRAM_BIN, na.rm = TRUE)
  }
  flags <- character(0)
  if (isTRUE(singular)) flags <- c(flags, "singular_fit")
  if (nugget_penalty > 0) flags <- c(flags, "high_nugget_sill")
  if (range_hit) flags <- c(flags, "range_hits_max")
  if (is.finite(practical_ratio) &&
      practical_ratio > MAX_PRACTICAL_RANGE_FACTOR_OF_CUTOFF) {
    flags <- c(flags, "practical_range_near_cutoff")
  }
  if (low_pair_fraction > 0) flags <- c(flags, "low_lag_pairs")
  list(
    nugget_penalty = nugget_penalty,
    range_penalty = range_penalty,
    lag_penalty = pmin(1, low_pair_fraction),
    singular_penalty = as.numeric(isTRUE(singular)),
    diagnostic_flags = paste(unique(flags), collapse = ";"),
    nugget_sill_ratio = nugget_sill,
    practical_range = practical,
    range_hit_max = range_hit,
    sse_per_pair = sse / max(sum(experimental_vgm$np %||% 1, na.rm = TRUE), 1)
  )
}

make_pure_nugget_variogram <- function(values,
    reason = "no_valid_structured_candidate") {
  nugget <- suppressWarnings(stats::var(values, na.rm = TRUE))
  if (!is.finite(nugget) || nugget < 0) nugget <- 0
  model <- gstat::vgm(psill = nugget, model = "Nug", range = 0)
  attr(model, "pure_nugget") <- TRUE
  attr(model, "fallback_reason") <- reason
  attr(model, "singular") <- FALSE
  model
}

is_pure_nugget_variogram <- function(model,
    threshold = PURE_NUGGET_RATIO_THRESHOLD) {
  if (is.null(model)) return(FALSE)
  if (isTRUE(attr(model, "pure_nugget"))) return(TRUE)
  params <- get_vgm_params(model)
  sill <- params$nugget + params$psill
  ratio <- if (is.finite(sill) && sill > 0) params$nugget / sill else NA_real_
  identical(params$model, "Nug") ||
    (!is.finite(sill) || sill <= 0) ||
    (is.finite(ratio) && ratio >= threshold)
}

fit_variogram_auto_select <- function(experimental_vgm, residual_values,
    candidate_models = VARIOGRAM_CANDIDATE_MODELS) {
  residual_var <- var(residual_values, na.rm = TRUE)
  if (is.na(residual_var) || residual_var <= 0) residual_var <- 1
  candidates <- expand.grid(
    model = unique(as.character(candidate_models)),
    range_factor = VARIOGRAM_INITIAL_RANGE_FACTORS,
    nugget_factor = VARIOGRAM_INITIAL_NUGGET_FACTORS,
    psill_factor = VARIOGRAM_INITIAL_PSILL_FACTORS,
    stringsAsFactors = FALSE
  )
  result_rows <- list()
  fit_objects <- list()

  for (i in seq_len(nrow(candidates))) {
    m <- candidates$model[i]
    init_range <- max(VARIOGRAM_RANGE_MIN,
      min(VARIOGRAM_CUTOFF * candidates$range_factor[i], VARIOGRAM_RANGE_MAX))
    init_nugget <- residual_var * candidates$nugget_factor[i]
    init_psill <- residual_var * candidates$psill_factor[i]
    init_model <- vgm(
      psill = init_psill, model = m, range = init_range, nugget = init_nugget)
    fit_try <- NULL
    invisible(utils::capture.output({
      fit_try <- suppressWarnings(try(
        fit.variogram(experimental_vgm, model = init_model, fit.method = 7),
        silent = TRUE
      ))
    }))
    if (inherits(fit_try, "try-error")) next
    if (any(is.na(fit_try$psill)) || any(is.na(fit_try$range)) ||
        any(fit_try$psill < 0, na.rm = TRUE) || any(fit_try$range < 0, na.rm = TRUE)) next

    params <- get_vgm_params(fit_try)
    sse <- suppressWarnings(as.numeric(attr(fit_try, "SSErr")))
    if (!is.finite(sse)) next
    singular <- isTRUE(attr(fit_try, "singular"))
    in_range <- is.finite(params$range) &&
      params$range >= VARIOGRAM_RANGE_MIN && params$range <= VARIOGRAM_RANGE_MAX
    diagnostics <- variogram_candidate_score(
      sse, params, experimental_vgm, singular = singular)
    accepted <- !singular && in_range
    row_id <- length(result_rows) + 1L
    result_rows[[row_id]] <- data.frame(
      model = m, init_range = init_range, init_nugget = init_nugget,
      init_psill = init_psill, fitted_model = params$model,
      fitted_nugget = params$nugget, fitted_psill = params$psill,
      fitted_range = params$range,
      practical_range = diagnostics$practical_range,
      nugget_sill_ratio = diagnostics$nugget_sill_ratio,
      range_hit_max = diagnostics$range_hit_max,
      sse = sse, sse_per_pair = diagnostics$sse_per_pair,
      nugget_penalty = diagnostics$nugget_penalty,
      range_penalty = diagnostics$range_penalty,
      lag_penalty = diagnostics$lag_penalty,
      singular = singular, converged = !singular,
      fit_method = 7L, n_iterations = NA_integer_,
      accepted = accepted,
      status = if (accepted) "valid" else if (singular) "singular_rejected" else "range_rejected",
      diagnostic_flags = diagnostics$diagnostic_flags,
      stringsAsFactors = FALSE
    )
    fit_objects[[row_id]] <- if (accepted) fit_try else NULL
  }

  if (length(result_rows) == 0) {
    return(list(
      fitted = make_pure_nugget_variogram(
        residual_values, "all_structured_candidates_failed"),
      table = data.frame(),
      fallback = "pure_nugget"
    ))
  }
  results <- do.call(rbind, result_rows)
  results$sse_rank <- NA_real_
  results$candidate_score <- Inf
  valid <- which(results$accepted & is.finite(results$sse_per_pair))
  if (length(valid) == 0) {
    pure_vgm <- make_pure_nugget_variogram(
      residual_values, "no_valid_structured_candidate")
    pure_params <- get_vgm_params(pure_vgm)
    pure_level <- pure_params$nugget
    weights <- if ("np" %in% names(experimental_vgm)) {
      pmax(suppressWarnings(as.numeric(experimental_vgm$np)), 1)
    } else {
      rep(1, nrow(experimental_vgm))
    }
    pure_sse <- sum(
      weights * (experimental_vgm$gamma - pure_level)^2,
      na.rm = TRUE
    )
    fallback_row <- data.frame(
      model = "Nug", init_range = 0, init_nugget = pure_level,
      init_psill = 0, fitted_model = "Nug",
      fitted_nugget = pure_level, fitted_psill = 0,
      fitted_range = 0, practical_range = 0,
      nugget_sill_ratio = 1, range_hit_max = FALSE,
      sse = pure_sse,
      sse_per_pair = pure_sse / max(sum(weights, na.rm = TRUE), 1),
      nugget_penalty = 1, range_penalty = 0,
      lag_penalty = mean(
        experimental_vgm$np < MIN_PAIRS_PER_VARIOGRAM_BIN,
        na.rm = TRUE
      ),
      singular = FALSE, converged = TRUE,
      fit_method = NA_integer_, n_iterations = NA_integer_,
      accepted = FALSE, status = "pure_nugget_fallback",
      diagnostic_flags =
        "no_valid_structured_candidate;pure_nugget",
      sse_rank = NA_real_, candidate_score = 1,
      stringsAsFactors = FALSE
    )
    results <- rbind(results, fallback_row)
    return(list(
      fitted = pure_vgm,
      table = results[
        order(results$candidate_score, results$sse_per_pair),
        , drop = FALSE
      ],
      fallback = "pure_nugget"
    ))
  }
  sse_rank <- if (length(valid) == 1) 0 else
    (rank(results$sse_per_pair[valid], ties.method = "average") - 1) /
    (length(valid) - 1)
  results$sse_rank[valid] <- sse_rank
  results$candidate_score[valid] <-
    0.45 * sse_rank +
    0.25 * results$range_penalty[valid] +
    0.20 * results$nugget_penalty[valid] +
    0.10 * results$lag_penalty[valid]
  best_i <- valid[which.min(results$candidate_score[valid])]
  list(
    fitted = fit_objects[[best_i]],
    table = results[
      order(results$candidate_score, results$sse_per_pair),
      , drop = FALSE
    ],
    fallback = NULL
  )
}

metric_table <- function(observed, predicted, variance = NULL, model_name = "model", cv_method = "none") {
  ok <- !is.na(observed) & !is.na(predicted)
  n_total <- length(observed)
  n_pred <- sum(ok)
  empty_row <- function() {
    data.frame(
      cv_method = cv_method, model = model_name, n_total = n_total,
      n_predicted = 0, n_missing = n_total, ME = NA_real_, RMSE = NA_real_,
      MAE = NA_real_, R2 = NA_real_, NSE = NA_real_, standardized_RMSE = NA_real_,
      n_interval = 0L, interval_fraction = 0,
      coverage_95 = NA_real_, mean_standardized_error = NA_real_,
      variance_standardized_RMSE = NA_real_, interval_score_95 = NA_real_,
      Pearson = NA_real_, NRMSE_mean = NA_real_, NRMSE_range = NA_real_,
      RPD = NA_real_, RPIQ = NA_real_, stringsAsFactors = FALSE
    )
  }
  if (n_pred == 0) return(empty_row())

  y <- observed[ok]
  p <- predicted[ok]
  err <- p - y
  rmse_val <- sqrt(mean(err^2, na.rm = TRUE))
  mae_val <- mean(abs(err), na.rm = TRUE)
  ss_res <- sum(err^2, na.rm = TRUE)
  ss_tot <- sum((y - mean(y, na.rm = TRUE))^2, na.rm = TRUE)
  r2_val <- ifelse(ss_tot > 0, 1 - ss_res / ss_tot, NA_real_)
  obs_sd <- stats::sd(y, na.rm = TRUE)
  obs_mean <- mean(y, na.rm = TRUE)
  obs_range <- diff(range(y, na.rm = TRUE))
  obs_iqr <- stats::IQR(y, na.rm = TRUE)
  std_rmse <- ifelse(obs_sd > 0, rmse_val / obs_sd, NA_real_)
  pearson_val <- suppressWarnings(stats::cor(y, p, use = "complete.obs"))
  nrmse_mean_val <- ifelse(abs(obs_mean) > 0, rmse_val / abs(obs_mean), NA_real_)
  nrmse_range_val <- ifelse(obs_range > 0, rmse_val / obs_range, NA_real_)
  rpd_val <- ifelse(rmse_val > 0, obs_sd / rmse_val, NA_real_)
  rpiq_val <- ifelse(rmse_val > 0, obs_iqr / rmse_val, NA_real_)
  n_interval <- 0L
  interval_fraction <- 0
  coverage <- mean_std_err <- variance_std_rmse <- interval_score <- NA_real_

  if (!is.null(variance)) {
    v <- suppressWarnings(as.numeric(variance[ok]))
    v_ok <- is.finite(v) & v > 0
    if (any(v_ok)) {
      n_interval <- sum(v_ok)
      interval_fraction <- n_interval / max(n_pred, 1)
      s <- sqrt(v[v_ok])
      yy <- y[v_ok]
      pp <- p[v_ok]
      ee <- err[v_ok]
      lower <- pp - 1.96 * s
      upper <- pp + 1.96 * s
      coverage <- mean(yy >= lower & yy <= upper)
      z <- ee / s
      mean_std_err <- mean(z, na.rm = TRUE)
      variance_std_rmse <- sqrt(mean(z^2, na.rm = TRUE))
      alpha <- 0.05
      interval_score <- mean(
        (upper - lower) +
          (2 / alpha) * (lower - yy) * (yy < lower) +
          (2 / alpha) * (yy - upper) * (yy > upper),
        na.rm = TRUE
      )
    }
  }

  data.frame(
    cv_method = cv_method, model = model_name, n_total = n_total,
    n_predicted = n_pred, n_missing = n_total - n_pred,
    ME = mean(err, na.rm = TRUE), RMSE = rmse_val, MAE = mae_val,
    R2 = r2_val, NSE = r2_val, standardized_RMSE = std_rmse,
    n_interval = n_interval, interval_fraction = interval_fraction,
    coverage_95 = coverage, mean_standardized_error = mean_std_err,
    variance_standardized_RMSE = variance_std_rmse,
    interval_score_95 = interval_score,
    Pearson = pearson_val, NRMSE_mean = nrmse_mean_val,
    NRMSE_range = nrmse_range_val, RPD = rpd_val, RPIQ = rpiq_val,
    stringsAsFactors = FALSE
  )
}

practical_range <- function(vgm_obj) {
  params <- get_vgm_params(vgm_obj)
  if (params$model == "Exp") {
    return(3 * params$range)
  }
  if (params$model == "Gau") {
    return(sqrt(3) * params$range)
  }
  return(params$range)
}

compute_vif_table <- function(df, predictors) {
  present <- predictors[predictors %in% names(df)]
  if (length(present) < 2) {
    return(data.frame(predictor = present, VIF = NA_real_))
  }

  cm <- suppressWarnings(cor(df[, present, drop = FALSE], use = "pairwise.complete.obs"))
  inv <- try(solve(cm), silent = TRUE)

  if (inherits(inv, "try-error")) {
    return(data.frame(predictor = present, VIF = NA_real_))
  }

  data.frame(
    predictor = present,
    VIF = as.numeric(diag(inv)),
    stringsAsFactors = FALSE
  )
}

nearest_neighbor_table <- function(points_sf) {
  xy <- st_coordinates(points_sf)
  if (nrow(xy) < 2) {
    return(data.frame(min_m = NA_real_, median_m = NA_real_, mean_m = NA_real_, max_m = NA_real_))
  }

  d <- as.matrix(stats::dist(xy))
  diag(d) <- NA_real_
  nn <- apply(d, 1, min, na.rm = TRUE)

  data.frame(
    min_m = min(nn, na.rm = TRUE),
    median_m = stats::median(nn, na.rm = TRUE),
    mean_m = mean(nn, na.rm = TRUE),
    max_m = max(nn, na.rm = TRUE)
  )
}

fit_variogram_for_cv <- function(sp_points, formula_obj, values,
    candidate_models = VARIOGRAM_CANDIDATE_MODELS, allow_fallback = TRUE,
    cressie = isTRUE(VARIOGRAM_ROBUST_CRESSIE)) {
  exp_try <- suppressWarnings(try(
    variogram(
      formula_obj, sp_points, cutoff = VARIOGRAM_CUTOFF,
      width = VARIOGRAM_WIDTH, cressie = cressie
    ),
    silent = TRUE
  ))
  if (inherits(exp_try, "try-error") || nrow(exp_try) == 0) return(NULL)

  auto_result <- fit_variogram_auto_select(
    experimental_vgm = exp_try, residual_values = values,
    candidate_models = candidate_models
  )
  if (!is.null(auto_result$fitted) &&
      !isTRUE(attr(auto_result$fitted, "singular"))) {
    return(auto_result$fitted)
  }
  if (!isTRUE(allow_fallback)) return(NULL)

  value_var <- var(values, na.rm = TRUE)
  if (is.na(value_var) || value_var <= 0) value_var <- 1
  fallback_model <- as.character(candidate_models[1] %||% VARIOGRAM_MODEL)
  init_vgm <- vgm(
    psill = value_var * 0.8, model = fallback_model,
    range = min(max(MANUAL_RANGE, VARIOGRAM_RANGE_MIN), VARIOGRAM_RANGE_MAX),
    nugget = value_var * 0.1
  )
  fit_try <- suppressWarnings(try(
    fit.variogram(exp_try, model = init_vgm, fit.method = 7),
    silent = TRUE
  ))
  if (inherits(fit_try, "try-error") || isTRUE(attr(fit_try, "singular")) ||
      any(is.na(fit_try$psill)) || any(is.na(fit_try$range)) ||
      any(fit_try$psill < 0, na.rm = TRUE) ||
      any(fit_try$range < 0, na.rm = TRUE)) {
    return(NULL)
  }
  fit_try
}

make_fold_ids <- function(points_sf, method, k, seed) {
  if (method %in% c("buffer", "nndm")) {
    stop(paste0(
      method,
      " uses explicit train/test lists and is supported as CV_OUTER_METHOD, not as a secondary CV_METHODS entry."
    ))
  }
  plan <- rk_make_cv_plan(
    points_sf, method, k, seed,
    block_size = CV_OUTER_BLOCK_SIZE %||% "auto",
    prediction_raster = if (exists("template_raster")) template_raster else NULL
  )
  plan$fold_ids
}

run_cv_comparison <- function(model_df, points_sf, regression_formula, target_field, cv_method, manual_vgm, target_model_field = target_field, target_transform = "none", log_bias_correction = FALSE) {
  fold_ids <- make_fold_ids(
    points_sf = points_sf,
    method = cv_method,
    k = CV_K_FOLDS,
    seed = CV_RANDOM_SEED
  )

  xy <- st_coordinates(points_sf)
  df <- model_df
  df$.x <- xy[, 1]
  df$.y <- xy[, 2]

  pred_reg_model <- rep(NA_real_, nrow(df))
  pred_ok_model <- rep(NA_real_, nrow(df))
  pred_rk_model <- rep(NA_real_, nrow(df))
  var_ok <- rep(NA_real_, nrow(df))
  var_rk <- rep(NA_real_, nrow(df))

  fold_rows <- list()
  fold_idx <- 1

  for (fold in sort(unique(fold_ids))) {
    test_idx <- which(fold_ids == fold)
    train_idx <- which(fold_ids != fold)

    train_df <- df[train_idx, , drop = FALSE]
    test_df <- df[test_idx, , drop = FALSE]

    reg_try <- try(lm(regression_formula, data = train_df), silent = TRUE)
    if (inherits(reg_try, "try-error")) {
      next
    }

    pred_reg_model[test_idx] <- as.numeric(predict(reg_try, newdata = test_df))
    train_df$.residual <- train_df[[target_model_field]] - as.numeric(predict(reg_try, newdata = train_df))

    train_sp <- train_df
    test_sp <- test_df
    coordinates(train_sp) <- ~.x + .y
    coordinates(test_sp) <- ~.x + .y
    proj4string(train_sp) <- CRS(SRS_string = paste0("EPSG:", UTM_EPSG))
    proj4string(test_sp) <- CRS(SRS_string = paste0("EPSG:", UTM_EPSG))

    ok_vgm <- manual_vgm
    rk_vgm <- manual_vgm
    ok_vgm_status <- "manual_fallback"
    rk_vgm_status <- "manual_fallback"

    if (isTRUE(CV_REFIT_VARIOGRAM)) {
      target_formula <- as.formula(paste(bt(target_model_field), "~ 1"))
      ok_fit <- fit_variogram_for_cv(train_sp, target_formula, train_df[[target_model_field]])
      rk_fit <- fit_variogram_for_cv(train_sp, .residual ~ 1, train_df$.residual)

      if (!is.null(ok_fit)) {
        ok_vgm <- ok_fit
        ok_vgm_status <- "refit"
      }
      if (!is.null(rk_fit)) {
        rk_vgm <- rk_fit
        rk_vgm_status <- "refit"
      }
    }

    cv_maxdist <- if (isTRUE(CV_REQUIRE_KRIGING_NEIGHBORS)) SEARCH_RADIUS else Inf

    ok_try <- suppressWarnings(
      try(
        krige(
          formula = as.formula(paste(bt(target_model_field), "~ 1")),
          locations = train_sp,
          newdata = test_sp,
          model = ok_vgm,
          nmax = NMAX_NEIGHBORS,
          maxdist = cv_maxdist
        ),
        silent = TRUE
      )
    )

    rk_try <- suppressWarnings(
      try(
        krige(
          formula = .residual ~ 1,
          locations = train_sp,
          newdata = test_sp,
          model = rk_vgm,
          nmax = NMAX_NEIGHBORS,
          maxdist = cv_maxdist
        ),
        silent = TRUE
      )
    )

    if (!inherits(ok_try, "try-error")) {
      pred_ok_model[test_idx] <- ok_try$var1.pred
      var_ok[test_idx] <- ok_try$var1.var
    }

    if (!inherits(rk_try, "try-error")) {
      pred_rk_model[test_idx] <- pred_reg_model[test_idx] + rk_try$var1.pred
      var_rk[test_idx] <- rk_try$var1.var
    }

    fold_rows[[fold_idx]] <- data.frame(
      cv_method = cv_method,
      fold = fold,
      n_train = length(train_idx),
      n_test = length(test_idx),
      ok_variogram_status = ok_vgm_status,
      rk_variogram_status = rk_vgm_status,
      ok_missing = sum(is.na(pred_ok_model[test_idx])),
      rk_missing = sum(is.na(pred_rk_model[test_idx])),
      stringsAsFactors = FALSE
    )
    fold_idx <- fold_idx + 1
  }

  observed <- df[[target_field]]
  var_ok_model <- var_ok
  var_rk_model <- var_rk
  pred_reg <- rk_back_transform_values(pred_reg_model, target_transform)
  pred_ok <- rk_back_transform_values(pred_ok_model, target_transform, variance = var_ok_model, bias_correction = log_bias_correction)
  pred_rk <- rk_back_transform_values(pred_rk_model, target_transform, variance = var_rk_model, bias_correction = log_bias_correction)
  var_ok <- rk_back_transform_variance_values(var_ok_model, pred_ok_model, target_transform, bias_correction = log_bias_correction)
  var_rk <- rk_back_transform_variance_values(var_rk_model, pred_rk_model, target_transform, bias_correction = log_bias_correction)

  summary <- rbind(
    metric_table(observed, pred_reg, NULL, "Regression-only", cv_method),
    metric_table(observed, pred_ok, var_ok, "Ordinary Kriging", cv_method),
    metric_table(observed, pred_rk, var_rk, "Regression Kriging", cv_method)
  )

  predictions <- data.frame(
    point_id = if (CODE_COL %in% names(df)) df[[CODE_COL]] else seq_len(nrow(df)),
    code = if (CODE_COL %in% names(df)) df[[CODE_COL]] else seq_len(nrow(df)),
    cv_method = cv_method,
    fold = fold_ids,
    x = df$.x,
    y = df$.y,
    lon = if (LON_COL %in% names(df)) df[[LON_COL]] else NA_real_,
    lat = if (LAT_COL %in% names(df)) df[[LAT_COL]] else NA_real_,
    observed = observed,
    regression_only = pred_reg,
    ordinary_kriging = pred_ok,
    regression_kriging = pred_rk,
    ok_variance = var_ok,
    rk_residual_variance = var_rk,
    rk_residual_variance_model_scale = var_rk_model,
    stringsAsFactors = FALSE
  )

  fold_report <- if (length(fold_rows) > 0) do.call(rbind, fold_rows) else data.frame()

  list(
    summary = summary,
    predictions = predictions,
    folds = fold_report
  )
}
auto_select_neighbors <- function(model_df, points_sf, regression_formula, target_field, manual_vgm, target_model_field = target_field, target_transform = "none", log_bias_correction = FALSE) {
  if (!isTRUE(AUTO_NEIGHBORS) || !isTRUE(RUN_CROSS_VALIDATION)) {
    return(list(selected_nmax = NMAX_NEIGHBORS, selected_radius = SEARCH_RADIUS, table = data.frame(), method = "disabled"))
  }

  n_candidates <- unique(as.integer(AUTO_NEIGHBOR_NMAX_CANDIDATES))
  r_candidates <- unique(as.numeric(AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES))
  n_candidates <- n_candidates[is.finite(n_candidates) & n_candidates > 0]
  r_candidates <- r_candidates[is.finite(r_candidates) & r_candidates > 0]
  if (length(n_candidates) == 0 || length(r_candidates) == 0) {
    return(list(selected_nmax = NMAX_NEIGHBORS, selected_radius = SEARCH_RADIUS, table = data.frame(), method = "fallback_empty_candidates"))
  }

  candidate_grid <- expand.grid(
    nmax_neighbors = n_candidates,
    search_radius = r_candidates,
    stringsAsFactors = FALSE
  )
  candidate_grid <- candidate_grid[order(candidate_grid$nmax_neighbors, candidate_grid$search_radius), , drop = FALSE]
  if (exists("AUTO_NEIGHBOR_MAX_CANDIDATES") && is.finite(AUTO_NEIGHBOR_MAX_CANDIDATES)) {
    candidate_grid <- head(candidate_grid, AUTO_NEIGHBOR_MAX_CANDIDATES)
  }

  old_nmax <- NMAX_NEIGHBORS
  old_radius <- SEARCH_RADIUS
  on.exit({
    NMAX_NEIGHBORS <<- old_nmax
    SEARCH_RADIUS <<- old_radius
  }, add = TRUE)

  cv_method <- AUTO_NEIGHBOR_CV_METHOD
  if (!(cv_method %in% CV_METHODS)) cv_method <- if ("spatial_kmeans" %in% CV_METHODS) "spatial_kmeans" else CV_METHODS[1]

  rows <- list()
  for (i in seq_len(nrow(candidate_grid))) {
    NMAX_NEIGHBORS <<- candidate_grid$nmax_neighbors[i]
    SEARCH_RADIUS <<- candidate_grid$search_radius[i]

    cv_try <- try(
      run_cv_comparison(
        model_df = model_df,
        points_sf = points_sf,
        regression_formula = regression_formula,
        target_field = target_field,
        cv_method = cv_method,
        manual_vgm = manual_vgm,
        target_model_field = target_model_field,
        target_transform = target_transform,
        log_bias_correction = log_bias_correction
      ),
      silent = TRUE
    )

    if (inherits(cv_try, "try-error")) {
      rows[[length(rows) + 1]] <- data.frame(
        nmax_neighbors = NMAX_NEIGHBORS,
        search_radius = SEARCH_RADIUS,
        cv_method = cv_method,
        n_predicted = 0,
        n_missing = nrow(model_df),
        RK_RMSE = NA_real_,
        RK_MAE = NA_real_,
        RK_ME = NA_real_,
        RK_R2_pred = NA_real_,
        score = Inf,
        status = "cv_failed",
        stringsAsFactors = FALSE
      )
      next
    }

    rk_row <- cv_try$summary[cv_try$summary$model == "Regression Kriging", , drop = FALSE]
    if (nrow(rk_row) == 0) {
      rows[[length(rows) + 1]] <- data.frame(
        nmax_neighbors = NMAX_NEIGHBORS,
        search_radius = SEARCH_RADIUS,
        cv_method = cv_method,
        n_predicted = 0,
        n_missing = nrow(model_df),
        RK_RMSE = NA_real_,
        RK_MAE = NA_real_,
        RK_ME = NA_real_,
        RK_R2_pred = NA_real_,
        score = Inf,
        status = "no_rk_result",
        stringsAsFactors = FALSE
      )
      next
    }

    rmse <- rk_row$RMSE[1]
    me <- rk_row$ME[1]
    r2 <- if ("R2" %in% names(rk_row)) rk_row$R2[1] else NA_real_
    n_missing <- rk_row$n_missing[1]
    missing_rate <- n_missing / max(1, rk_row$n_total[1])
    score_scale <- if (is.finite(rmse) && rmse > 0) rmse else max(stats::sd(model_df[[target_field]], na.rm = TRUE), 1e-9)
    vg_params <- tryCatch(get_vgm_params(manual_vgm), error = function(e) NULL)
    practical_range <- if (!is.null(vg_params)) variogram_practical_range(vg_params$model, vg_params$range) else NA_real_
    score_penalty <- 0
    if (is.finite(r2) && r2 < 0) score_penalty <- score_penalty + score_scale * min(0.35, 0.10 + abs(r2) * 0.05)
    if (is.finite(practical_range) && practical_range > 0) {
      if (SEARCH_RADIUS > 1.75 * practical_range) score_penalty <- score_penalty + score_scale * 0.12
      if (SEARCH_RADIUS < 0.45 * practical_range) score_penalty <- score_penalty + score_scale * 0.08
    }
    if (NMAX_NEIGHBORS > max(24, 0.30 * nrow(model_df))) score_penalty <- score_penalty + score_scale * 0.05
    if (NMAX_NEIGHBORS > max(32, 0.45 * nrow(model_df))) score_penalty <- score_penalty + score_scale * 0.10
    score <- rmse + 0.25 * abs(me) + missing_rate * score_scale + score_penalty
    if (!is.finite(score)) score <- Inf

    rows[[length(rows) + 1]] <- data.frame(
      nmax_neighbors = NMAX_NEIGHBORS,
      search_radius = SEARCH_RADIUS,
      cv_method = cv_method,
      n_predicted = rk_row$n_predicted[1],
      n_missing = n_missing,
      RK_RMSE = rmse,
      RK_MAE = rk_row$MAE[1],
      RK_ME = me,
      RK_R2_pred = r2,
      score = score,
      status = "ok",
      stringsAsFactors = FALSE
    )
  }

  out <- if (length(rows) > 0) do.call(rbind, rows) else data.frame()
  valid <- out[is.finite(out$score) & out$status == "ok", , drop = FALSE]
  if (nrow(valid) == 0) {
    return(list(selected_nmax = old_nmax, selected_radius = old_radius, table = out, method = "fallback_no_valid_candidate"))
  }

  best <- valid[order(valid$score, valid$n_missing, valid$RK_RMSE, valid$nmax_neighbors), , drop = FALSE][1, ]
  list(
    selected_nmax = as.integer(best$nmax_neighbors),
    selected_radius = as.numeric(best$search_radius),
    table = out,
    method = cv_method
  )
}
write_variogram_html <- function(experimental_vgm, fitted_vgm, html_file) {
  params <- get_vgm_params(fitted_vgm)

  dist_vec <- paste(round(experimental_vgm$dist, 6), collapse = ",")
  gamma_vec <- paste(round(experimental_vgm$gamma, 6), collapse = ",")
  np_vec <- paste(experimental_vgm$np, collapse = ",")

  html <- c(
'<!DOCTYPE html>',
'<html lang="vi">',
'<head>',
'<meta charset="UTF-8">',
'<title>Interactive Variogram</title>',
'<style>',
'body{font-family:Arial, sans-serif;margin:20px;background:#f7f7f7;color:#222;}',
'.wrap{display:grid;grid-template-columns:760px 380px;gap:20px;align-items:start;}',
'.card{background:white;border:1px solid #ddd;border-radius:10px;padding:15px;box-shadow:0 1px 4px rgba(0,0,0,.08);}',
'canvas{background:white;border:1px solid #ccc;border-radius:8px;}',
'label{display:block;margin-top:10px;font-weight:bold;}',
'input,select,button,textarea{width:100%;box-sizing:border-box;padding:7px;margin-top:4px;}',
'button{cursor:pointer;font-weight:bold;}',
'pre{background:#111;color:#0f0;padding:10px;white-space:pre-wrap;border-radius:8px;}',
'.small{font-size:13px;color:#555;}',
'</style>',
'</head>',
'<body>',
'<h2>Interactive Residual Variogram</h2>',
'<p class="small">Dung file nay de xem va ghi lai cac thong so variogram de review. Hay chay lai bang launcher cua du an; khong sua cac file loi noi bo.</p>',
'<div class="wrap">',
'<div class="card">',
'<canvas id="plot" width="740" height="500"></canvas>',
'<p id="status"></p>',
'</div>',
'<div class="card">',
'<label>Model</label>',
'<select id="model"><option>Exp</option><option>Sph</option><option>Gau</option></select>',
'<label>Nugget</label><input id="nugget" type="number" step="0.001">',
'<label>Partial sill / Psill</label><input id="psill" type="number" step="0.001">',
'<label>Range parameter, meter</label><input id="range" type="number" step="10">',
'<label>Range search min, meter</label><input id="rangeMin" type="number" step="100">',
'<label>Range search max, meter</label><input id="rangeMax" type="number" step="100">',
'<button onclick="update()">Update chart</button>',
'<button onclick="optimize()">Find best params in range</button>',
'<h3>Config to copy</h3>',
'<pre id="configBlock"></pre>',
'</div>',
'</div>',
'<script>',
paste0('const dist=[', dist_vec, '];'),
paste0('const gamma=[', gamma_vec, '];'),
paste0('const np=[', np_vec, '];'),
'const data = dist.map((d,i)=>({h:d,g:gamma[i],np:np[i]}));',
paste0('document.getElementById("model").value="', params$model, '";'),
paste0('document.getElementById("nugget").value=', round(params$nugget, 6), ';'),
paste0('document.getElementById("psill").value=', round(params$psill, 6), ';'),
paste0('document.getElementById("range").value=', round(params$range, 6), ';'),
paste0('document.getElementById("rangeMin").value=', VARIOGRAM_RANGE_MIN, ';'),
paste0('document.getElementById("rangeMax").value=', VARIOGRAM_RANGE_MAX, ';'),
'function modelGamma(h, model, nugget, psill, range){',
'  if(range<=0) return NaN;',
'  if(model==="Sph"){',
'    if(h>=range) return nugget+psill;',
'    let x=h/range; return nugget+psill*(1.5*x-0.5*x*x*x);',
'  }',
'  if(model==="Gau"){',
'    return nugget+psill*(1-Math.exp(-Math.pow(h/range,2)));',
'  }',
'  return nugget+psill*(1-Math.exp(-h/range));',
'}',
'function weightedSSE(model,nugget,psill,range){',
'  let s=0,wSum=0;',
'  for(const p of data){',
'    let pred=modelGamma(p.h,model,nugget,psill,range);',
'    let w=Math.max(1,p.np);',
'    s+=w*Math.pow(p.g-pred,2);',
'    wSum+=w;',
'  }',
'  return s/Math.max(1,wSum);',
'}',
'function getVals(){',
'  return {',
'    model:document.getElementById("model").value,',
'    nugget:parseFloat(document.getElementById("nugget").value),',
'    psill:parseFloat(document.getElementById("psill").value),',
'    range:parseFloat(document.getElementById("range").value)',
'  };',
'}',
'function update(){',
'  const v=getVals();',
'  const canvas=document.getElementById("plot");',
'  const ctx=canvas.getContext("2d");',
'  ctx.clearRect(0,0,canvas.width,canvas.height);',
'  const pad=55;',
'  const maxH=Math.max(...dist)*1.05;',
'  const modelMax=v.nugget+v.psill;',
'  const maxG=Math.max(...gamma, modelMax)*1.15;',
'  function X(h){return pad+h/maxH*(canvas.width-pad-20);}',
'  function Y(g){return canvas.height-pad-g/maxG*(canvas.height-pad-20);}',
'  ctx.strokeStyle="#333";ctx.lineWidth=1;',
'  ctx.beginPath();ctx.moveTo(pad,20);ctx.lineTo(pad,canvas.height-pad);ctx.lineTo(canvas.width-20,canvas.height-pad);ctx.stroke();',
'  ctx.fillStyle="#333";ctx.font="13px Arial";',
'  ctx.fillText("distance (m)",canvas.width/2,canvas.height-15);',
'  ctx.save();ctx.translate(15,canvas.height/2);ctx.rotate(-Math.PI/2);ctx.fillText("semivariance",0,0);ctx.restore();',
'  ctx.fillStyle="#1f77b4";',
'  for(const p of data){',
'    const r=3+Math.min(7,Math.sqrt(Math.max(1,p.np))/2);',
'    ctx.beginPath();ctx.arc(X(p.h),Y(p.g),r,0,Math.PI*2);ctx.fill();',
'  }',
'  ctx.strokeStyle="#d62728";ctx.lineWidth=2;ctx.beginPath();',
'  for(let i=0;i<=250;i++){',
'    const h=maxH*i/250;',
'    const g=modelGamma(h,v.model,v.nugget,v.psill,v.range);',
'    if(i===0) ctx.moveTo(X(h),Y(g)); else ctx.lineTo(X(h),Y(g));',
'  }',
'  ctx.stroke();',
'  ctx.strokeStyle="#999";ctx.setLineDash([5,5]);',
'  ctx.beginPath();ctx.moveTo(X(v.range),20);ctx.lineTo(X(v.range),canvas.height-pad);ctx.stroke();ctx.setLineDash([]);',
'  const sse=weightedSSE(v.model,v.nugget,v.psill,v.range);',
'  document.getElementById("status").innerHTML = "Model: <b>"+v.model+"</b> | Nugget: <b>"+v.nugget.toFixed(4)+"</b> | Psill: <b>"+v.psill.toFixed(4)+"</b> | Range: <b>"+v.range.toFixed(1)+" m</b> | weighted SSE: <b>"+sse.toFixed(6)+"</b>";',
'  document.getElementById("configBlock").textContent =',
'    "VARIOGRAM_MODE <- \\"manual\\"\\n" +',
'    "VARIOGRAM_MODEL <- \\"" + v.model + "\\"\\n" +',
'    "MANUAL_NUGGET <- " + v.nugget.toFixed(6) + "\\n" +',
'    "MANUAL_PSILL  <- " + v.psill.toFixed(6) + "\\n" +',
'    "MANUAL_RANGE  <- " + v.range.toFixed(2) + "\\n";',
'}',
'function optimize(){',
'  const model=document.getElementById("model").value;',
'  const rMin=parseFloat(document.getElementById("rangeMin").value);',
'  const rMax=parseFloat(document.getElementById("rangeMax").value);',
'  const gMax=Math.max(...gamma);',
'  let best={sse:Infinity,nugget:0,psill:gMax,range:rMin};',
'  for(let ri=0;ri<=60;ri++){',
'    const range=rMin+(rMax-rMin)*ri/60;',
'    for(let ni=0;ni<=30;ni++){',
'      const nugget=gMax*0.5*ni/30;',
'      for(let si=1;si<=50;si++){',
'        const psill=gMax*1.5*si/50;',
'        const sse=weightedSSE(model,nugget,psill,range);',
'        if(sse<best.sse){best={sse,nugget,psill,range};}',
'      }',
'    }',
'  }',
'  document.getElementById("nugget").value=best.nugget.toFixed(6);',
'  document.getElementById("psill").value=best.psill.toFixed(6);',
'  document.getElementById("range").value=best.range.toFixed(2);',
'  update();',
'}',
'document.querySelectorAll("input,select").forEach(el=>el.addEventListener("input",update));',
'update();',
'</script>',
'</body>',
'</html>'
  )

  con <- file(html_file, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(paste(html, collapse = "\n")), con)
}

check_file(POINT_FILE)

RASTER_FILES <- detect_pc_files()
PREDICTORS <- names(RASTER_FILES)

for (f in RASTER_FILES) {
  check_file(f)
}


cat("[1] Read soil point CSV...\n")

pts_raw <- read.csv(
  POINT_FILE,
  stringsAsFactors = FALSE,
  check.names = FALSE
)

bom <- rawToChar(as.raw(c(0xef, 0xbb, 0xbf)))
names(pts_raw) <- trimws(sub(paste0("^", bom), "", names(pts_raw), useBytes = TRUE))

required_coord_cols <- c(LAT_COL, LON_COL)
missing_coord_cols <- setdiff(required_coord_cols, names(pts_raw))

if (length(missing_coord_cols) > 0) {
  stop(paste0("Missing coordinate columns: ", paste(missing_coord_cols, collapse = ", ")))
}

if (!(CODE_COL %in% names(pts_raw))) {
  pts_raw[[CODE_COL]] <- paste0("P", sprintf("%03d", seq_len(nrow(pts_raw))))
}

analysis_cols <- setdiff(names(pts_raw), c(CODE_COL, LAT_COL, LON_COL))

if (length(analysis_cols) == 0) {
  stop("No analysis columns found after code/lat/lon.")
}

if (is.null(TARGET_FIELD) || TARGET_FIELD == "auto") {
  if (length(analysis_cols) == 1) {
    TARGET_FIELD <- analysis_cols[1]
  } else {
    stop(paste0(
      "CSV has many analysis columns: ",
      paste(analysis_cols, collapse = ", "),
      ". Run the project interpolation launcher so populated indicators are processed automatically; do not run the internal engine directly."
    ))
  }
} else {
  if (!(TARGET_FIELD %in% analysis_cols)) {
    stop(paste0(
      "TARGET_FIELD does not exist in CSV analysis columns. Available: ",
      paste(analysis_cols, collapse = ", ")
    ))
  }
}

TARGET_NAME <- safe_name(TARGET_FIELD)

RUN_NAME <- ask_output_name(TARGET_NAME)
OUT_DIR <- file.path(OUTPUT_ROOT, RUN_NAME)
make_output_folders(OUT_DIR)
cat("\nOutput run folder: ", OUT_DIR, "\n\n", sep = "")

log_file <- out_path("06_report", "logs", paste0("run_log_", TARGET_NAME, ".txt"))
con <- file(log_file, open = "wb")
log_header <- paste0("Regression Kriging log - ", Sys.time(), "\n")
writeBin(charToRaw(log_header), con)
close(con)

log_msg <- function(...) {
  txt <- paste0(..., collapse = "")
  Encoding(txt) <- "UTF-8"
  cat(txt, "\n")
  con <- file(log_file, open = "ab")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(paste0(txt, "\n")), con)
}

scientific_messages <- character(0)
scientific_warnings <- character(0)
scientific_hard_failures <- character(0)

add_science_message <- function(message) {
  scientific_messages <<- unique(c(scientific_messages, message))
  log_msg("INFO: ", message)
}
add_science_warning <- function(message) {
  scientific_warnings <<- unique(c(scientific_warnings, message))
  log_msg("WARNING: ", message)
}
add_science_hard_failure <- function(message) {
  scientific_hard_failures <<- unique(c(scientific_hard_failures, message))
  log_msg("HARD-FAIL: ", message)
}

load_target_metadata <- function(path, target_field) {
  if (is.null(path) || !file.exists(path)) return(list())
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("TARGET_METADATA_FILE exists but package yaml is not installed.")
  }
  root <- yaml::read_yaml(path)
  targets <- root$targets %||% root
  metadata <- targets[[target_field]] %||% list()
  if (!is.list(metadata)) stop("Target metadata entry must be a YAML object.")
  metadata
}
target_metadata_active <- load_target_metadata(
  TARGET_METADATA_FILE %||% "", TARGET_FIELD)
TARGET_PROFILE_OVERRIDE <- if (
    rk_eval_has_metadata_value(target_metadata_active$profile_name)) {
  as.character(target_metadata_active$profile_name[1])
} else NULL
if (length(target_metadata_active) > 0) {
  add_science_message(paste0(
    "Đã đọc metadata cho ", TARGET_FIELD,
    if (rk_eval_has_metadata_value(TARGET_PROFILE_OVERRIDE))
      paste0("; profile override = ", TARGET_PROFILE_OVERRIDE) else "."
  ))
} else {
  add_science_message(
    "Chưa có target metadata YAML; profile/classification chỉ được xem là rule nội bộ.")
}
point_support_path <- if (exists("POINT_SUPPORT_METADATA_FILE")) {
  as.character(POINT_SUPPORT_METADATA_FILE %||% "")
} else {
  ""
}
point_support_inside_raw <- rep(NA, nrow(pts_raw))
point_support_metadata_loaded <- FALSE
point_support_manual_raw <- rep(NA_character_, nrow(pts_raw))
point_support_target_raw <- rep(NA_character_, nrow(pts_raw))
point_support_sampling_raw <- rep(NA_character_, nrow(pts_raw))
point_support_include_raw <- rep(NA, nrow(pts_raw))
point_support_role_raw <- rep(NA_character_, nrow(pts_raw))
point_support_schema <- "required: code, inside_roi; optional governance: manual_assessment_status, target_population_status, sampling_support_status, include_in_model_development, analysis_role"

parse_inside_roi <- function(x) {
  value <- tolower(trimws(as.character(x)))
  out <- rep(NA, length(value))
  out[value %in% c("true", "t", "1", "yes", "y", "inside", "in")] <- TRUE
  out[value %in% c("false", "f", "0", "no", "n", "outside", "out")] <- FALSE
  out
}

if (nzchar(point_support_path)) {
  if (!file.exists(point_support_path)) {
    add_science_warning(paste0(
      "POINT_SUPPORT_METADATA_FILE không tồn tại: ", point_support_path,
      ". Không thể thống kê inside/outside ROI trong engine."
    ))
  } else {
    support_df <- read.csv(
      point_support_path, stringsAsFactors = FALSE, check.names = FALSE)
    clean_names <- tolower(trimws(names(support_df)))
    support_code_idx <- match(tolower(CODE_COL), clean_names)
    if (is.na(support_code_idx)) support_code_idx <- match("code", clean_names)
    support_inside_idx <- match("inside_roi", clean_names)
    if (is.na(support_code_idx) || is.na(support_inside_idx)) {
      add_science_warning(paste0(
        "POINT_SUPPORT_METADATA_FILE sai schema; cần ", point_support_schema,
        ". File chỉ dùng cho provenance/QA, không dùng làm target."
      ))
    } else {
      support_code <- trimws(as.character(support_df[[support_code_idx]]))
      duplicate_support <- duplicated(support_code)
      if (any(duplicate_support)) {
        add_science_warning(paste0(
          "POINT_SUPPORT_METADATA_FILE có code trùng; chỉ dùng bản ghi đầu tiên ",
          "cho mỗi code."
        ))
        support_df <- support_df[!duplicate_support, , drop = FALSE]
        support_code <- support_code[!duplicate_support]
      }
      inside_values <- parse_inside_roi(support_df[[support_inside_idx]])
      support_value <- function(column) {
        idx <- match(column, clean_names)
        if (is.na(idx)) return(rep(NA_character_, nrow(support_df)))
        value <- trimws(as.character(support_df[[idx]]))
        value[!nzchar(value)] <- NA_character_
        value
      }
      manual_values <- support_value("manual_assessment_status")
      target_values <- support_value("target_population_status")
      sampling_values <- support_value("sampling_support_status")
      include_values <- parse_inside_roi(
        support_value("include_in_model_development"))
      role_values <- support_value("analysis_role")
      invalid_inside <- !is.na(support_df[[support_inside_idx]]) &
        nzchar(trimws(as.character(support_df[[support_inside_idx]]))) &
        is.na(inside_values)
      if (any(invalid_inside)) {
        add_science_warning(paste0(
          sum(invalid_inside),
          " giá trị inside_roi không hợp lệ; ghi nhận ROI membership = unknown."
        ))
      }
      matched_support <- match(
        trimws(as.character(pts_raw[[CODE_COL]])), support_code)
      point_support_inside_raw <- inside_values[matched_support]
      point_support_manual_raw <- manual_values[matched_support]
      point_support_target_raw <- target_values[matched_support]
      point_support_sampling_raw <- sampling_values[matched_support]
      point_support_include_raw <- include_values[matched_support]
      point_support_role_raw <- role_values[matched_support]
      point_support_metadata_loaded <- TRUE
      if (any(is.na(matched_support))) {
        add_science_warning(paste0(
          sum(is.na(matched_support)),
          " điểm không có bản ghi trong POINT_SUPPORT_METADATA_FILE."
        ))
      }
      add_science_message(paste0(
        "Đã đọc point-support metadata; inside ROI = ",
        sum(point_support_inside_raw %in% TRUE), ", outside ROI = ",
        sum(point_support_inside_raw %in% FALSE),
        ". ROI membership chỉ mô tả support, không tạo validation set."
      ))
    }
  }
}

raster_manifest <- data.frame(
  layer = PREDICTORS,
  file = unname(RASTER_FILES),
  type = "continuous",
  resampling = "bilinear",
  provenance = "PC raster assumed continuous",
  stringsAsFactors = FALSE
)
if (file.exists(RASTER_MANIFEST_FILE)) {
  manifest_input <- read.csv(
    RASTER_MANIFEST_FILE, stringsAsFactors = FALSE, check.names = FALSE)
  required_manifest <- c("layer", "type", "resampling")
  missing_manifest <- setdiff(required_manifest, names(manifest_input))
  if (length(missing_manifest) > 0) {
    stop(paste0(
      "Raster manifest thiếu cột: ", paste(missing_manifest, collapse = ", ")))
  }
  for (i in seq_len(nrow(raster_manifest))) {
    hit <- which(
      manifest_input$layer == raster_manifest$layer[i] |
        ("file" %in% names(manifest_input) &
          basename(manifest_input$file) == basename(raster_manifest$file[i]))
    )
    if (length(hit) > 0) {
      row <- manifest_input[hit[1], , drop = FALSE]
      raster_manifest$type[i] <- tolower(as.character(row$type[1]))
      raster_manifest$resampling[i] <- tolower(as.character(row$resampling[1]))
      if ("provenance" %in% names(row)) {
        raster_manifest$provenance[i] <- as.character(row$provenance[1])
      }
    }
  }
  add_science_message(paste0(
    "Đã áp dụng raster manifest: ", RASTER_MANIFEST_FILE))
} else {
  add_science_message(
    "Không có raster manifest; mọi PC*.tif được coi là continuous PCA score và resample bilinear.")
}
if (any(!raster_manifest$type %in% c("continuous", "categorical"))) {
  stop("Raster manifest type must be continuous or categorical.")
}
raster_manifest$resampling[raster_manifest$type == "categorical"] <- "near"
if (any(!raster_manifest$resampling %in% c("bilinear", "near"))) {
  stop("Raster manifest resampling must be bilinear or near.")
}
write.csv(
  raster_manifest,
  out_path("01_clean_data", "raster_manifest_used.csv"),
  row.names = FALSE, fileEncoding = "UTF-8"
)
if (any(raster_manifest$type == "categorical")) {
  add_science_warning(
    "Có raster categorical: đã dùng nearest-neighbor resampling; cần đảm bảo formula xử lý mã lớp đúng ngữ nghĩa.")
}
first_resampling_method <- raster_manifest$resampling[
  match(names(RASTER_FILES)[1], raster_manifest$layer)]

log_msg("Run name: ", RUN_NAME)
log_msg("Output folder: ", OUT_DIR)
log_msg("Target field: ", TARGET_FIELD)
log_msg("Analysis columns: ", paste(analysis_cols, collapse = ", "))
log_msg("Detected PC rasters: ", paste(PREDICTORS, collapse = ", "))
log_msg("Number of PC rasters: ", length(PREDICTORS))
log_msg("UTM EPSG config: ", UTM_EPSG)
log_msg("Variogram mode: ", VARIOGRAM_MODE)
log_msg("Manual variogram: model=", VARIOGRAM_MODEL, ", nugget=", MANUAL_NUGGET, ", psill=", MANUAL_PSILL, ", range=", MANUAL_RANGE)
log_msg("Variogram cutoff: ", VARIOGRAM_CUTOFF)
log_msg("Variogram width: ", VARIOGRAM_WIDTH)
log_msg("Kriging nmax: ", NMAX_NEIGHBORS)
log_msg("Kriging search radius: ", SEARCH_RADIUS)
log_msg("Run cross-validation: ", RUN_CROSS_VALIDATION)
if (isTRUE(RUN_CROSS_VALIDATION)) {
  log_msg("CV methods: ", paste(CV_METHODS, collapse = ", "))
  log_msg("CV folds: ", CV_K_FOLDS)
  log_msg("CV refit variogram: ", CV_REFIT_VARIOGRAM)
}

pts_raw[[LON_COL]] <- suppressWarnings(as.numeric(pts_raw[[LON_COL]]))
pts_raw[[LAT_COL]] <- suppressWarnings(as.numeric(pts_raw[[LAT_COL]]))
pts_raw[[TARGET_FIELD]] <- suppressWarnings(as.numeric(pts_raw[[TARGET_FIELD]]))

valid_idx <- !is.na(pts_raw[[LON_COL]]) &
  !is.na(pts_raw[[LAT_COL]]) &
  !is.na(pts_raw[[TARGET_FIELD]])

point_support_inside_valid <- point_support_inside_raw[valid_idx]
pts_raw <- pts_raw[valid_idx, ]
point_support_manual_valid <- point_support_manual_raw[valid_idx]
point_support_target_valid <- point_support_target_raw[valid_idx]
point_support_sampling_valid <- point_support_sampling_raw[valid_idx]
point_support_include_valid <- point_support_include_raw[valid_idx]
point_support_role_valid <- point_support_role_raw[valid_idx]

if (nrow(pts_raw) < 5) {
  stop("Too few valid points after NA filtering. Need at least 5 points.")
}

utm_resolution <- resolve_utm_epsg(pts_raw, LON_COL, LAT_COL, UTM_EPSG)
UTM_EPSG <- utm_resolution$epsg
if (!is.null(utm_resolution$warning)) add_science_warning(utm_resolution$warning)
log_msg("UTM centroid lon/lat: ", round(utm_resolution$center_lon, 6), ", ", round(utm_resolution$center_lat, 6))
log_msg("UTM EPSG active: ", UTM_EPSG, " (mode=", utm_resolution$mode, ", auto_suggestion=", utm_resolution$auto_epsg, ")")

pts_sf <- st_as_sf(pts_raw,
  coords = c(LON_COL, LAT_COL),
  crs = 4326,
  remove = FALSE
)

target_crs <- paste0("EPSG:", UTM_EPSG)
pts_utm <- st_transform(pts_sf, target_crs)

log_msg("\n[2] ROI step skipped. Points will be filtered only by valid PC raster pixels.")
log_msg("PC rasters are assumed to be pre-masked/cropped with the desired buffer.")
log_msg("Valid coordinate points: ", nrow(pts_utm))

log_msg("\n[3] Create raster template from PC rasters...")

first_r <- rast(RASTER_FILES[[1]])
first_r <- first_r[[1]]

if (is.na(terra::crs(first_r))) {
  stop(paste0("First raster has no CRS: ", RASTER_FILES[[1]]))
}

if (is.character(OUTPUT_RESOLUTION) && tolower(OUTPUT_RESOLUTION) == "auto") {
  log_msg("Output resolution mode: auto from first detected PC raster")

  template_raster <- project(
    first_r,
    target_crs,
    method = first_resampling_method
  )
} else {
  out_res <- suppressWarnings(as.numeric(OUTPUT_RESOLUTION))

  if (is.na(out_res) || out_res <= 0) {
    stop("OUTPUT_RESOLUTION must be numeric or 'auto'.")
  }

  first_utm_base <- project(first_r, target_crs, method = first_resampling_method)

  base_template <- rast(
    ext(first_utm_base),
    resolution = out_res,
    crs = target_crs
  )

  template_raster <- project(first_utm_base, base_template, method = first_resampling_method)
}

template_res <- res(template_raster)

log_msg("Template resolution X: ", round(template_res[1], 4), " m")
log_msg("Template resolution Y: ", round(template_res[2], 4), " m")
log_msg("Template cells: ", ncell(template_raster))

writeRaster(
  template_raster,
  out_path("01_clean_data", "template_from_first_pc_utm.tif"),
  overwrite = TRUE
)

log_msg("\n[4] Read and align all detected PC rasters...")

raster_list <- list()

for (nm in names(RASTER_FILES)) {
  f <- RASTER_FILES[[nm]]
  log_msg("Processing raster: ", nm, " -> ", f)

  r <- rast(f)

  if (is.na(terra::crs(r))) {
    stop(paste0("Raster has no CRS: ", f))
  }

  r <- r[[1]]

  resampling_method <- raster_manifest$resampling[
    match(nm, raster_manifest$layer)
  ]
  r_utm <- project(
    r,
    template_raster,
    method = resampling_method
  )

  names(r_utm) <- nm
  raster_list[[nm]] <- r_utm
}

covs_utm <- rast(raster_list)
names(covs_utm) <- PREDICTORS

if (isTRUE(USE_COMPLETE_PC_MASK)) {
  valid_count <- app(!is.na(covs_utm), sum)
  complete_pc_mask <- ifel(valid_count == nlyr(covs_utm), 1, NA)
  names(complete_pc_mask) <- "complete_pc_mask"
  covs_utm <- mask(covs_utm, complete_pc_mask)
} else {
  complete_pc_mask <- ifel(!is.na(covs_utm[[1]]), 1, NA)
  names(complete_pc_mask) <- "first_pc_mask"
}

writeRaster(
  covs_utm,
  out_path("01_clean_data", "covariates_utm.tif"),
  overwrite = TRUE
)

writeRaster(
  complete_pc_mask,
  out_path("01_clean_data", "pc_valid_mask_utm.tif"),
  overwrite = TRUE
)

valid_pc_cells <- global(complete_pc_mask, "sum", na.rm = TRUE)[1, 1]

log_msg("Raster predictors used: ", paste(names(covs_utm), collapse = ", "))
log_msg("Number of predictors used: ", nlyr(covs_utm))
log_msg("Valid PC cells: ", valid_pc_cells)

if (is.na(valid_pc_cells) || valid_pc_cells < 1) {
  stop("No valid PC cells found. Check PC rasters.")
}

log_msg("\n[5] Extract PC values at sample points...")

extract_values <- terra::extract(covs_utm, vect(pts_utm))

model_df_all <- cbind(
  st_drop_geometry(pts_utm),
  extract_values[, -1, drop = FALSE]
)

keep_cols <- c(TARGET_FIELD, PREDICTORS)
missing_model_cols <- setdiff(keep_cols, names(model_df_all))

if (length(missing_model_cols) > 0) {
  stop(paste0("Missing model columns: ", paste(missing_model_cols, collapse = ", ")))
}

complete_idx <- complete.cases(model_df_all[, keep_cols])

model_df <- model_df_all[complete_idx, ]
pts_model_sf <- pts_utm[complete_idx, ]
point_support_inside_model <- point_support_inside_valid[complete_idx]
point_support_manual_model <- point_support_manual_valid[complete_idx]
point_support_target_model <- point_support_target_valid[complete_idx]
point_support_sampling_model <- point_support_sampling_valid[complete_idx]
point_support_include_model <- point_support_include_valid[complete_idx]
point_support_role_model <- point_support_role_valid[complete_idx]

support_status_confirmed <- function(x) {
  value <- tolower(trimws(as.character(x)))
  positive <- grepl(
    "confirm|approv|accept|reviewed|complete|eligible|in.?scope|supported",
    value
  )
  negative <- grepl(
    "pending|unconfirm|unknown|not.?review|exclude|reject|sensitivity",
    value
  )
  !is.na(value) & nzchar(value) & positive & !negative
}
outside_model_idx <- which(point_support_inside_model %in% FALSE)
manual_confirmed <- support_status_confirmed(point_support_manual_model)
target_confirmed <- support_status_confirmed(point_support_target_model)
sampling_confirmed <- support_status_confirmed(point_support_sampling_model)
role_value <- tolower(trimws(as.character(point_support_role_model)))
role_primary <- rk_eval_primary_model_role(role_value)
role_validation <- !is.na(role_value) &
  grepl("validation|holdout|test", role_value)
role_sensitivity <- !is.na(role_value) &
  grepl("sensitivity", role_value)
outside_review_ok <- manual_confirmed & target_confirmed &
  sampling_confirmed & (point_support_include_model %in% TRUE) &
  role_primary
outside_pending_idx <- outside_model_idx[
  !outside_review_ok[outside_model_idx]]
outside_include_false_idx <- outside_model_idx[
  point_support_include_model[outside_model_idx] %in% FALSE]
outside_validation_label_idx <- outside_model_idx[
  role_validation[outside_model_idx]]
outside_sensitivity_idx <- outside_model_idx[
  role_sensitivity[outside_model_idx]]
outside_review_gate_passed <- length(outside_pending_idx) == 0
roi_known <- any(!is.na(point_support_inside_model))
n_inside_roi_model <- if (roi_known) {
  sum(point_support_inside_model %in% TRUE)
} else NA_integer_
n_outside_roi_model <- if (roi_known) {
  sum(point_support_inside_model %in% FALSE)
} else NA_integer_
point_support_summary <- list(
  metadata_available = point_support_metadata_loaded,
  metadata_file = if (point_support_metadata_loaded) {
    normalizePath(point_support_path, winslash = "/", mustWork = FALSE)
  } else {
    NA_character_
  },
  metadata_schema = point_support_schema,
  n_model_points = nrow(model_df),
  n_inside_roi_model = n_inside_roi_model,
  n_outside_roi_model = n_outside_roi_model,
  n_roi_membership_unknown = sum(is.na(point_support_inside_model)),
  model_point_role = "model_development_training_and_outer_cv",
  outside_roi_model_policy =
    "included_when_target_and_all_model_covariates_are_complete",
  outside_roi_points_are_validation = FALSE,
  independent_field_validation_sample = FALSE,
  roi_membership_role = "provenance_and_target_population_diagnostic_only",
  prediction_domain =
    "complete_covariate_raster_support; final_ROI_mask_applied_by_project_workflow",
  aoa_reference_points =
    "all_model_development_points_with_complete_target_and_covariates",
  outside_review_gate_passed = outside_review_gate_passed,
  n_outside_pending_review = length(outside_pending_idx),
  n_outside_include_false_in_primary = length(outside_include_false_idx),
  n_outside_labeled_validation = length(outside_validation_label_idx),
  n_outside_sensitivity_role_in_primary = length(outside_sensitivity_idx),
  primary_product_eligible = outside_review_gate_passed,
  sensitivity_analysis_eligible = TRUE,
  governance_policy =
    "outside points remain model-development only; pending/false flags force DRAFT and block auto-ACCEPT"
)
point_support_model_table <- data.frame(
  code = as.character(model_df[[CODE_COL]]),
  inside_roi = point_support_inside_model,
  manual_assessment_status = point_support_manual_model,
  target_population_status = point_support_target_model,
  sampling_support_status = point_support_sampling_model,
  include_in_model_development = point_support_include_model,
  declared_analysis_role = point_support_role_model,
  sample_role = "model_development",
  used_as_independent_validation = FALSE,
  stringsAsFactors = FALSE
)
write.csv(
  point_support_model_table,
  out_path("01_clean_data",
    paste0("model_point_support_", TARGET_NAME, ".csv")),
  row.names = FALSE, fileEncoding = "UTF-8"
)
if (is.finite(n_outside_roi_model) && n_outside_roi_model > 0) {
  add_science_message(paste0(
    n_outside_roi_model,
    " điểm ngoài ROI được giữ làm model-development vì đủ target/covariate; ",
    "không được gọi là validation points."
  ))
}
if (length(outside_pending_idx) > 0) {
  add_science_hard_failure(paste0(
    length(outside_pending_idx),
    " điểm ngoài ROI trong primary input chưa đạt manual/target-population/",
    "sampling-support/include/analysis-role gate. Continuous model vẫn chạy ",
    "để QA/sensitivity nhưng product phải DRAFT_PENDING_OUTSIDE_REVIEW."
  ))
}
if (length(outside_include_false_idx) > 0) {
  add_science_hard_failure(paste0(
    length(outside_include_false_idx),
    " điểm ngoài ROI có include_in_model_development=false nhưng vẫn xuất hiện ",
    "trong primary input; không được auto-ACCEPT làm final candidate."
  ))
  add_science_warning(
    "Các điểm include=false chỉ đủ điều kiện cho sensitivity analysis cho tới khi được phê duyệt lại."
  )
}
if (length(outside_validation_label_idx) > 0) {
  add_science_hard_failure(paste0(
    length(outside_validation_label_idx),
    " điểm ngoài ROI mang analysis_role validation/holdout/test. Engine bỏ ngữ ",
    "nghĩa validation: các điểm này vẫn không phải independent field validation."
  ))
}
if (length(outside_sensitivity_idx) > 0) {
  add_science_warning(paste0(
    length(outside_sensitivity_idx),
    " điểm ngoài ROI có sensitivity role nhưng nằm trong primary input; ",
    "primary product bị chặn, chỉ sensitivity candidate có thể được xem xét."
  ))
}
write.csv(
  model_df,
  out_path("01_clean_data", paste0("clean_points_", TARGET_NAME, ".csv")),
  row.names = FALSE
)

log_msg("Points used for model: ", nrow(model_df))

if (nrow(model_df) < 5) {
  stop("Too few valid points after PC raster extraction.")
}

sample_min <- min(model_df[[TARGET_FIELD]], na.rm = TRUE)
sample_max <- max(model_df[[TARGET_FIELD]], na.rm = TRUE)

log_msg("Sample min: ", round(sample_min, 4))
log_msg("Sample max: ", round(sample_max, 4))

sample_xy <- st_coordinates(pts_model_sf)
coordinate_key <- paste(round(sample_xy[, 1], 3), round(sample_xy[, 2], 3), sep = "_")
duplicate_keys <- unique(coordinate_key[duplicated(coordinate_key)])
if (length(duplicate_keys) > 0) {
  duplicate_rows <- do.call(rbind, lapply(duplicate_keys, function(key) {
    idx <- which(coordinate_key == key)
    data.frame(
      coordinate_key = key,
      row_index = idx,
      sample_code = if (CODE_COL %in% names(model_df))
        as.character(model_df[[CODE_COL]][idx]) else as.character(idx),
      target_value = model_df[[TARGET_FIELD]][idx],
      stringsAsFactors = FALSE
    )
  }))
  write.csv(
    duplicate_rows,
    out_path("01_clean_data",
      paste0("duplicate_coordinates_", TARGET_NAME, ".csv")),
    row.names = FALSE, fileEncoding = "UTF-8"
  )
  conflicting_keys <- vapply(duplicate_keys, function(key) {
    values <- model_df[[TARGET_FIELD]][coordinate_key == key]
    values <- values[is.finite(values)]
    length(values) > 1 && diff(range(values)) >
      1e-8 * max(1, max(abs(values)))
  }, logical(1))
  if (any(conflicting_keys)) {
    message <- paste0(
      "Có ", sum(conflicting_keys),
      " tọa độ trùng nhưng giá trị ", TARGET_FIELD,
      " xung đột và không có metadata replicate. Pipeline dừng; không jitter hoặc gộp âm thầm.")
    add_science_hard_failure(message)
    if (identical(DUPLICATE_COORDINATE_POLICY, "stop_conflicts")) stop(message)
  } else {
    add_science_warning(
      "Có tọa độ trùng với giá trị giống nhau; cần khai báo laboratory/field replicate trước khi phân tích chính thức.")
  }
}

target_transform_info <- resolve_target_transform(TARGET_FIELD, model_df[[TARGET_FIELD]])
TARGET_TRANSFORM_ACTIVE <- target_transform_info$selected
LOG_BACKTRANSFORM_BIAS_CORRECTION_ACTIVE <- isTRUE(LOG_BACKTRANSFORM_BIAS_CORRECTION) && identical(TARGET_TRANSFORM_ACTIVE, "log1p")
MODEL_TARGET_FIELD <- ".rk_target_model"
model_df[[MODEL_TARGET_FIELD]] <- rk_transform_values(model_df[[TARGET_FIELD]], TARGET_TRANSFORM_ACTIVE)
pts_model_sf[[MODEL_TARGET_FIELD]] <- model_df[[MODEL_TARGET_FIELD]]
if (!is.null(target_transform_info$warning)) add_science_warning(target_transform_info$warning)
log_msg("Target transform requested: ", target_transform_info$requested)
log_msg("Target transform used: ", TARGET_TRANSFORM_ACTIVE)
log_msg("Log back-transform bias correction: ", LOG_BACKTRANSFORM_BIAS_CORRECTION_ACTIVE)
log_msg("Transform profile: ", target_transform_info$profile_name)
log_msg("Transform reason: ", target_transform_info$recommendation$reason %||% "")

if (nrow(model_df) < MIN_SAMPLE_POINTS_WARNING) {
  add_science_warning(paste0(
    "Chỉ có ", nrow(model_df), " điểm dùng cho mô hình; spatial validation và fitting variogram có thể không ổn định."
  ))
}

vif_table <- compute_vif_table(model_df, PREDICTORS)
write.csv(
  vif_table,
  out_path("02_regression_model", paste0("predictor_vif_", TARGET_NAME, ".csv")),
  row.names = FALSE
)

if (any(!is.na(vif_table$VIF) & vif_table$VIF > 5)) {
  add_science_warning("Một số biến dự báo có VIF > 5; hệ số hồi quy có thể không ổn định do đa cộng tuyến.")
}

nn_table <- nearest_neighbor_table(pts_model_sf)
write.csv(
  nn_table,
  out_path("01_clean_data", paste0("sample_spacing_", TARGET_NAME, ".csv")),
  row.names = FALSE
)

log_msg("Nearest-neighbor median distance: ", round(nn_table$median_m[1], 2), " m")
log_msg("Nearest-neighbor max distance: ", round(nn_table$max_m[1], 2), " m")

if (!is.na(nn_table$median_m[1]) && max(template_res) < nn_table$median_m[1] / 50) {
  add_science_warning(paste0(
    "Độ phân giải output (", round(max(template_res), 2), " m) mịn hơn nhiều so với khoảng cách trung vị giữa các điểm mẫu (",
    round(nn_table$median_m[1], 2), " m); chi tiết trên bản đồ có thể trông chính xác hơn mức dữ liệu mẫu hỗ trợ."
  ))
}

log_msg("\n[6] Fit regression model...")

if (is.null(REGRESSION_FORMULA)) {
  formula_text <- paste(
    bt(MODEL_TARGET_FIELD),
    "~",
    paste(PREDICTORS, collapse = " + ")
  )

  regression_formula <- as.formula(formula_text)
} else {
  regression_formula <- replace_formula_lhs(REGRESSION_FORMULA, MODEL_TARGET_FIELD)
}

log_msg("Regression formula: ", deparse(regression_formula))
log_msg("Regression target scale: ", ifelse(identical(TARGET_TRANSFORM_ACTIVE, "none"), "original", TARGET_TRANSFORM_ACTIVE))

n_regression_predictors <- length(attr(stats::terms(regression_formula), "term.labels"))
samples_per_predictor <- nrow(model_df) / max(n_regression_predictors, 1)
if (samples_per_predictor < REGRESSION_MIN_SAMPLES_PER_PREDICTOR_HARD_FAIL) {
  add_science_hard_failure(paste0(
    "Tỷ lệ n/p = ", round(samples_per_predictor, 2),
    " < ", REGRESSION_MIN_SAMPLES_PER_PREDICTOR_HARD_FAIL,
    "; trend model có nguy cơ overfit nghiêm trọng và không được auto-ACCEPT."
  ))
} else if (samples_per_predictor < REGRESSION_MIN_SAMPLES_PER_PREDICTOR_WARNING) {
  add_science_warning(paste0(
    "Tỷ lệ n/p = ", round(samples_per_predictor, 2),
    " < ", REGRESSION_MIN_SAMPLES_PER_PREDICTOR_WARNING,
    "; hệ số trend có thể không ổn định."
  ))
}

reg_model <- lm(regression_formula, data = model_df)
model_matrix <- stats::model.matrix(reg_model)
condition_number <- tryCatch(kappa(model_matrix, exact = TRUE),
  error = function(e) NA_real_)
leverage <- stats::hatvalues(reg_model)
cooks <- stats::cooks.distance(reg_model)
studentized <- tryCatch(stats::rstudent(reg_model),
  error = function(e) rep(NA_real_, nrow(model_df)))
bp_test <- if (requireNamespace("lmtest", quietly = TRUE)) {
  suppressWarnings(try(lmtest::bptest(reg_model), silent = TRUE))
} else {
  NULL
}
bp_statistic <- if (!is.null(bp_test) &&
    !inherits(bp_test, "try-error")) {
  suppressWarnings(as.numeric(bp_test$statistic))
} else {
  NA_real_
}
bp_df <- if (!is.null(bp_test) && !inherits(bp_test, "try-error")) {
  suppressWarnings(as.numeric(bp_test$parameter))
} else {
  NA_real_
}
bp_p_value <- if (!is.null(bp_test) &&
    !inherits(bp_test, "try-error")) {
  suppressWarnings(as.numeric(bp_test$p.value))
} else {
  NA_real_
}
residual_for_normality <- stats::residuals(reg_model)
shapiro_p_value <- if (length(residual_for_normality) >= 3 &&
    length(residual_for_normality) <= 5000) {
  tryCatch(
    stats::shapiro.test(residual_for_normality)$p.value,
    error = function(e) NA_real_
  )
} else {
  NA_real_
}
regression_influence <- data.frame(
  row_index = seq_len(nrow(model_df)),
  sample_code = if (CODE_COL %in% names(model_df))
    as.character(model_df[[CODE_COL]]) else as.character(seq_len(nrow(model_df))),
  fitted_model_scale = stats::fitted(reg_model),
  residual_model_scale = stats::residuals(reg_model),
  leverage = leverage, cooks_distance = cooks,
  studentized_residual = studentized, stringsAsFactors = FALSE
)
write.csv(
  regression_influence,
  out_path("02_regression_model",
    paste0("regression_influence_", TARGET_NAME, ".csv")),
  row.names = FALSE, fileEncoding = "UTF-8"
)
regression_diagnostics <- data.frame(
  n_samples = nrow(model_df), n_predictors = n_regression_predictors,
  samples_per_predictor = samples_per_predictor,
  model_matrix_rank = reg_model$rank,
  condition_number = condition_number,
  breusch_pagan_statistic = bp_statistic,
  breusch_pagan_df = bp_df,
  breusch_pagan_p_value = bp_p_value,
  shapiro_wilk_p_value = shapiro_p_value,
  high_leverage_count = sum(leverage > 2 * mean(leverage), na.rm = TRUE),
  influential_cooks_count = sum(cooks > 4 / nrow(model_df), na.rm = TRUE),
  stringsAsFactors = FALSE
)
write.csv(
  regression_diagnostics,
  out_path("02_regression_model",
    paste0("regression_diagnostics_", TARGET_NAME, ".csv")),
  row.names = FALSE, fileEncoding = "UTF-8"
)
if (is.finite(condition_number) && condition_number > 30) {
  add_science_warning(paste0(
    "Condition number = ", round(condition_number, 1),
    " cho thấy thiết kế hồi quy kém ổn định/đa cộng tuyến."
  ))
}
if (sum(cooks > 4 / nrow(model_df), na.rm = TRUE) >
    max(1, 0.05 * nrow(model_df))) {
  add_science_warning(
    paste0(
      "Nhiều điểm có Cook's distance lớn; cần kiểm tra ảnh hưởng điểm ",
      "và sai số phòng thí nghiệm."
    )
  )
}
if (is.finite(bp_p_value) && bp_p_value < 0.05) {
  add_science_warning(paste0(
    "Breusch-Pagan p = ", signif(bp_p_value, 3),
    " cho thấy phương sai phần dư trend có thể không đồng nhất."
  ))
}
if (is.finite(shapiro_p_value) && shapiro_p_value < 0.05) {
  add_science_warning(paste0(
    "Shapiro-Wilk p = ", signif(shapiro_p_value, 3),
    " cho thấy phần dư trend lệch chuẩn; cần xem histogram, outlier và transform."
  ))
}

model_df$reg_pred_model <- as.numeric(predict(reg_model, newdata = model_df))
model_df$reg_pred <- rk_back_transform_values(model_df$reg_pred_model, TARGET_TRANSFORM_ACTIVE)
model_df$residual <- model_df[[MODEL_TARGET_FIELD]] - model_df$reg_pred_model
model_df$residual_original <- model_df[[TARGET_FIELD]] - model_df$reg_pred

rmse <- sqrt(mean((model_df[[TARGET_FIELD]] - model_df$reg_pred)^2, na.rm = TRUE))
mae <- mean(abs(model_df[[TARGET_FIELD]] - model_df$reg_pred), na.rm = TRUE)

ss_res <- sum((model_df[[TARGET_FIELD]] - model_df$reg_pred)^2, na.rm = TRUE)
ss_tot <- sum((model_df[[TARGET_FIELD]] - mean(model_df[[TARGET_FIELD]], na.rm = TRUE))^2, na.rm = TRUE)

r2_pred <- 1 - ss_res / ss_tot

log_msg("Regression RMSE: ", round(rmse, 4))
log_msg("Regression MAE : ", round(mae, 4))
log_msg("Regression R2  : ", round(r2_pred, 4))

reg_adj_r2 <- summary(reg_model)$adj.r.squared
log_msg("Regression adjusted R2: ", round(reg_adj_r2, 4))

if (!is.na(r2_pred) && r2_pred < REGRESSION_R2_WARNING) {
  add_science_warning(paste0(
    "Regression R² thấp (", round(r2_pred, 3), "); các biến phụ trợ giải thích rất ít biến động của chỉ tiêu."
  ))
}

write.csv(
  model_df,
  out_path("02_regression_model", paste0("regression_points_", TARGET_NAME, ".csv")),
  row.names = FALSE
)

saveRDS(
  reg_model,
  out_path("02_regression_model", paste0("regression_model_", TARGET_NAME, ".rds"))
)

writeLines(
  c(
    "Regression model summary",
    paste0("Target: ", TARGET_FIELD),
    paste0("Formula: ", deparse(regression_formula)),
    paste0("Predictors: ", paste(PREDICTORS, collapse = ", ")),
    "",
    paste0("RMSE: ", round(rmse, 4)),
    paste0("MAE : ", round(mae, 4)),
    paste0("R2  : ", round(r2_pred, 4)),
    paste0("Adjusted R2: ", round(reg_adj_r2, 4)),
    "",
    capture.output(summary(reg_model))
  ),
  out_path("02_regression_model", paste0("regression_summary_", TARGET_NAME, ".txt"))
)

plot_file <- out_path("02_regression_model", paste0("observed_vs_predicted_", TARGET_NAME, ".png"))
png(plot_file, width = 1200, height = 900)
plot(
  model_df[[TARGET_FIELD]],
  model_df$reg_pred,
  pch = 19,
  xlab = "Observed",
  ylab = "Regression predicted",
  main = paste("Observed vs Predicted -", TARGET_FIELD)
)
abline(0, 1, col = "red", lwd = 2)
save_plot_done(plot_file)

plot_file <- out_path("02_regression_model", paste0("residual_histogram_", TARGET_NAME, ".png"))
png(plot_file, width = 1200, height = 900)
hist(
  model_df$residual,
  main = paste("Residual histogram - model scale -", TARGET_FIELD),
  xlab = paste0("Residual on ", ifelse(identical(TARGET_TRANSFORM_ACTIVE, "none"), "original", TARGET_TRANSFORM_ACTIVE), " scale")
)
save_plot_done(plot_file)

plot_file <- out_path("02_regression_model", paste0("residual_vs_predicted_", TARGET_NAME, ".png"))
png(plot_file, width = 1200, height = 900)
plot(
  model_df$reg_pred_model,
  model_df$residual,
  pch = 19,
  xlab = paste0("Regression predicted on ", ifelse(identical(TARGET_TRANSFORM_ACTIVE, "none"), "original", TARGET_TRANSFORM_ACTIVE), " scale"),
  ylab = paste0("Residual on ", ifelse(identical(TARGET_TRANSFORM_ACTIVE, "none"), "original", TARGET_TRANSFORM_ACTIVE), " scale"),
  main = paste("Residual vs Predicted - model scale -", TARGET_FIELD)
)
abline(h = 0, col = "red", lwd = 2)
save_plot_done(plot_file)

plot_file <- out_path("02_regression_model", paste0("residual_original_histogram_", TARGET_NAME, ".png"))
png(plot_file, width = 1200, height = 900)
hist(
  model_df$residual_original,
  main = paste("Residual histogram - original units -", TARGET_FIELD),
  xlab = "Residual on original units"
)
save_plot_done(plot_file)

plot_file <- out_path("02_regression_model", paste0("residual_original_vs_predicted_", TARGET_NAME, ".png"))
png(plot_file, width = 1200, height = 900)
plot(
  model_df$reg_pred,
  model_df$residual_original,
  pch = 19,
  xlab = "Regression predicted on original units",
  ylab = "Residual on original units",
  main = paste("Residual vs Predicted - original units -", TARGET_FIELD)
)
abline(h = 0, col = "red", lwd = 2)
save_plot_done(plot_file)

log_msg("\n[7] Fit residual variogram...")

pts_model_sf$residual <- model_df$residual
pts_sp <- as(pts_model_sf, "Spatial")

experimental_vgm <- variogram(
  residual ~ 1,
  pts_sp,
  cutoff = VARIOGRAM_CUTOFF,
  width = VARIOGRAM_WIDTH
)

if (nrow(experimental_vgm) == 0) {
  stop("Experimental variogram is empty. Increase VARIOGRAM_CUTOFF or check points.")
}

write.csv(
  experimental_vgm,
  out_path("03_variogram", paste0("experimental_variogram_", TARGET_NAME, ".csv")),
  row.names = FALSE
)

robust_vgm <- suppressWarnings(try(variogram(
  residual ~ 1, pts_sp, cutoff = VARIOGRAM_CUTOFF,
  width = VARIOGRAM_WIDTH, cressie = TRUE
), silent = TRUE))
robust_relative_difference <- NA_real_
if (!inherits(robust_vgm, "try-error") && nrow(robust_vgm) > 0) {
  write.csv(
    robust_vgm,
    out_path("03_variogram",
      paste0("experimental_variogram_cressie_", TARGET_NAME, ".csv")),
    row.names = FALSE, fileEncoding = "UTF-8"
  )
  matched <- merge(
    experimental_vgm[, c("dist", "gamma")],
    robust_vgm[, c("dist", "gamma")],
    by = "dist", suffixes = c("_classical", "_robust")
  )
  if (nrow(matched) > 0) {
    scale_gamma <- stats::median(
      abs(matched$gamma_classical), na.rm = TRUE)
    if (is.finite(scale_gamma) && scale_gamma > 0) {
      robust_relative_difference <- stats::median(
        abs(matched$gamma_classical - matched$gamma_robust),
        na.rm = TRUE) / scale_gamma
    }
  }
}

if (isTRUE(VARIOGRAM_EXPORT_CLOUD)) {
  variogram_cloud <- suppressWarnings(try(variogram(
    residual ~ 1, pts_sp, cutoff = VARIOGRAM_CUTOFF, cloud = TRUE
  ), silent = TRUE))
  if (!inherits(variogram_cloud, "try-error") && nrow(variogram_cloud) > 0) {
    write.csv(
      variogram_cloud,
      out_path("03_variogram",
        paste0("variogram_cloud_", TARGET_NAME, ".csv")),
      row.names = FALSE, fileEncoding = "UTF-8"
    )
  }
}

directional_vgm <- suppressWarnings(try(variogram(
  residual ~ 1, pts_sp, cutoff = VARIOGRAM_CUTOFF,
  width = VARIOGRAM_WIDTH, alpha = VARIOGRAM_DIRECTIONAL_ALPHAS,
  tol.hor = VARIOGRAM_DIRECTIONAL_TOLERANCE
), silent = TRUE))
directional_ranges <- data.frame()
anisotropy_ratio <- NA_real_
anisotropy_major_direction <- NA_real_
if (!inherits(directional_vgm, "try-error") && nrow(directional_vgm) > 0) {
  write.csv(
    directional_vgm,
    out_path("03_variogram",
      paste0("directional_variogram_", TARGET_NAME, ".csv")),
    row.names = FALSE, fileEncoding = "UTF-8"
  )
  directional_rows <- lapply(VARIOGRAM_DIRECTIONAL_ALPHAS, function(alpha) {
    z <- directional_vgm[
      abs(directional_vgm$dir.hor - alpha) < 1e-8, , drop = FALSE]
    if (nrow(z) < 3) {
      return(data.frame(
        direction = alpha, n_lags = nrow(z), model = NA_character_,
        range = NA_real_, practical_range = NA_real_,
        singular = NA, status = "insufficient_lags"))
    }
    fit <- fit_variogram_auto_select(
      z, model_df$residual,
      candidate_models = VARIOGRAM_CANDIDATE_MODELS)
    if (is.null(fit$fitted)) {
      return(data.frame(
        direction = alpha, n_lags = nrow(z), model = NA_character_,
        range = NA_real_, practical_range = NA_real_,
        singular = NA, status = "no_valid_fit"))
    }
    params <- get_vgm_params(fit$fitted)
    data.frame(
      direction = alpha, n_lags = nrow(z), model = params$model,
      range = params$range,
      practical_range = variogram_practical_range(params$model, params$range),
      singular = isTRUE(attr(fit$fitted, "singular")), status = "ok")
  })
  directional_ranges <- do.call(rbind, directional_rows)
  write.csv(
    directional_ranges,
    out_path("03_variogram",
      paste0("directional_range_diagnostics_", TARGET_NAME, ".csv")),
    row.names = FALSE, fileEncoding = "UTF-8"
  )
  valid_direction <- is.finite(directional_ranges$practical_range) &
    directional_ranges$practical_range > 0 & !directional_ranges$singular
  if (sum(valid_direction) >= 2) {
    ranges <- directional_ranges$practical_range[valid_direction]
    anisotropy_ratio <- max(ranges) / min(ranges)
    anisotropy_major_direction <- directional_ranges$direction[
      valid_direction][which.max(ranges)]
    if (anisotropy_ratio >= ANISOTROPY_RATIO_WARNING) {
      add_science_warning(paste0(
        "Directional variogram cho range ratio = ",
        round(anisotropy_ratio, 2), " (hướng liên tục lớn nhất ",
        anisotropy_major_direction,
        "°). Cần xem anisotropy trước khi dùng mô hình đẳng hướng."
      ))
    }
  }

  plot_file <- out_path("03_variogram",
    paste0("directional_variogram_", TARGET_NAME, ".png"))
  png(plot_file, width = 1200, height = 900)
  colors <- c("#1f77b4", "#d62728", "#2ca02c", "#9467bd")
  plot(NA, xlim = range(directional_vgm$dist, na.rm = TRUE),
    ylim = range(directional_vgm$gamma, na.rm = TRUE),
    xlab = "Distance (m)", ylab = "Semivariance",
    main = paste("Directional residual variograms -", TARGET_FIELD))
  for (i in seq_along(VARIOGRAM_DIRECTIONAL_ALPHAS)) {
    alpha <- VARIOGRAM_DIRECTIONAL_ALPHAS[i]
    z <- directional_vgm[
      abs(directional_vgm$dir.hor - alpha) < 1e-8, , drop = FALSE]
    points(z$dist, z$gamma, type = "b", pch = 19, col = colors[i])
  }
  legend("bottomright",
    legend = paste0(VARIOGRAM_DIRECTIONAL_ALPHAS, "°"),
    col = colors, pch = 19, lty = 1, bty = "n")
  save_plot_done(plot_file)
}

if (nrow(experimental_vgm) < MIN_VARIOGRAM_BINS_WARNING) {
  add_science_warning(paste0(
    "Experimental variogram has only ", nrow(experimental_vgm), " bins; fitted range/sill may be unstable."
  ))
}

low_pair_bins <- sum(experimental_vgm$np < MIN_PAIRS_PER_VARIOGRAM_BIN, na.rm = TRUE)
if (low_pair_bins > 0) {
  add_science_warning(paste0(
    low_pair_bins, " bin variogram có ít hơn ", MIN_PAIRS_PER_VARIOGRAM_BIN,
    " cặp điểm; cấu trúc ở các lag đầu có thể nhiễu."
  ))
}

manual_vgm <- vgm(
  psill = MANUAL_PSILL,
  model = VARIOGRAM_MODEL,
  range = MANUAL_RANGE,
  nugget = MANUAL_NUGGET
)

candidate_table <- data.frame()
suggested_vgm <- NULL
variogram_auto_fallback <- NULL

if (isTRUE(EXPORT_VARIogram_SUGGESTIONS) || VARIOGRAM_MODE == "auto_select") {
  log_msg("Creating constrained variogram suggestions...")

  auto_result <- fit_variogram_auto_select(
    experimental_vgm = experimental_vgm,
    residual_values = model_df$residual
  )

  suggested_vgm <- auto_result$fitted
  candidate_table <- auto_result$table
  variogram_auto_fallback <- auto_result$fallback %||% NULL

  if (nrow(candidate_table) > 0) {
    write.csv(
      candidate_table,
      out_path("03_variogram", paste0("variogram_candidate_results_", TARGET_NAME, ".csv")),
      row.names = FALSE
    )
    log_msg("Đã lưu bảng candidate variogram.")
  } else {
    log_msg("Không tìm được candidate variogram hợp lệ trong các ràng buộc range đã cấu hình.")
    add_science_warning("Fitting variogram tự động có ràng buộc không tìm được candidate hợp lệ; cần chuyên gia xem lại thông số variogram thủ công.")
  }
}

if (VARIOGRAM_MODE == "manual") {
  log_msg("Chế độ variogram: manual")
  log_msg("Dùng thông số variogram thủ công cho kriging.")
  fitted_vgm <- manual_vgm
} else if (VARIOGRAM_MODE == "auto_select") {
  log_msg("Variogram mode: auto_select")
  if (is.null(suggested_vgm)) {
    log_msg("auto_select không trả về mô hình; dùng pure-nugget an toàn.")
    fitted_vgm <- make_pure_nugget_variogram(
      model_df$residual, "auto_select_returned_null")
    variogram_auto_fallback <- "pure_nugget"
  } else {
    fitted_vgm <- suggested_vgm
    if (identical(variogram_auto_fallback, "pure_nugget")) {
      log_msg(paste0(
        "Không có candidate variogram có cấu trúc hợp lệ; ",
        "dùng pure nugget và không krige phần dư."
      ))
    } else {
      log_msg("Dùng variogram tự động có ràng buộc tốt nhất cho kriging.")
    }
  }
} else if (VARIOGRAM_MODE == "auto") {
  log_msg("Variogram mode: auto")
  fitted_vgm_try <- suppressWarnings(
    try(fit.variogram(experimental_vgm, model = manual_vgm), silent = TRUE)
  )

  if (inherits(fitted_vgm_try, "try-error")) {
    log_msg("Fit variogram tự động lỗi; dùng pure-nugget an toàn.")
    fitted_vgm <- make_pure_nugget_variogram(
      model_df$residual, "auto_fit_failed")
    variogram_auto_fallback <- "pure_nugget"
  } else {
    fitted_vgm <- fitted_vgm_try
    if (isTRUE(attr(fitted_vgm, "singular"))) {
      log_msg("Auto fit singular; dùng pure-nugget an toàn.")
      fitted_vgm <- make_pure_nugget_variogram(
        model_df$residual, "auto_fit_singular")
      variogram_auto_fallback <- "pure_nugget"
    } else if (any(fitted_vgm$psill < 0, na.rm = TRUE) ||
        any(fitted_vgm$range < 0, na.rm = TRUE)) {
      log_msg("Auto fit tạo thông số âm; dùng pure-nugget an toàn.")
      fitted_vgm <- make_pure_nugget_variogram(
        model_df$residual, "auto_fit_negative_parameters")
      variogram_auto_fallback <- "pure_nugget"
    }
  }
} else {
  stop("VARIOGRAM_MODE must be 'manual', 'auto_select', or 'auto'.")
}

fitted_vgm_params <- get_vgm_params(fitted_vgm)
fitted_vgm_singular <- isTRUE(attr(fitted_vgm, "singular"))
fitted_vgm_pure_nugget <- is_pure_nugget_variogram(fitted_vgm)
if (fitted_vgm_pure_nugget) {
  add_science_message(paste0(
    "Không tìm thấy cấu trúc không gian phần dư đáng tin cậy; ",
    "variogram cuối là pure nugget."
  ))
}
if (fitted_vgm_singular) {
  add_science_hard_failure(
    "Final variogram fit is singular; output map must not be auto-accepted.")
}
if (is.finite(robust_relative_difference) &&
    robust_relative_difference > 0.30) {
  add_science_warning(paste0(
    "Classical và Cressie variogram khác nhau ",
    round(100 * robust_relative_difference, 1),
    "% theo median relative difference; cần kiểm tra outlier/support."
  ))
}
if (is.finite(anisotropy_ratio) &&
    anisotropy_ratio >= ANISOTROPY_RATIO_MANUAL_REVIEW) {
  add_science_hard_failure(
    "Anisotropy mạnh nhưng final variogram vẫn đẳng hướng; cần manual review.")
}

fitted_practical_range <- practical_range(fitted_vgm)
fitted_total_sill <- fitted_vgm_params$nugget + fitted_vgm_params$psill
nugget_sill_ratio <- ifelse(fitted_total_sill > 0, fitted_vgm_params$nugget / fitted_total_sill, NA_real_)

log_msg("Final practical range: ", round(fitted_practical_range, 2), " m")
log_msg("Final nugget/sill ratio: ", round(nugget_sill_ratio, 4))

if (!is.na(fitted_practical_range) && fitted_practical_range > VARIOGRAM_CUTOFF * MAX_PRACTICAL_RANGE_FACTOR_OF_CUTOFF) {
  add_science_warning(paste0(
    "Practical range của variogram (", round(fitted_practical_range, 1), " m) gần hoặc vượt cutoff; cấu trúc khoảng cách xa có thể bị ràng buộc kém."
  ))
}

if (!is.na(nugget_sill_ratio) &&
    nugget_sill_ratio > MAX_NUGGET_SILL_RATIO_WARNING) {
  log_msg(
    "Variogram diagnostic: nugget/sill = ",
    round(nugget_sill_ratio, 3),
    "; residual spatial continuity is weak."
  )
}

capture.output(
  fitted_vgm,
  file = out_path("03_variogram", paste0("fitted_variogram_", TARGET_NAME, ".txt"))
)

capture.output(fitted_vgm, file = log_file, append = TRUE)

plot_file <- out_path("03_variogram", paste0("variogram_", TARGET_NAME, ".png"))
png(plot_file, width = 1200, height = 900)
plot(
  experimental_vgm,
  fitted_vgm,
  main = paste("Residual variogram -", TARGET_FIELD)
)
save_plot_done(plot_file)
variogram_plot_file <- plot_file

html_file <- out_path("03_variogram", paste0("variogram_interactive_", TARGET_NAME, ".html"))
write_variogram_html(experimental_vgm, fitted_vgm, html_file)
log_msg("Saved interactive variogram HTML: ", html_file)
report_interactive_variogram_file <- out_path("06_report", "interactive", basename(html_file))
report_variogram_plot_file <- out_path("06_report", "figures", basename(variogram_plot_file))
invisible(file.copy(html_file, report_interactive_variogram_file, overwrite = TRUE))
invisible(file.copy(variogram_plot_file, report_variogram_plot_file, overwrite = TRUE))
log_msg("Interactive variogram copied to report: ", report_interactive_variogram_file)

neighbor_tuning <- list(selected_nmax = NMAX_NEIGHBORS, selected_radius = SEARCH_RADIUS, table = data.frame(), method = "disabled")
if (exists("AUTO_NEIGHBORS") && isTRUE(AUTO_NEIGHBORS)) {
  log_msg("\n[7b] Auto-select kriging neighbors by spatial CV...")
  neighbor_tuning <- auto_select_neighbors(
    model_df = model_df,
    points_sf = pts_model_sf,
    regression_formula = regression_formula,
    target_field = TARGET_FIELD,
    manual_vgm = fitted_vgm,
    target_model_field = MODEL_TARGET_FIELD,
    target_transform = TARGET_TRANSFORM_ACTIVE,
    log_bias_correction = FALSE
  )

  if (!is.null(neighbor_tuning$table) && nrow(neighbor_tuning$table) > 0) {
    write.csv(
      neighbor_tuning$table,
      out_path("06_report", "tables", paste0("neighbor_tuning_", TARGET_NAME, ".csv")),
      row.names = FALSE
    )
  }

  NMAX_NEIGHBORS <- neighbor_tuning$selected_nmax
  SEARCH_RADIUS <- neighbor_tuning$selected_radius
  log_msg("Auto-neighbor method: ", neighbor_tuning$method)
  log_msg("Selected kriging nmax: ", NMAX_NEIGHBORS)
  log_msg("Selected search radius: ", SEARCH_RADIUS)

  if (grepl("fallback", neighbor_tuning$method)) {
    add_science_warning("Tự chọn neighbors không tìm được candidate hợp lệ; pipeline dùng lại NMAX_NEIGHBORS và SEARCH_RADIUS mặc định.")
  }
}

cv_summary <- data.frame()
cv_predictions <- data.frame()
cv_folds <- data.frame()
cv_rmse_plot_file <- NA_character_
nested_cv_result <- NULL
cv_validation_metadata <- list(
  method = "none", strict_outer_cv = FALSE, outer_repeats = 0L,
  tuning_uses_outer_test = NA,
  validation_design = "no_strict_outer_held_out_evaluation",
  validation_task = "internal_model_performance_estimation",
  independent_field_validation = FALSE,
  sample_role = "model_development"
)

bind_rows_fill <- function(items) {
  items <- Filter(function(x) is.data.frame(x) && nrow(x) > 0, items)
  if (length(items) == 0) return(data.frame())
  all_names <- unique(unlist(lapply(items, names), use.names = FALSE))
  items <- lapply(items, function(x) {
    missing <- setdiff(all_names, names(x))
    for (nm in missing) x[[nm]] <- NA
    x[, all_names, drop = FALSE]
  })
  do.call(rbind, items)
}

if (isTRUE(RUN_CROSS_VALIDATION)) {
  log_msg("\n[8] Cross-validation and model comparison...")

  if (identical(tolower(CV_EVALUATION_MODE %||% "nested_spatial"), "nested_spatial")) {
    log_msg("Running leakage-resistant nested spatial CV: ",
      CV_OUTER_FOLDS, " outer folds x ", CV_OUTER_REPEATS, " repeats.")
    nested_try <- try(
      rk_nested_spatial_cv(
        model_df = model_df,
        points_sf = pts_model_sf,
        regression_formula = regression_formula,
        target_field = TARGET_FIELD,
        target_model_field = MODEL_TARGET_FIELD,
        manual_vgm = fitted_vgm,
        prediction_raster = template_raster
      ),
      silent = TRUE
    )
    if (inherits(nested_try, "try-error")) {
      add_science_warning(paste0(
        "Nested spatial CV failed; no outer held-out performance estimate is available: ",
        as.character(nested_try)
      ))
    } else {
      nested_cv_result <- nested_try
      cv_summary <- nested_try$summary
      cv_predictions <- nested_try$predictions
      cv_folds <- nested_try$folds
      cv_validation_metadata <- utils::modifyList(nested_try$metadata, list(
        validation_design = "nested_spatial_cv_outer_held_out",
        validation_task = "internal_model_performance_estimation",
        independent_field_validation = FALSE,
        sample_role = "model_development"
      ))
      write.csv(
        nested_try$repeat_metrics,
        out_path("06_report", "tables",
          paste0("nested_cv_repeat_metrics_", TARGET_NAME, ".csv")),
        row.names = FALSE
      )
      write.csv(
        nested_try$stability |> as.data.frame(),
        out_path("06_report", "tables",
          paste0("nested_cv_stability_", TARGET_NAME, ".csv")),
        row.names = FALSE
      )
      write.csv(
        nested_try$tuning,
        out_path("06_report", "tables",
          paste0("nested_cv_inner_tuning_", TARGET_NAME, ".csv")),
        row.names = FALSE
      )
      if (isTRUE(EXPORT_RAW_CV_TABLES)) {
        write.csv(
          nested_try$raw_predictions,
          out_path("06_report", "tables",
            paste0("nested_cv_raw_predictions_", TARGET_NAME, ".csv")),
          row.names = FALSE
        )
      }
      if (is.finite(nested_try$stability$inner_tuning_fallback_fraction) &&
          nested_try$stability$inner_tuning_fallback_fraction > 0) {
        add_science_warning(paste0(
          "Inner tuning phải fallback trong ",
          round(100 * nested_try$stability$inner_tuning_fallback_fraction, 1),
          "% outer folds; cần xem bảng nested_cv_inner_tuning."
        ))
        if (nested_try$stability$inner_tuning_fallback_fraction >= 0.50) {
          add_science_hard_failure(
            "Ít nhất một nửa outer folds không tìm được inner candidate ổn định.")
        }
      }
      if (is.finite(nested_try$stability$rk_better_than_regression_fraction) &&
          nested_try$stability$rk_better_than_regression_fraction < 0.80) {
        log_msg(
          "Nested CV diagnostic: RK better than regression-only in ",
          round(100 * nested_try$stability$rk_better_than_regression_fraction, 1),
          "% of outer repeats."
        )
      }
      log_msg("Nested spatial CV completed. Median repeat RMSE: ",
        round(nested_try$stability$median_rmse, 4),
        "; IQR: ", round(nested_try$stability$iqr_rmse, 4))
    }
  }

  secondary_results <- list()
  for (cv_method in CV_METHODS) {
    log_msg("Running secondary diagnostic CV method: ", cv_method)
    cv_try <- try(
      run_cv_comparison(
        model_df = model_df, points_sf = pts_model_sf,
        regression_formula = regression_formula, target_field = TARGET_FIELD,
        cv_method = cv_method, manual_vgm = fitted_vgm,
        target_model_field = MODEL_TARGET_FIELD,
        target_transform = TARGET_TRANSFORM_ACTIVE,
        log_bias_correction = FALSE
      ),
      silent = TRUE
    )
    if (inherits(cv_try, "try-error")) {
      add_science_warning(paste0(
        "Cross-validation chẩn đoán lỗi với phương pháp ", cv_method, "."))
      next
    }
    cv_try$summary$evaluation_role <- "secondary_diagnostic"
    secondary_results[[cv_method]] <- cv_try
  }

  if (length(secondary_results) > 0) {
    secondary_summary <- bind_rows_fill(lapply(secondary_results, function(x) x$summary))
    secondary_predictions <- bind_rows_fill(lapply(secondary_results, function(x) x$predictions))
    secondary_folds <- bind_rows_fill(lapply(secondary_results, function(x) x$folds))
    cv_summary <- bind_rows_fill(list(cv_summary, secondary_summary))
    cv_predictions <- bind_rows_fill(list(cv_predictions, secondary_predictions))
    cv_folds <- bind_rows_fill(list(cv_folds, secondary_folds))
  }

  if (nrow(cv_summary) > 0) {
    if (isTRUE(EXPORT_RAW_CV_TABLES)) {
      write.csv(
        cv_summary,
        out_path("06_report", "tables",
          paste0("cv_model_comparison_raw_", TARGET_NAME, ".csv")),
        row.names = FALSE
      )
      write.csv(
        cv_predictions,
        out_path("06_report", "tables",
          paste0("cv_predictions_raw_", TARGET_NAME, ".csv")),
        row.names = FALSE
      )
    }
    write.csv(
      cv_folds,
      out_path("06_report", "tables",
        paste0("cv_fold_diagnostics_", TARGET_NAME, ".csv")),
      row.names = FALSE
    )
    cv_plot_rows <- cv_summary[
      !is.na(cv_summary$RMSE) &
        (is.na(cv_summary$evaluation_role) |
          cv_summary$evaluation_role == "primary_outer"), , drop = FALSE]
    if (nrow(cv_plot_rows) == 0) {
      cv_plot_rows <- cv_summary[!is.na(cv_summary$RMSE), , drop = FALSE]
    }
    if (nrow(cv_plot_rows) > 0) {
      plot_file <- out_path(
        "06_report", "figures", paste0("cv_rmse_comparison_", TARGET_NAME, ".png"))
      png(plot_file, width = 1400, height = 900)
      bar_cols <- ifelse(
        cv_plot_rows$model == "Regression Kriging", "#d62728",
        ifelse(cv_plot_rows$model == "Ordinary Kriging", "#1f77b4", "#2ca02c")
      )
      barplot(
        cv_plot_rows$RMSE,
        names.arg = paste(cv_plot_rows$cv_method, cv_plot_rows$model, sep = "\n"),
        las = 2, col = bar_cols, ylab = "RMSE on original units",
        main = paste("Primary outer spatial CV RMSE -", TARGET_FIELD)
      )
      save_plot_done(plot_file)
      cv_rmse_plot_file <- plot_file
    }
    if (any(cv_summary$n_missing > 0, na.rm = TRUE)) {
      add_science_warning(
        "Một số dự báo kriging trong CV bị thiếu vì không tìm được điểm lân cận trong SEARCH_RADIUS.")
    }
  } else {
    add_science_warning("Cross-validation không tạo được kết quả hợp lệ.")
  }
}

extrapolation_summary <- list(
  available = FALSE, method = "CAST_AOA", outside_aoa_percent = NA_real_,
  model_dependent = TRUE,
  dependency_scope =
    "predictor_set_preprocessing_model_development_points_and_cv_folds",
  roi_membership_test = FALSE,
  outside_roi_points_are_validation = FALSE,
  message = "AOA diagnostics not run; AOA is not an ROI-membership test."
)
if (isTRUE(RUN_AOA_DIAGNOSTICS)) {
  if (!requireNamespace("CAST", quietly = TRUE)) {
    add_science_warning(
      "Không có package CAST; Area of Applicability chưa được đánh giá.")
  } else {
    log_msg("\n[8b] Area of Applicability diagnostics...")
    aoa_try <- try({
      aoa_plan <- rk_make_cv_plan(
        pts_model_sf, CV_OUTER_METHOD, CV_OUTER_FOLDS,
        CV_RANDOM_SEED + 9001L, block_size = CV_OUTER_BLOCK_SIZE,
        prediction_raster = template_raster
      )
      train_di <- CAST::trainDI(
        train = model_df[, PREDICTORS, drop = FALSE],
        variables = PREDICTORS, useWeight = FALSE, useCV = TRUE,
        CVtest = lapply(aoa_plan$folds, function(z) z$test),
        CVtrain = lapply(aoa_plan$folds, function(z) z$train),
        verbose = FALSE
      )
      CAST::aoa(covs_utm, trainDI = train_di)
    }, silent = TRUE)

    if (inherits(aoa_try, "try-error")) {
      add_science_warning(paste0(
        "Không tính được Area of Applicability: ", as.character(aoa_try)))
      extrapolation_summary$message <- as.character(aoa_try)
    } else {
      aoa_mask <- mask(aoa_try$AOA, complete_pc_mask)
      aoa_di <- mask(aoa_try$DI, complete_pc_mask)
      names(aoa_mask) <- paste0("AOA_", TARGET_NAME)
      names(aoa_di) <- paste0("DI_", TARGET_NAME)
      writeRaster(
        aoa_mask,
        out_path("05_final_rk",
          paste0("area_of_applicability_", TARGET_NAME, "_utm.tif")),
        overwrite = TRUE
      )
      writeRaster(
        aoa_di,
        out_path("05_final_rk",
          paste0("dissimilarity_index_", TARGET_NAME, "_utm.tif")),
        overwrite = TRUE
      )
      outside_aoa_percent <- tryCatch(
        100 * as.numeric(global(aoa_mask == 0, "mean", na.rm = TRUE)[1, 1]),
        error = function(e) NA_real_
      )
      extrapolation_summary <- list(
        available = TRUE, method = "CAST_AOA",
        threshold = aoa_try$parameters$threshold %||% NA_real_,
        outside_aoa_percent = outside_aoa_percent,
        weighted_predictors = FALSE,
        cv_based_threshold = TRUE,
        raster_aoa = paste0(
          "05_final_rk/area_of_applicability_", TARGET_NAME, "_utm.tif"),
        raster_dissimilarity = paste0(
          "05_final_rk/dissimilarity_index_", TARGET_NAME, "_utm.tif"),
        model_dependent = TRUE,
        dependency_scope = paste0(
          "predictors=", paste(PREDICTORS, collapse = "|"),
          "; preprocessing=current_run; reference=all_model_development_points"
        ),
        roi_membership_test = FALSE,
        outside_roi_points_are_validation = FALSE,
        message = "AOA dựa trên covariate space và outer held-out folds nội bộ; không phải kiểm tra ROI hay field validation."
      )
      if (is.finite(outside_aoa_percent) &&
          outside_aoa_percent > AOA_MAX_OUTSIDE_PERCENT_WARNING) {
        add_science_warning(paste0(
          round(outside_aoa_percent, 1),
          "% vùng dự báo nằm ngoài Area of Applicability."))
      }
      if (is.finite(outside_aoa_percent) &&
          outside_aoa_percent > AOA_MAX_OUTSIDE_PERCENT_HARD_FAIL) {
        add_science_hard_failure(
          "Diện tích ngoài AOA quá lớn; bản đồ không được auto-ACCEPT.")
      }
    }
  }
}

log_msg("
[9] Kriging residual...")

template <- complete_pc_mask
residual_spatial_structure_available <-
  !isTRUE(fitted_vgm_pure_nugget) &&
  is.finite(nugget_sill_ratio) &&
  nugget_sill_ratio < PURE_NUGGET_RATIO_THRESHOLD &&
  is.finite(fitted_vgm_params$psill) &&
  fitted_vgm_params$psill > 0
final_prediction_method <- "regression_kriging"

if (!residual_spatial_structure_available &&
    identical(PURE_NUGGET_POLICY, "regression_only")) {
  add_science_message(
    "Final map đã chuyển sang regression-only vì residual variogram là pure nugget.")
  final_prediction_method <- "regression_only_pure_nugget_fallback"
  residual_raster <- ifel(!is.na(template), 0, NA)
  residual_var_raster <- template * NA_real_
} else {
  grid_df <- as.data.frame(
    template, xy = TRUE, cells = TRUE, na.rm = TRUE)
  grid_cells <- grid_df$cell
  grid_df <- grid_df[, c("cell", "x", "y")]
  coordinates(grid_df) <- ~x + y
  proj4string(grid_df) <- CRS(SRS_string = terra::crs(template))
  res_krig <- krige(
    formula = residual ~ 1, locations = pts_sp, newdata = grid_df,
    model = fitted_vgm, nmax = NMAX_NEIGHBORS,
    maxdist = SEARCH_RADIUS, debug.level = 0
  )
  residual_raster <- template
  residual_var_raster <- template
  values(residual_raster) <- NA_real_
  values(residual_var_raster) <- NA_real_
  residual_raster[grid_cells] <- res_krig$var1.pred
  residual_var_raster[grid_cells] <- res_krig$var1.var
  residual_raster <- mask(residual_raster, complete_pc_mask)
  residual_var_raster <- mask(residual_var_raster, complete_pc_mask)
}
LOG_BACKTRANSFORM_BIAS_CORRECTION_APPLIED <-
  isTRUE(LOG_BACKTRANSFORM_BIAS_CORRECTION_ACTIVE) &&
  isTRUE(residual_spatial_structure_available)
if (isTRUE(LOG_BACKTRANSFORM_BIAS_CORRECTION_ACTIVE) &&
    !isTRUE(LOG_BACKTRANSFORM_BIAS_CORRECTION_APPLIED)) {
  add_science_message(paste0(
    "Đã tắt bias correction cho output production vì residual variogram ",
    "là pure nugget và không có residual kriging variance hợp lệ."
  ))
}
names(residual_raster) <- "kriged_residual"
names(residual_var_raster) <- "residual_kriging_variance"
writeRaster(
  residual_raster,
  out_path("04_kriging_residual",
    paste0("residual_kriging_", TARGET_NAME, "_utm.tif")),
  overwrite = TRUE
)
writeRaster(
  residual_var_raster,
  out_path("04_kriging_residual",
    paste0("residual_variance_", TARGET_NAME, "_utm.tif")),
  overwrite = TRUE
)

log_msg("\n[10] Predict regression on PC raster...")

regression_prediction_model <- terra::predict(
  covs_utm,
  reg_model,
  na.rm = TRUE
)

regression_prediction_model <- mask(regression_prediction_model, complete_pc_mask)
regression_prediction <- rk_back_transform_raster(regression_prediction_model, TARGET_TRANSFORM_ACTIVE)
regression_prediction <- mask(regression_prediction, complete_pc_mask)

names(regression_prediction) <- paste0("regression_prediction_", TARGET_NAME)
names(regression_prediction_model) <- paste0("regression_prediction_model_scale_", TARGET_NAME)

if (!identical(TARGET_TRANSFORM_ACTIVE, "none")) {
  writeRaster(
    regression_prediction_model,
    out_path("05_final_rk", paste0("regression_prediction_model_scale_", TARGET_NAME, "_utm.tif")),
    overwrite = TRUE
  )
}

writeRaster(
  regression_prediction,
  out_path("05_final_rk", paste0("regression_prediction_", TARGET_NAME, "_utm.tif")),
  overwrite = TRUE
)

log_msg("\n[11] Create final Regression Kriging raster...")

rk_final_model <- regression_prediction_model + residual_raster
residual_var_raster <- clamp(
  residual_var_raster,
  lower = 0,
  values = TRUE
)
rk_final_unclamped <- rk_back_transform_raster(
  rk_final_model, TARGET_TRANSFORM_ACTIVE,
  variance_raster = residual_var_raster,
  bias_correction = LOG_BACKTRANSFORM_BIAS_CORRECTION_APPLIED
)
rk_final_unclamped <- mask(rk_final_unclamped, complete_pc_mask)
names(rk_final_unclamped) <- paste0("RK_unclamped_", TARGET_NAME)

rk_clipping_mask <- ifel(
  rk_final_unclamped < sample_min, -1,
  ifel(rk_final_unclamped > sample_max, 1, 0)
)
rk_clipping_mask <- mask(rk_clipping_mask, complete_pc_mask)
names(rk_clipping_mask) <- paste0("RK_clipping_mask_", TARGET_NAME)
clipped_low_percent <- tryCatch(
  100 * as.numeric(global(rk_clipping_mask == -1, "mean", na.rm = TRUE)[1, 1]),
  error = function(e) NA_real_
)
clipped_high_percent <- tryCatch(
  100 * as.numeric(global(rk_clipping_mask == 1, "mean", na.rm = TRUE)[1, 1]),
  error = function(e) NA_real_
)
total_clipped_percent <- clipped_low_percent + clipped_high_percent
if (is.finite(total_clipped_percent) &&
    total_clipped_percent > MAX_CLIPPED_AREA_PERCENT_WARNING) {
  add_science_warning(paste0(
    round(total_clipped_percent, 2),
    "% cell nằm ngoài min-max mẫu trước clamp; cần xem extrapolation/clipping mask."
  ))
}
if (is.finite(total_clipped_percent) &&
    total_clipped_percent > MAX_CLIPPED_AREA_PERCENT_HARD_FAIL) {
  add_science_hard_failure(
    "Tỷ lệ clipping quá lớn; bản đồ không được auto-ACCEPT.")
}

rk_final <- if (isTRUE(CLAMP_TO_SAMPLE_RANGE)) {
  clamp(rk_final_unclamped, lower = sample_min, upper = sample_max, values = TRUE)
} else {
  rk_final_unclamped
}
rk_final <- mask(rk_final, complete_pc_mask)
names(rk_final) <- paste0("RK_", TARGET_NAME)
if (isTRUE(CLAMP_TO_SAMPLE_RANGE)) {
  log_msg("Clamped final raster to sample min/max; audit rasters retain unclamped values.")
}

uncertainty_available <- isTRUE(residual_spatial_structure_available)
if (uncertainty_available) {
  rk_variance_original <- rk_back_transform_variance_raster(
    residual_var_raster,
    rk_final_model,
    TARGET_TRANSFORM_ACTIVE,
    bias_correction = LOG_BACKTRANSFORM_BIAS_CORRECTION_APPLIED
  )
  rk_variance_original <- clamp(
    rk_variance_original, lower = 0, values = TRUE)
  rk_std <- sqrt(rk_variance_original)
  rk_std <- mask(rk_std, complete_pc_mask)
  add_science_message(paste0(
    "Residual kriging SD (file tương thích RK_uncertainty_STD) chỉ mô tả phần dư; ",
    "không phải total predictive uncertainty hay prediction interval."
  ))
} else {
  rk_variance_original <- template * NA_real_
  rk_std <- template * NA_real_
  add_science_message(paste0(
    "Không xuất residual kriging STD vì variogram phần dư là pure nugget; ",
    "không có uncertainty raster RK hợp lệ."
  ))
}
names(rk_std) <- paste0("residual_kriging_SD_", TARGET_NAME)

writeRaster(
  rk_final,
  out_path("05_final_rk", paste0("RK_final_", TARGET_NAME, "_utm.tif")),
  overwrite = TRUE
)

writeRaster(
  rk_final_unclamped,
  out_path("05_final_rk", paste0("RK_final_unclamped_", TARGET_NAME, "_utm.tif")),
  overwrite = TRUE
)
writeRaster(
  rk_clipping_mask,
  out_path("05_final_rk", paste0("RK_clipping_mask_", TARGET_NAME, "_utm.tif")),
  overwrite = TRUE
)

uncertainty_utm_file <- out_path(
  "05_final_rk", paste0("RK_uncertainty_STD_", TARGET_NAME, "_utm.tif"))
if (uncertainty_available) {
  writeRaster(rk_std, uncertainty_utm_file, overwrite = TRUE)
}

if (!is.na(EXPORT_EPSG)) {
  export_crs <- paste0("EPSG:", EXPORT_EPSG)
  safe_project_write <- function(r, file, label, method = "bilinear") {
    ok <- tryCatch({
      terra::project(
        r,
        export_crs,
        method = method,
        filename = file,
        overwrite = TRUE
      )
      TRUE
    }, error = function(e) {
      add_science_warning(paste0(
        "Không export được ", label, " sang EPSG:", EXPORT_EPSG,
        " do lỗi bộ nhớ hoặc reprojection: ", conditionMessage(e),
        ". File UTM vẫn đã được xuất và nên dùng làm output chính."
      ))
      log_msg("[WARN] Failed to export ", label, " to EPSG:", EXPORT_EPSG, ": ", conditionMessage(e))
      FALSE
    })
    ok
  }

  safe_project_write(
    rk_final,
    out_path("05_final_rk", paste0("RK_final_", TARGET_NAME, "_epsg", EXPORT_EPSG, ".tif")),
    "RK final raster"
  )

  if (uncertainty_available) {
    safe_project_write(
      rk_std,
      out_path("05_final_rk", paste0(
        "RK_uncertainty_STD_", TARGET_NAME,
        "_epsg", EXPORT_EPSG, ".tif"
      )),
      "Residual kriging SD raster (legacy-compatible filename)"
    )
  }
  safe_project_write(
    rk_final_unclamped,
    out_path("05_final_rk", paste0(
      "RK_final_unclamped_", TARGET_NAME, "_epsg", EXPORT_EPSG, ".tif")),
    "RK unclamped raster"
  )
  safe_project_write(
    rk_clipping_mask,
    out_path("05_final_rk", paste0(
      "RK_clipping_mask_", TARGET_NAME, "_epsg", EXPORT_EPSG, ".tif")),
    "RK clipping mask", method = "near"
  )
}

rk_min <- global(rk_final, "min", na.rm = TRUE)[1, 1]
rk_max <- global(rk_final, "max", na.rm = TRUE)[1, 1]
rk_mean <- global(rk_final, "mean", na.rm = TRUE)[1, 1]

std_min <- std_max <- std_mean <- std_q80_display <- NA_real_
if (uncertainty_available) {
  std_min <- global(rk_std, "min", na.rm = TRUE)[1, 1]
  std_max <- global(rk_std, "max", na.rm = TRUE)[1, 1]
  std_mean <- global(rk_std, "mean", na.rm = TRUE)[1, 1]
  std_q80_display <- tryCatch(
    as.numeric(global(
      rk_std,
      function(x, ...) stats::quantile(x, 0.80, na.rm = TRUE),
      na.rm = TRUE
    )[1, 1]),
    error = function(e) NA_real_
  )
}
primary_rk_row <- data.frame()
if (exists("cv_summary") && nrow(cv_summary) > 0) {
  primary_rk_row <- cv_summary[
    cv_summary$model == "Regression Kriging" &
      cv_summary$cv_method == "nested_spatial_block", , drop = FALSE]
  if (nrow(primary_rk_row) == 0) {
    primary_rk_row <- cv_summary[
      cv_summary$model == "Regression Kriging", , drop = FALSE]
  }
}
outer_cv_rmse <- if (nrow(primary_rk_row) > 0)
  suppressWarnings(as.numeric(primary_rk_row$RMSE[1])) else NA_real_
profiles_for_uncertainty <- load_evaluation_profiles(EVALUATION_PROFILE_FILE)
profile_for_uncertainty <- match_indicator_profile(
  TARGET_FIELD, profiles_for_uncertainty)
profile_sd_threshold <- suppressWarnings(as.numeric(
  profile_for_uncertainty$uncertainty_sd_threshold %||% NA_real_))
uncertainty_threshold <- if (!uncertainty_available) {
  NA_real_
} else if (is.finite(profile_sd_threshold)) {
  profile_sd_threshold
} else {
  outer_cv_rmse
}
uncertainty_threshold_source <- if (!uncertainty_available) {
  "unavailable_pure_nugget"
} else if (is.finite(profile_sd_threshold)) {
  "profile_absolute_residual_sd_display_reference"
} else if (is.finite(outer_cv_rmse)) {
  "outer_heldout_rmse_display_reference"
} else {
  "not_defined"
}
std_high_pct <- tryCatch(
  if (is.finite(uncertainty_threshold)) {
    100 * as.numeric(global(
      rk_std >= uncertainty_threshold, "mean", na.rm = TRUE)[1, 1])
  } else NA_real_,
  error = function(e) NA_real_
)
observed_iqr <- stats::IQR(model_df[[TARGET_FIELD]], na.rm = TRUE)
normalized_mean_sd_iqr <- if (is.finite(observed_iqr) && observed_iqr > 0)
  std_mean / observed_iqr else NA_real_
var_min <- var_max <- var_mean <- NA_real_
if (uncertainty_available) {
  var_min <- global(rk_variance_original, "min", na.rm = TRUE)[1, 1]
  var_max <- global(rk_variance_original, "max", na.rm = TRUE)[1, 1]
  var_mean <- global(rk_variance_original, "mean", na.rm = TRUE)[1, 1]
}
uncertainty_summary <- list(
  available = uncertainty_available,
  uncertainty_type = if (uncertainty_available) {
    "residual_kriging_standard_deviation"
  } else {
    "not_available_pure_nugget"
  },
  product_semantics =
    "partial_residual_kriging_sd_not_total_predictive_uncertainty",
  legacy_filename_compatibility = "RK_uncertainty_STD_*.tif",
  total_predictive_uncertainty_available = FALSE,
  prediction_interval_claim_allowed = FALSE,
  prediction_interval_type = "not_available_from_residual_kriging_sd",
  coverage_95_semantics =
    "residual_variance_diagnostic_only_not_prediction_interval_validation",
  calibration_approved = FALSE,
  calibration_basis = if (uncertainty_available) {
    "residual_kriging_only"
  } else {
    "not_available"
  },
  calibrated = FALSE,
  used_in_grade = FALSE,
  min_sd = std_min, mean_sd = std_mean, max_sd = std_max,
  min_variance = var_min, mean_variance = var_mean, max_variance = var_max,
  display_q80 = std_q80_display,
  high_uncertainty_threshold = uncertainty_threshold,
  threshold_source = uncertainty_threshold_source,
  high_uncertainty_area_percent = std_high_pct,
  normalized_mean_sd_by_observed_iqr = normalized_mean_sd_iqr,
  n_interval = if (nrow(primary_rk_row) > 0 &&
      "n_interval" %in% names(primary_rk_row)) {
    primary_rk_row$n_interval[1]
  } else {
    NA_integer_
  },
  interval_fraction = if (nrow(primary_rk_row) > 0 &&
      "interval_fraction" %in% names(primary_rk_row)) {
    primary_rk_row$interval_fraction[1]
  } else {
    NA_real_
  },
  coverage_95 = if (nrow(primary_rk_row) > 0)
    primary_rk_row$coverage_95[1] else NA_real_,
  mean_standardized_error = if (nrow(primary_rk_row) > 0)
    primary_rk_row$mean_standardized_error[1] else NA_real_,
  variance_standardized_RMSE = if (nrow(primary_rk_row) > 0 &&
      "variance_standardized_RMSE" %in% names(primary_rk_row))
    primary_rk_row$variance_standardized_RMSE[1] else NA_real_,
  interval_score_95 = if (nrow(primary_rk_row) > 0 &&
      "interval_score_95" %in% names(primary_rk_row))
    primary_rk_row$interval_score_95[1] else NA_real_,
  messages = if (uncertainty_available) {
    "Residual kriging SD only; interval diagnostics are not calibrated total predictive intervals and are not scored."
  } else {
    "Residual uncertainty raster is unavailable because the final residual variogram is pure nugget."
  },
  warnings = character(0)
)

best_variogram_sse <- NA_real_
if (exists("candidate_table") && nrow(candidate_table) > 0) {
  selected_candidate <- if (fitted_vgm_pure_nugget) {
    candidate_table[
      candidate_table$status == "pure_nugget_fallback", , drop = FALSE]
  } else {
    candidate_table[
      candidate_table$accepted %in% TRUE, , drop = FALSE]
  }
  if (nrow(selected_candidate) > 0) {
    selected_candidate <- selected_candidate[
      order(selected_candidate$candidate_score,
        selected_candidate$sse_per_pair),
      , drop = FALSE
    ]
    best_variogram_sse <- suppressWarnings(
      as.numeric(selected_candidate$sse[1]))
  }
}

vgm_params <- get_vgm_params(fitted_vgm)

lookup_cv <- function(method, model, field) {
  if (!exists("cv_summary") || nrow(cv_summary) == 0) {
    return(NA_real_)
  }
  row <- cv_summary[cv_summary$cv_method == method & cv_summary$model == model, , drop = FALSE]
  if (nrow(row) == 0 || !(field %in% names(row))) {
    return(NA_real_)
  }
  return(row[[field]][1])
}

issue_table <- function(values, column) {
  out <- data.frame(id = seq_along(values), stringsAsFactors = FALSE)
  out[[column]] <- values
  out
}
write.csv(
  issue_table(scientific_messages, "message"),
  out_path("06_report", "tables",
    paste0("scientific_messages_", TARGET_NAME, ".csv")),
  row.names = FALSE, fileEncoding = "UTF-8"
)
write.csv(
  issue_table(scientific_warnings, "warning"),
  out_path("06_report", "tables",
    paste0("scientific_warnings_", TARGET_NAME, ".csv")),
  row.names = FALSE, fileEncoding = "UTF-8"
)
write.csv(
  issue_table(scientific_hard_failures, "hard_failure"),
  out_path("06_report", "tables",
    paste0("scientific_hard_failures_", TARGET_NAME, ".csv")),
  row.names = FALSE, fileEncoding = "UTF-8"
)
writeLines(
  c(
    "Thông báo, cảnh báo và điều kiện chặn ACCEPT",
    paste0("Target: ", TARGET_FIELD), "",
    "THÔNG BÁO:",
    if (length(scientific_messages)) scientific_messages else "(trống)",
    "", "CẢNH BÁO:",
    if (length(scientific_warnings)) scientific_warnings else "(trống)",
    "", "HARD FAILURES:",
    if (length(scientific_hard_failures)) scientific_hard_failures else "(trống)",
    "",
    "RK_uncertainty_STD là residual kriging SD; không phải total predictive uncertainty hoặc prediction interval."
  ),
  out_path("06_report", paste0("warnings_", TARGET_NAME, ".txt")),
  useBytes = TRUE
)

report <- data.frame(
  run_name = RUN_NAME,
  output_folder = OUT_DIR,
  roi_handling =
    "model support uses complete covariates; final project deliverables mask to ROI",
  target = TARGET_FIELD,
  target_metadata_confirmed = isTRUE(target_metadata_active$confirmed),
  product_status_pre_evaluation = if (!isTRUE(target_metadata_active$confirmed)) {
    "DRAFT_UNCONFIRMED_METADATA"
  } else if (!outside_review_gate_passed) {
    "DRAFT_PENDING_OUTSIDE_REVIEW"
  } else "SCIENTIFIC_QA",
  final_prediction_method = final_prediction_method,
  target_transform_requested = target_transform_info$requested,
  target_transform_used = TARGET_TRANSFORM_ACTIVE,
  log_backtransform_bias_correction_requested =
    LOG_BACKTRANSFORM_BIAS_CORRECTION_ACTIVE,
  log_backtransform_bias_correction =
    LOG_BACKTRANSFORM_BIAS_CORRECTION_APPLIED,
  predictors = paste(PREDICTORS, collapse = ", "),
  n_predictors = length(PREDICTORS),
  n_points_raw_valid = nrow(pts_raw),
  n_points_inside_roi_model = n_inside_roi_model,
  n_points_outside_roi_model = n_outside_roi_model,
  n_outside_pending_review = length(outside_pending_idx),
  n_outside_include_false_in_primary = length(outside_include_false_idx),
  outside_roi_points_are_validation = FALSE,
  primary_product_eligible = outside_review_gate_passed,
  sensitivity_analysis_eligible = TRUE,
  n_points_used_model = nrow(model_df),
  sample_min = sample_min,
  sample_max = sample_max,
  regression_rmse = rmse,
  regression_mae = mae,
  regression_r2 = r2_pred,
  regression_adjusted_r2 = reg_adj_r2,
  random_cv_regression_rmse = lookup_cv("random", "Regression-only", "RMSE"),
  random_cv_ok_rmse = lookup_cv("random", "Ordinary Kriging", "RMSE"),
  random_cv_rk_rmse = lookup_cv("random", "Regression Kriging", "RMSE"),
  spatial_cv_regression_rmse = lookup_cv("spatial_kmeans", "Regression-only", "RMSE"),
  spatial_cv_ok_rmse = lookup_cv("spatial_kmeans", "Ordinary Kriging", "RMSE"),
  spatial_cv_rk_rmse = lookup_cv("spatial_kmeans", "Regression Kriging", "RMSE"),
  spatial_cv_rk_n_predicted = lookup_cv("spatial_kmeans", "Regression Kriging", "n_predicted"),
  nested_outer_rk_rmse = lookup_cv("nested_spatial_block", "Regression Kriging", "RMSE"),
  nested_outer_rk_r2 = lookup_cv("nested_spatial_block", "Regression Kriging", "R2"),
  nested_outer_repeats = cv_validation_metadata$outer_repeats %||% 0L,
  validation_design = cv_validation_metadata$validation_design,
  validation_task = cv_validation_metadata$validation_task,
  independent_field_validation = FALSE,
  cv_sample_role = "model_development",
  strict_outer_cv = isTRUE(cv_validation_metadata$strict_outer_cv),
  variogram_mode = VARIOGRAM_MODE,
  final_variogram_model = vgm_params$model,
  final_variogram_nugget = vgm_params$nugget,
  final_variogram_psill = vgm_params$psill,
  final_variogram_range = vgm_params$range,
  final_variogram_practical_range = fitted_practical_range,
  final_nugget_sill_ratio = nugget_sill_ratio,
  final_variogram_singular = fitted_vgm_singular,
  anisotropy_ratio = anisotropy_ratio,
  best_variogram_sse = best_variogram_sse,
  variogram_cutoff = VARIOGRAM_CUTOFF,
  variogram_width = VARIOGRAM_WIDTH,
  range_min = VARIOGRAM_RANGE_MIN,
  range_max = VARIOGRAM_RANGE_MAX,
  auto_neighbors_enabled = exists("AUTO_NEIGHBORS") && isTRUE(AUTO_NEIGHBORS),
  auto_neighbors_method = if (exists("neighbor_tuning")) neighbor_tuning$method else "not_run",
  nmax_neighbors = NMAX_NEIGHBORS,
  search_radius = SEARCH_RADIUS,
  output_res_x = template_res[1],
  output_res_y = template_res[2],
  valid_pc_cells = valid_pc_cells,
  median_sample_spacing_m = nn_table$median_m[1],
  max_sample_spacing_m = nn_table$max_m[1],
  n_scientific_messages = length(scientific_messages),
  n_scientific_warnings = length(scientific_warnings),
  n_scientific_hard_failures = length(scientific_hard_failures),
  clipped_area_percent = total_clipped_percent,
  outside_aoa_percent = extrapolation_summary$outside_aoa_percent %||% NA_real_,
  rk_min = rk_min,
  rk_max = rk_max,
  rk_mean = rk_mean,
  std_min = std_min,
  std_max = std_max,
  std_mean = std_mean,
  uncertainty_product_type = "residual_kriging_standard_deviation",
  total_predictive_uncertainty_available = FALSE,
  prediction_interval_claim_allowed = FALSE,
  uncertainty_legacy_filename = "RK_uncertainty_STD_*.tif"
)

write.csv(
  report,
  out_path("06_report", "tables", paste0("rk_report_", TARGET_NAME, ".csv")),
  row.names = FALSE
)

log_msg("\n[12] Export RK quality evaluation report...")

quality_cv <- data.frame()
preferred_method <- NA_character_
if (exists("cv_predictions") && nrow(cv_predictions) > 0) {
  preference <- c(
    "nested_spatial_block", "spatial_block", "buffer", "nndm",
    "spatial_kmeans", "random"
  )
  available_methods <- unique(as.character(cv_predictions$cv_method))
  preferred_method <- preference[preference %in% available_methods][1]
  if (is.na(preferred_method)) preferred_method <- available_methods[1]
  quality_cv <- cv_predictions[
    cv_predictions$cv_method == preferred_method, , drop = FALSE]
  log_msg("Evaluation CV method: ", preferred_method)
}

if (nrow(quality_cv) == 0) {
  quality_cv <- data.frame(
    point_id = if (CODE_COL %in% names(model_df)) model_df[[CODE_COL]] else seq_len(nrow(model_df)),
    code = if (CODE_COL %in% names(model_df)) model_df[[CODE_COL]] else seq_len(nrow(model_df)),
    cv_method = "in_sample_fallback",
    fold = NA_integer_,
    x = st_coordinates(pts_model_sf)[, 1],
    y = st_coordinates(pts_model_sf)[, 2],
    lon = if (LON_COL %in% names(model_df)) model_df[[LON_COL]] else NA_real_,
    lat = if (LAT_COL %in% names(model_df)) model_df[[LAT_COL]] else NA_real_,
    observed = model_df[[TARGET_FIELD]],
    regression_only = model_df$reg_pred,
    ordinary_kriging = NA_real_,
    regression_kriging = rk_back_transform_values(model_df$reg_pred_model + model_df$residual, TARGET_TRANSFORM_ACTIVE),
    ok_variance = NA_real_,
    rk_residual_variance = NA_real_,
    stringsAsFactors = FALSE
  )
  scientific_warnings <- unique(c(scientific_warnings, "Không có dự báo cross-validation; evaluation phải dùng fallback in-sample."))
}

quality_context <- list(
  target_field = TARGET_FIELD,
  prediction_method = final_prediction_method,
  target_name = TARGET_NAME,
  output_dir = out_path("06_report"),
  config_path = EVALUATION_PROFILE_FILE,
  target_metadata = target_metadata_active,
  observed = model_df[[TARGET_FIELD]],
  regression_predicted = model_df$reg_pred,
  target_transform = list(
    requested = target_transform_info$requested,
    used = TARGET_TRANSFORM_ACTIVE,
    profile = target_transform_info$profile_name,
    reason = target_transform_info$recommendation$reason %||% "",
    requires_nonnegative = target_transform_info$requires_nonnegative,
    log_backtransform_bias_correction_requested =
      LOG_BACKTRANSFORM_BIAS_CORRECTION_ACTIVE,
    log_backtransform_bias_correction =
      LOG_BACKTRANSFORM_BIAS_CORRECTION_APPLIED,
    bias_correction_basis = if (
      LOG_BACKTRANSFORM_BIAS_CORRECTION_APPLIED) {
      "partial_residual_kriging_variance_only"
    } else {
      "not_applied"
    },
    metric_scale = "original units",
    ok_baseline_scale = ifelse(
      identical(TARGET_TRANSFORM_ACTIVE, "log1p"),
      "log1p(target), direct inverse before CV metrics",
      "original units"
    )
  ),
  residuals = model_df$residual,
  coordinates = as.data.frame(st_coordinates(pts_model_sf)),
  variogram_params = list(
    model = vgm_params$model,
    nugget = vgm_params$nugget,
    psill = vgm_params$psill,
    range = vgm_params$range,
    practical_range = fitted_practical_range,
    lag_width = VARIOGRAM_WIDTH,
    fit_sse = best_variogram_sse,
    fit_method = if (fitted_vgm_pure_nugget) NA_integer_ else 7L,
    singular = fitted_vgm_singular,
    anisotropy_ratio = anisotropy_ratio,
    anisotropy_major_direction = anisotropy_major_direction,
    robust_relative_difference = robust_relative_difference
  ),
  experimental_variogram = experimental_vgm,
  range_max = VARIOGRAM_RANGE_MAX,
  cv_summary = cv_summary,
  cv_predictions = quality_cv,
  cv_method = if ("cv_method" %in% names(quality_cv) && nrow(quality_cv) > 0) quality_cv$cv_method[1] else NA_character_,
  cv_folds = cv_validation_metadata$outer_folds %||% CV_K_FOLDS,
  cv_refit_variogram = TRUE,
  cv_metadata = cv_validation_metadata,
  cv_stability = if (!is.null(nested_cv_result))
    nested_cv_result$stability else list(),
  cv_observed = quality_cv$observed,
  cv_regression_predicted = quality_cv$regression_only,
  cv_ok_predicted = quality_cv$ordinary_kriging,
  cv_rk_predicted = quality_cv$regression_kriging,
  prediction_sd_values = NULL,
  prediction_sd_summary = uncertainty_summary,
  point_support = point_support_summary,
  extrapolation = extrapolation_summary,
  clipping = list(
    model_dependent = TRUE,
    dependency_scope =
      "observed_target_range_of_current_model_development_points",
    outside_roi_points_are_validation = FALSE,
    interpretation = "audit_only_not_validation_and_not_uncertainty",
    clamp_enabled = isTRUE(CLAMP_TO_SAMPLE_RANGE),
    clamp_lower = sample_min,
    clamp_upper = sample_max,
    clipped_low_percent = clipped_low_percent,
    clipped_high_percent = clipped_high_percent,
    total_clipped_percent = total_clipped_percent,
    unclamped_raster = paste0("../05_final_rk/RK_final_unclamped_",
      TARGET_NAME, "_utm.tif"),
    clipping_mask = paste0("../05_final_rk/RK_clipping_mask_",
      TARGET_NAME, "_utm.tif")
  ),
  messages = scientific_messages,
  warnings = scientific_warnings,
  hard_failures = scientific_hard_failures,
  report_links = list(
    "Interactive variogram" = paste0("interactive/", basename(report_interactive_variogram_file)),
    "Variogram PNG" = paste0("figures/", basename(report_variogram_plot_file)),
    "CV RMSE chart" = ifelse(is.na(cv_rmse_plot_file), "", paste0("figures/", basename(cv_rmse_plot_file))),
    "Detailed tables folder" = "tables/",
    "JSON diagnostics folder" = "json/",
    "RK unclamped raster" = paste0("../05_final_rk/RK_final_unclamped_",
      TARGET_NAME, "_utm.tif"),
    "RK clipping mask" = paste0("../05_final_rk/RK_clipping_mask_",
      TARGET_NAME, "_utm.tif"),
    "Residual kriging SD (legacy RK_uncertainty_STD filename)" = if (uncertainty_available) {
      paste0("../05_final_rk/RK_uncertainty_STD_",
        TARGET_NAME, "_utm.tif")
    } else {
      ""
    },
    "Area of Applicability" = if (isTRUE(extrapolation_summary$available))
      paste0("../05_final_rk/area_of_applicability_", TARGET_NAME,
        "_utm.tif") else ""
  )
)

rk_quality_result <- try(run_rk_quality_evaluation(quality_context), silent = TRUE)
if (inherits(rk_quality_result, "try-error")) {
  log_msg("[WARN] RK quality evaluation failed: ", as.character(rk_quality_result))
} else {
  report_index_file <- out_path("06_report", paste0("index_", TARGET_NAME, ".html"))
  readme_file <- out_path("06_report", paste0("README_", TARGET_NAME, ".txt"))
  writeLines(
    c(
      paste0("Báo cáo Regression Kriging cho chỉ tiêu: ", TARGET_FIELD),
      "",
      paste0("Mở file này trước: ", basename(report_index_file)),
      paste0("Xếp hạng chất lượng: ", rk_quality_result$quality$final_grade, " (", rk_quality_result$quality$final_score, "/100)"),
      "",
      "Hướng dẫn thư mục:",
      "- tables/: các bảng CSV chi tiết để kiểm tra kỹ thuật.",
      "- figures/: biểu đồ PNG dùng trong report.",
      "- interactive/: variogram HTML tương tác để kiểm tra thủ công.",
      "- json/: chẩn đoán dạng JSON cho máy/agent đọc.",
      "- logs/: nhật ký chạy.",
      "",
      "Các bản đồ chính nằm trong ../05_final_rk."
    ),
    readme_file
  )
  log_msg("RK quality grade: ", rk_quality_result$quality$final_grade, " (", rk_quality_result$quality$final_score, "/100)")
  log_msg("Open report first: ", report_index_file)
  log_msg("Interactive variogram in report: ", report_interactive_variogram_file)
}

log_msg("\n[13] Finished.")
log_msg("RK min : ", round(rk_min, 4))
log_msg("RK max : ", round(rk_max, 4))
log_msg("RK mean: ", round(rk_mean, 4))
log_msg("STD mean: ", round(std_mean, 4))
log_msg("Final variogram model: ", vgm_params$model)
log_msg("Final nugget: ", round(vgm_params$nugget, 6))
log_msg("Final psill : ", round(vgm_params$psill, 6))
log_msg("Final range : ", round(vgm_params$range, 2), " m")

cat("\n============================================\n")
cat("REGRESSION KRIGING FINISHED\n")
cat("Output folder: ", OUT_DIR, "\n", sep = "")
cat("============================================\n\n")
