cat("\n============================================\n")
cat("REGRESSION KRIGING - R PURE CODE\n")
cat("============================================\n\n")

source("scripts/00_config.R")

rk_config_override <- Sys.getenv("RK_CONFIG_OVERRIDE", unset = "")
if (nzchar(rk_config_override)) {
  if (!file.exists(rk_config_override)) {
    stop(paste0("RK_CONFIG_OVERRIDE file not found: ", rk_config_override))
  }
  source(rk_config_override)
}

source("rk_evaluation/evaluation.R")

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
  if (!file.exists(path)) {
    stop(paste0("File not found: ", path))
  }
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

  first_number <- suppressWarnings(
    as.numeric(regmatches(base_names, regexpr("[0-9]+", base_names)))
  )

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
      model = "Exp",
      nugget = nugget,
      psill = 0,
      range = 1
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

variogram_candidate_score <- function(sse, params, experimental_vgm) {
  nugget <- suppressWarnings(as.numeric(params$nugget %||% NA_real_))
  psill <- suppressWarnings(as.numeric(params$psill %||% NA_real_))
  total_sill <- nugget + psill
  nugget_sill <- if (is.finite(total_sill) && total_sill > 0) nugget / total_sill else NA_real_
  practical <- variogram_practical_range(params$model, params$range)
  penalty <- 0
  penalty_reasons <- character(0)

  if (is.finite(nugget_sill) && nugget_sill > MAX_NUGGET_SILL_RATIO_WARNING) {
    penalty <- penalty + 0.80
    penalty_reasons <- c(penalty_reasons, "high_nugget_sill")
  } else if (is.finite(nugget_sill) && nugget_sill > 0.50) {
    penalty <- penalty + 0.25
    penalty_reasons <- c(penalty_reasons, "moderate_nugget_sill")
  }

  if (is.finite(params$range) && params$range >= 0.98 * VARIOGRAM_RANGE_MAX) {
    penalty <- penalty + 1.00
    penalty_reasons <- c(penalty_reasons, "range_hits_max")
  }
  if (is.finite(practical) && is.finite(VARIOGRAM_CUTOFF) && practical > MAX_PRACTICAL_RANGE_FACTOR_OF_CUTOFF * VARIOGRAM_CUTOFF) {
    penalty <- penalty + 0.60
    penalty_reasons <- c(penalty_reasons, "practical_range_near_cutoff")
  }
  if ("np" %in% names(experimental_vgm)) {
    low_bins <- sum(experimental_vgm$np < MIN_PAIRS_PER_VARIOGRAM_BIN, na.rm = TRUE)
    if (low_bins > 0) {
      penalty <- penalty + min(0.50, 0.08 * low_bins)
      penalty_reasons <- c(penalty_reasons, "low_lag_pairs")
    }
  }

  list(
    candidate_score = log1p(sse) + penalty,
    diagnostic_penalty = penalty,
    diagnostic_flags = paste(unique(penalty_reasons), collapse = ";"),
    nugget_sill_ratio = nugget_sill,
    practical_range = practical,
    range_hit_max = is.finite(params$range) && params$range >= 0.98 * VARIOGRAM_RANGE_MAX
  )
}
fit_variogram_auto_select <- function(experimental_vgm, residual_values) {
  residual_var <- var(residual_values, na.rm = TRUE)

  if (is.na(residual_var) || residual_var <= 0) {
    residual_var <- 1
  }

  candidates <- expand.grid(
    model = VARIOGRAM_CANDIDATE_MODELS,
    range_factor = VARIOGRAM_INITIAL_RANGE_FACTORS,
    nugget_factor = VARIOGRAM_INITIAL_NUGGET_FACTORS,
    psill_factor = VARIOGRAM_INITIAL_PSILL_FACTORS,
    stringsAsFactors = FALSE
  )

  result_rows <- list()
  fit_objects <- list()
  idx <- 1

  for (i in seq_len(nrow(candidates))) {
    m <- candidates$model[i]

    init_range <- VARIOGRAM_CUTOFF * candidates$range_factor[i]
    init_range <- max(VARIOGRAM_RANGE_MIN, min(init_range, VARIOGRAM_RANGE_MAX))

    init_nugget <- residual_var * candidates$nugget_factor[i]
    init_psill  <- residual_var * candidates$psill_factor[i]

    init_model <- vgm(
      psill = init_psill,
      model = m,
      range = init_range,
      nugget = init_nugget
    )

    fit_try <- suppressWarnings(
      try(
        fit.variogram(
          experimental_vgm,
          model = init_model
        ),
        silent = TRUE
      )
    )

    if (inherits(fit_try, "try-error")) {
      next
    }

    if (any(is.na(fit_try$psill)) ||
        any(is.na(fit_try$range)) ||
        any(fit_try$psill < 0, na.rm = TRUE) ||
        any(fit_try$range < 0, na.rm = TRUE)) {
      next
    }

    params <- get_vgm_params(fit_try)

    if (params$range < VARIOGRAM_RANGE_MIN || params$range > VARIOGRAM_RANGE_MAX) {
      next
    }

    sse <- attr(fit_try, "SSErr")

    if (is.null(sse) || is.na(sse) || !is.finite(sse)) {
      next
    }

    diag_score <- variogram_candidate_score(sse, params, experimental_vgm)

    result_rows[[idx]] <- data.frame(
      model = m,
      init_range = init_range,
      init_nugget = init_nugget,
      init_psill = init_psill,
      fitted_model = params$model,
      fitted_nugget = params$nugget,
      fitted_psill = params$psill,
      fitted_range = params$range,
      practical_range = diag_score$practical_range,
      nugget_sill_ratio = diag_score$nugget_sill_ratio,
      range_hit_max = diag_score$range_hit_max,
      sse = sse,
      diagnostic_penalty = diag_score$diagnostic_penalty,
      diagnostic_flags = diag_score$diagnostic_flags,
      candidate_score = diag_score$candidate_score,
      stringsAsFactors = FALSE
    )

    fit_objects[[idx]] <- fit_try
    idx <- idx + 1
  }

  if (length(result_rows) == 0) {
    return(list(
      fitted = NULL,
      table = data.frame()
    ))
  }

  results <- do.call(rbind, result_rows)
  best_i <- which.min(results$candidate_score)

  return(list(
    fitted = fit_objects[[best_i]],
    table = results[order(results$candidate_score, results$sse), ]
  ))
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
      coverage_95 = NA_real_, mean_standardized_error = NA_real_, Pearson = NA_real_,
      NRMSE_mean = NA_real_, NRMSE_range = NA_real_, RPD = NA_real_, RPIQ = NA_real_,
      stringsAsFactors = FALSE
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
  coverage <- NA_real_
  mean_std_err <- NA_real_

  if (!is.null(variance)) {
    v <- variance[ok]
    v_ok <- !is.na(v) & v > 0
    if (any(v_ok)) {
      s <- sqrt(v[v_ok])
      coverage <- mean(y[v_ok] >= p[v_ok] - 1.96 * s & y[v_ok] <= p[v_ok] + 1.96 * s)
      mean_std_err <- mean(err[v_ok] / s, na.rm = TRUE)
    }
  }

  data.frame(
    cv_method = cv_method, model = model_name, n_total = n_total,
    n_predicted = n_pred, n_missing = n_total - n_pred,
    ME = mean(err, na.rm = TRUE), RMSE = rmse_val, MAE = mae_val,
    R2 = r2_val, NSE = r2_val, standardized_RMSE = std_rmse,
    coverage_95 = coverage, mean_standardized_error = mean_std_err,
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

fit_variogram_for_cv <- function(sp_points, formula_obj, values) {
  exp_try <- suppressWarnings(
    try(
      variogram(
        formula_obj,
        sp_points,
        cutoff = VARIOGRAM_CUTOFF,
        width = VARIOGRAM_WIDTH
      ),
      silent = TRUE
    )
  )

  if (inherits(exp_try, "try-error") || nrow(exp_try) == 0) {
    return(NULL)
  }

  auto_result <- fit_variogram_auto_select(
    experimental_vgm = exp_try,
    residual_values = values
  )

  if (!is.null(auto_result$fitted)) {
    return(auto_result$fitted)
  }

  value_var <- var(values, na.rm = TRUE)
  if (is.na(value_var) || value_var <= 0) value_var <- 1

  init_vgm <- vgm(
    psill = value_var * 0.8,
    model = VARIOGRAM_MODEL,
    range = min(max(MANUAL_RANGE, VARIOGRAM_RANGE_MIN), VARIOGRAM_RANGE_MAX),
    nugget = value_var * 0.1
  )

  fit_try <- suppressWarnings(try(fit.variogram(exp_try, model = init_vgm), silent = TRUE))

  if (inherits(fit_try, "try-error") ||
      any(is.na(fit_try$psill)) ||
      any(is.na(fit_try$range)) ||
      any(fit_try$psill < 0, na.rm = TRUE) ||
      any(fit_try$range < 0, na.rm = TRUE)) {
    return(NULL)
  }

  return(fit_try)
}

make_fold_ids <- function(points_sf, method, k, seed) {
  n <- nrow(points_sf)
  k <- max(2, min(k, n))
  set.seed(seed)

  if (method == "random") {
    return(sample(rep(seq_len(k), length.out = n)))
  }

  if (method == "spatial_kmeans") {
    xy <- st_coordinates(points_sf)
    km <- stats::kmeans(scale(xy), centers = k, nstart = 50)
    return(km$cluster)
  }

  stop(paste0("Unknown CV method: ", method))
}

run_cv_comparison <- function(model_df, points_sf, regression_formula, target_field, cv_method, manual_vgm) {
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

  pred_reg <- rep(NA_real_, nrow(df))
  pred_ok <- rep(NA_real_, nrow(df))
  pred_rk <- rep(NA_real_, nrow(df))
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

    pred_reg[test_idx] <- as.numeric(predict(reg_try, newdata = test_df))
    train_df$.residual <- train_df[[target_field]] - as.numeric(predict(reg_try, newdata = train_df))

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
      target_formula <- as.formula(paste(bt(target_field), "~ 1"))
      ok_fit <- fit_variogram_for_cv(train_sp, target_formula, train_df[[target_field]])
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
          formula = as.formula(paste(bt(target_field), "~ 1")),
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
      pred_ok[test_idx] <- ok_try$var1.pred
      var_ok[test_idx] <- ok_try$var1.var
    }

    if (!inherits(rk_try, "try-error")) {
      pred_rk[test_idx] <- pred_reg[test_idx] + rk_try$var1.pred
      var_rk[test_idx] <- rk_try$var1.var
    }

    fold_rows[[fold_idx]] <- data.frame(
      cv_method = cv_method,
      fold = fold,
      n_train = length(train_idx),
      n_test = length(test_idx),
      ok_variogram_status = ok_vgm_status,
      rk_variogram_status = rk_vgm_status,
      ok_missing = sum(is.na(pred_ok[test_idx])),
      rk_missing = sum(is.na(pred_rk[test_idx])),
      stringsAsFactors = FALSE
    )
    fold_idx <- fold_idx + 1
  }

  observed <- df[[target_field]]
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
    stringsAsFactors = FALSE
  )

  fold_report <- if (length(fold_rows) > 0) do.call(rbind, fold_rows) else data.frame()

  list(
    summary = summary,
    predictions = predictions,
    folds = fold_report
  )
}
auto_select_neighbors <- function(model_df, points_sf, regression_formula, target_field, manual_vgm) {
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
        manual_vgm = manual_vgm
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
'<p class="small">Dung file nay de xem va nan tay variogram. Sau khi chon thong so phu hop, copy block config ve scripts/00_config.R roi chay lai R.</p>',
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
      ". Please set TARGET_FIELD in scripts/00_config.R."
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

scientific_warnings <- character(0)

add_science_warning <- function(message) {
  scientific_warnings <<- unique(c(scientific_warnings, message))
  log_msg("WARNING: ", message)
}

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

pts_raw <- pts_raw[valid_idx, ]

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
    method = "bilinear"
  )
} else {
  out_res <- suppressWarnings(as.numeric(OUTPUT_RESOLUTION))

  if (is.na(out_res) || out_res <= 0) {
    stop("OUTPUT_RESOLUTION must be numeric or 'auto'.")
  }

  first_utm_base <- project(first_r, target_crs, method = "bilinear")

  base_template <- rast(
    ext(first_utm_base),
    resolution = out_res,
    crs = target_crs
  )

  template_raster <- project(first_utm_base, base_template, method = "bilinear")
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

  r_utm <- project(
    r,
    template_raster,
    method = "bilinear"
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
    bt(TARGET_FIELD),
    "~",
    paste(PREDICTORS, collapse = " + ")
  )

  regression_formula <- as.formula(formula_text)
} else {
  regression_formula <- REGRESSION_FORMULA
}

log_msg("Regression formula: ", deparse(regression_formula))

reg_model <- lm(regression_formula, data = model_df)

model_df$reg_pred <- as.numeric(predict(reg_model, newdata = model_df))
model_df$residual <- model_df[[TARGET_FIELD]] - model_df$reg_pred

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
  main = paste("Residual histogram -", TARGET_FIELD),
  xlab = "Residual"
)
save_plot_done(plot_file)

plot_file <- out_path("02_regression_model", paste0("residual_vs_predicted_", TARGET_NAME, ".png"))
png(plot_file, width = 1200, height = 900)
plot(
  model_df$reg_pred,
  model_df$residual,
  pch = 19,
  xlab = "Regression predicted",
  ylab = "Residual",
  main = paste("Residual vs Predicted -", TARGET_FIELD)
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

if (isTRUE(EXPORT_VARIogram_SUGGESTIONS) || VARIOGRAM_MODE == "auto_select") {
  log_msg("Creating constrained variogram suggestions...")

  auto_result <- fit_variogram_auto_select(
    experimental_vgm = experimental_vgm,
    residual_values = model_df$residual
  )

  suggested_vgm <- auto_result$fitted
  candidate_table <- auto_result$table

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
    log_msg("auto_select lỗi. Dùng lại variogram thủ công.")
    fitted_vgm <- manual_vgm
  } else {
    log_msg("Dùng variogram tự động có ràng buộc tốt nhất cho kriging.")
    fitted_vgm <- suggested_vgm
  }
} else if (VARIOGRAM_MODE == "auto") {
  log_msg("Variogram mode: auto")
  fitted_vgm_try <- suppressWarnings(
    try(fit.variogram(experimental_vgm, model = manual_vgm), silent = TRUE)
  )

  if (inherits(fitted_vgm_try, "try-error")) {
    log_msg("Fit variogram tự động lỗi. Dùng lại variogram thủ công.")
    fitted_vgm <- manual_vgm
  } else {
    fitted_vgm <- fitted_vgm_try
    if (any(fitted_vgm$psill < 0, na.rm = TRUE) ||
        any(fitted_vgm$range < 0, na.rm = TRUE)) {
      log_msg("Auto fit tạo thông số âm. Dùng lại variogram thủ công.")
      fitted_vgm <- manual_vgm
    }
  }
} else {
  stop("VARIOGRAM_MODE must be 'manual', 'auto_select', or 'auto'.")
}

fitted_vgm_params <- get_vgm_params(fitted_vgm)
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

if (!is.na(nugget_sill_ratio) && nugget_sill_ratio > MAX_NUGGET_SILL_RATIO_WARNING) {
  add_science_warning(paste0(
    "Tỷ lệ nugget/sill cao (", round(nugget_sill_ratio, 3), "); tính liên tục không gian của phần dư yếu."
  ))
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
    manual_vgm = fitted_vgm
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

if (isTRUE(RUN_CROSS_VALIDATION)) {
  log_msg("\n[8] Cross-validation and model comparison...")

  cv_results <- list()
  for (cv_method in CV_METHODS) {
    log_msg("Running CV method: ", cv_method)
    cv_try <- try(
      run_cv_comparison(
        model_df = model_df,
        points_sf = pts_model_sf,
        regression_formula = regression_formula,
        target_field = TARGET_FIELD,
        cv_method = cv_method,
        manual_vgm = fitted_vgm
      ),
      silent = TRUE
    )

    if (inherits(cv_try, "try-error")) {
      add_science_warning(paste0("Cross-validation lỗi với phương pháp ", cv_method, "."))
      next
    }

    cv_results[[cv_method]] <- cv_try
  }

  if (length(cv_results) > 0) {
    cv_summary <- do.call(rbind, lapply(cv_results, function(x) x$summary))
    cv_predictions <- do.call(rbind, lapply(cv_results, function(x) x$predictions))
    cv_folds <- do.call(rbind, lapply(cv_results, function(x) x$folds))

    if (isTRUE(EXPORT_RAW_CV_TABLES)) {
      write.csv(
        cv_summary,
        out_path("06_report", "tables", paste0("cv_model_comparison_raw_", TARGET_NAME, ".csv")),
        row.names = FALSE
      )

      write.csv(
        cv_predictions,
        out_path("06_report", "tables", paste0("cv_predictions_raw_", TARGET_NAME, ".csv")),
        row.names = FALSE
      )
    }

    write.csv(
      cv_folds,
      out_path("06_report", "tables", paste0("cv_fold_diagnostics_", TARGET_NAME, ".csv")),
      row.names = FALSE
    )

    log_msg("Đã lưu bảng so sánh mô hình CV.")

    cv_plot_rows <- cv_summary[!is.na(cv_summary$RMSE), , drop = FALSE]
    if (nrow(cv_plot_rows) > 0) {
      plot_file <- out_path("06_report", "figures", paste0("cv_rmse_comparison_", TARGET_NAME, ".png"))
      png(plot_file, width = 1400, height = 900)
      bar_cols <- ifelse(
        cv_plot_rows$model == "Regression Kriging", "#d62728",
        ifelse(cv_plot_rows$model == "Ordinary Kriging", "#1f77b4", "#2ca02c")
      )
      barplot(
        height = cv_plot_rows$RMSE,
        names.arg = paste(cv_plot_rows$cv_method, cv_plot_rows$model, sep = "\n"),
        las = 2,
        col = bar_cols,
        ylab = "RMSE",
        main = paste("Cross-validation RMSE comparison -", TARGET_FIELD)
      )
      save_plot_done(plot_file)
      cv_rmse_plot_file <- plot_file
    }

    log_msg("So sánh CV chỉ dùng để chẩn đoán; không dùng như tiêu chí đạt/không đạt cứng cho RK.")

    if (any(cv_summary$n_missing > 0, na.rm = TRUE)) {
      add_science_warning("Một số dự báo kriging trong CV bị thiếu vì không tìm được điểm lân cận trong SEARCH_RADIUS.")
    }
  } else {
    add_science_warning("Cross-validation không tạo được kết quả hợp lệ.")
  }
}

log_msg("\n[9] Kriging residual...")

template <- complete_pc_mask

grid_df <- as.data.frame(
  template,
  xy = TRUE,
  cells = TRUE,
  na.rm = TRUE
)

grid_cells <- grid_df$cell
grid_df <- grid_df[, c("cell", "x", "y")]

coordinates(grid_df) <- ~x + y
proj4string(grid_df) <- CRS(SRS_string = terra::crs(template))

res_krig <- krige(
  formula = residual ~ 1,
  locations = pts_sp,
  newdata = grid_df,
  model = fitted_vgm,
  nmax = NMAX_NEIGHBORS,
  maxdist = SEARCH_RADIUS
)

residual_raster <- template
residual_var_raster <- template

values(residual_raster) <- NA_real_
values(residual_var_raster) <- NA_real_

residual_raster[grid_cells] <- res_krig$var1.pred
residual_var_raster[grid_cells] <- res_krig$var1.var

residual_raster <- mask(residual_raster, complete_pc_mask)
residual_var_raster <- mask(residual_var_raster, complete_pc_mask)

names(residual_raster) <- "kriged_residual"
names(residual_var_raster) <- "residual_kriging_variance"

writeRaster(
  residual_raster,
  out_path("04_kriging_residual", paste0("residual_kriging_", TARGET_NAME, "_utm.tif")),
  overwrite = TRUE
)

writeRaster(
  residual_var_raster,
  out_path("04_kriging_residual", paste0("residual_variance_", TARGET_NAME, "_utm.tif")),
  overwrite = TRUE
)

log_msg("\n[10] Predict regression on PC raster...")

regression_prediction <- terra::predict(
  covs_utm,
  reg_model,
  na.rm = TRUE
)

regression_prediction <- mask(regression_prediction, complete_pc_mask)

names(regression_prediction) <- paste0("regression_prediction_", TARGET_NAME)

writeRaster(
  regression_prediction,
  out_path("05_final_rk", paste0("regression_prediction_", TARGET_NAME, "_utm.tif")),
  overwrite = TRUE
)

log_msg("\n[11] Create final Regression Kriging raster...")

rk_final <- regression_prediction + residual_raster
rk_final <- mask(rk_final, complete_pc_mask)

names(rk_final) <- paste0("RK_", TARGET_NAME)

if (CLAMP_TO_SAMPLE_RANGE) {
  rk_final <- clamp(
    rk_final,
    lower = sample_min,
    upper = sample_max,
    values = TRUE
  )

  rk_final <- mask(rk_final, complete_pc_mask)

  log_msg("Clamped final raster to sample min/max.")
}

residual_var_raster <- clamp(
  residual_var_raster,
  lower = 0,
  values = TRUE
)

rk_std <- sqrt(residual_var_raster)
rk_std <- mask(rk_std, complete_pc_mask)

names(rk_std) <- paste0("RK_STD_", TARGET_NAME)

add_science_warning("RK uncertainty STD hiện chỉ là độ lệch chuẩn kriging phần dư; chưa bao gồm bất định từ mô hình hồi quy hoặc biến phụ trợ.")

writeRaster(
  rk_final,
  out_path("05_final_rk", paste0("RK_final_", TARGET_NAME, "_utm.tif")),
  overwrite = TRUE
)

writeRaster(
  rk_std,
  out_path("05_final_rk", paste0("RK_uncertainty_STD_", TARGET_NAME, "_utm.tif")),
  overwrite = TRUE
)

if (!is.na(EXPORT_EPSG)) {
  export_crs <- paste0("EPSG:", EXPORT_EPSG)

  rk_final_wgs84 <- project(rk_final, export_crs, method = "bilinear")
  rk_std_wgs84 <- project(rk_std, export_crs, method = "bilinear")

  writeRaster(
    rk_final_wgs84,
    out_path("05_final_rk", paste0("RK_final_", TARGET_NAME, "_epsg", EXPORT_EPSG, ".tif")),
    overwrite = TRUE
  )

  writeRaster(
    rk_std_wgs84,
    out_path("05_final_rk", paste0("RK_uncertainty_STD_", TARGET_NAME, "_epsg", EXPORT_EPSG, ".tif")),
    overwrite = TRUE
  )
}

rk_min <- global(rk_final, "min", na.rm = TRUE)[1, 1]
rk_max <- global(rk_final, "max", na.rm = TRUE)[1, 1]
rk_mean <- global(rk_final, "mean", na.rm = TRUE)[1, 1]

std_min <- global(rk_std, "min", na.rm = TRUE)[1, 1]
std_max <- global(rk_std, "max", na.rm = TRUE)[1, 1]
std_mean <- global(rk_std, "mean", na.rm = TRUE)[1, 1]

best_variogram_sse <- NA
if (exists("candidate_table") && nrow(candidate_table) > 0) {
  best_variogram_sse <- min(candidate_table$sse, na.rm = TRUE)
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

if (length(scientific_warnings) == 0) {
  scientific_warnings <- "Không có cảnh báo khoa học nào theo các ngưỡng hiện tại."
}

warning_table <- data.frame(
  id = seq_along(scientific_warnings),
  warning = scientific_warnings,
  stringsAsFactors = FALSE
)

write.csv(
  warning_table,
  out_path("06_report", "tables", paste0("scientific_warnings_", TARGET_NAME, ".csv")),
  row.names = FALSE
)

writeLines(
  c(
    "Cảnh báo khoa học và ghi chú diễn giải",
    paste0("Target: ", TARGET_FIELD),
    "",
    paste0(seq_along(scientific_warnings), ". ", scientific_warnings),
    "",
    "Quan trọng: RK_uncertainty_STD là độ lệch chuẩn kriging phần dư, chưa phải toàn bộ bất định dự báo."
  ),
  out_path("06_report", paste0("warnings_", TARGET_NAME, ".txt"))
)

report <- data.frame(
  run_name = RUN_NAME,
  output_folder = OUT_DIR,
  roi_handling = "not_used_pc_rasters_pre_masked_buffered",
  target = TARGET_FIELD,
  predictors = paste(PREDICTORS, collapse = ", "),
  n_predictors = length(PREDICTORS),
  n_points_raw_valid = nrow(pts_raw),
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
  variogram_mode = VARIOGRAM_MODE,
  final_variogram_model = vgm_params$model,
  final_variogram_nugget = vgm_params$nugget,
  final_variogram_psill = vgm_params$psill,
  final_variogram_range = vgm_params$range,
  final_variogram_practical_range = fitted_practical_range,
  final_nugget_sill_ratio = nugget_sill_ratio,
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
  n_scientific_warnings = length(scientific_warnings),
  rk_min = rk_min,
  rk_max = rk_max,
  rk_mean = rk_mean,
  std_min = std_min,
  std_max = std_max,
  std_mean = std_mean
)

write.csv(
  report,
  out_path("06_report", "tables", paste0("rk_report_", TARGET_NAME, ".csv")),
  row.names = FALSE
)

log_msg("\n[12] Export RK quality evaluation report...")

quality_cv <- data.frame()
if (exists("cv_predictions") && nrow(cv_predictions) > 0) {
  preferred_method <- if ("spatial_kmeans" %in% cv_predictions$cv_method) "spatial_kmeans" else cv_predictions$cv_method[1]
  quality_cv <- cv_predictions[cv_predictions$cv_method == preferred_method, , drop = FALSE]
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
    regression_kriging = model_df$reg_pred + model_df$residual,
    ok_variance = NA_real_,
    rk_residual_variance = NA_real_,
    stringsAsFactors = FALSE
  )
  scientific_warnings <- unique(c(scientific_warnings, "Không có dự báo cross-validation; evaluation phải dùng fallback in-sample."))
}

quality_context <- list(
  target_field = TARGET_FIELD,
  target_name = TARGET_NAME,
  output_dir = out_path("06_report"),
  config_path = EVALUATION_PROFILE_FILE,
  observed = model_df[[TARGET_FIELD]],
  regression_predicted = model_df$reg_pred,
  residuals = model_df$residual,
  coordinates = as.data.frame(st_coordinates(pts_model_sf)),
  variogram_params = list(
    model = vgm_params$model,
    nugget = vgm_params$nugget,
    psill = vgm_params$psill,
    range = vgm_params$range,
    practical_range = fitted_practical_range,
    lag_width = VARIOGRAM_WIDTH,
    fit_sse = best_variogram_sse
  ),
  experimental_variogram = experimental_vgm,
  range_max = VARIOGRAM_RANGE_MAX,
  cv_summary = cv_summary,
  cv_predictions = quality_cv,
  cv_method = if ("cv_method" %in% names(quality_cv) && nrow(quality_cv) > 0) quality_cv$cv_method[1] else NA_character_,
  cv_folds = CV_K_FOLDS,
  cv_refit_variogram = CV_REFIT_VARIOGRAM,
  cv_observed = quality_cv$observed,
  cv_regression_predicted = quality_cv$regression_only,
  cv_ok_predicted = quality_cv$ordinary_kriging,
  cv_rk_predicted = quality_cv$regression_kriging,
  prediction_sd_values = terra::values(rk_std, mat = FALSE),
  warnings = scientific_warnings,
  report_links = list(
    "Interactive variogram" = paste0("interactive/", basename(report_interactive_variogram_file)),
    "Variogram PNG" = paste0("figures/", basename(report_variogram_plot_file)),
    "CV RMSE chart" = ifelse(is.na(cv_rmse_plot_file), "", paste0("figures/", basename(cv_rmse_plot_file))),
    "Detailed tables folder" = "tables/",
    "JSON diagnostics folder" = "json/"
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
