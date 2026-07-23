# ============================================================
# Leakage-resistant spatial validation for Regression Kriging.
# Outer folds are used only for final assessment. Every transform,
# variogram family and neighborhood choice is made within outer training data.
# ============================================================

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}

rk_cv_auto_block_size <- function(points_sf, k = 5L) {
  xy <- sf::st_coordinates(points_sf)
  if (nrow(xy) < 2) return(1)
  width <- diff(range(xy[, 1], na.rm = TRUE))
  height <- diff(range(xy[, 2], na.rm = TRUE))
  area <- max(width * height, 1)
  d <- as.matrix(stats::dist(xy))
  diag(d) <- NA_real_
  nn <- apply(d, 1, min, na.rm = TRUE)
  median_nn <- stats::median(nn[is.finite(nn)], na.rm = TRUE)
  if (!is.finite(median_nn)) median_nn <- 0
  candidate <- max(2 * median_nn, sqrt(area / max(2 * k, 1)))
  upper <- max(width, height) / 2
  if (is.finite(upper) && upper > 0) candidate <- min(candidate, upper)
  max(candidate, 1)
}

rk_cv_normalize_block_size <- function(points_sf, k, configured = "auto") {
  if (is.character(configured) && tolower(configured[1]) == "auto") {
    return(rk_cv_auto_block_size(points_sf, k))
  }
  value <- suppressWarnings(as.numeric(configured[1]))
  if (!is.finite(value) || value <= 0) return(rk_cv_auto_block_size(points_sf, k))
  value
}

rk_cv_plan_from_ids <- function(ids, method, seed, block_size = NA_real_, engine = "base") {
  ids <- as.integer(ids)
  folds <- lapply(sort(unique(ids)), function(fold) {
    list(train = which(ids != fold), test = which(ids == fold))
  })
  folds <- Filter(function(x) length(x$train) > 0 && length(x$test) > 0, folds)
  list(method = method, seed = as.integer(seed), folds = folds, fold_ids = ids,
    effective_folds = length(folds), block_size = block_size, engine = engine)
}

rk_cv_grid_block_plan <- function(points_sf, k, seed, block_size) {
  xy <- sf::st_coordinates(points_sf)
  size <- block_size
  make_keys <- function(current_size) {
    paste(
      floor((xy[, 1] - min(xy[, 1], na.rm = TRUE)) / current_size),
      floor((xy[, 2] - min(xy[, 2], na.rm = TRUE)) / current_size),
      sep = "_"
    )
  }
  keys <- make_keys(size)
  attempt <- 0L
  while (length(unique(keys)) < min(k, nrow(points_sf)) && attempt < 8L) {
    size <- size / 2
    keys <- make_keys(size)
    attempt <- attempt + 1L
  }
  block_counts <- sort(table(keys), decreasing = TRUE)
  effective_k <- max(2L, min(as.integer(k), length(block_counts)))
  set.seed(seed)
  tie_noise <- stats::runif(length(block_counts))
  block_order <- names(block_counts)[order(-as.numeric(block_counts), tie_noise)]
  loads <- rep(0, effective_k)
  assignment <- setNames(integer(length(block_order)), block_order)
  for (block in block_order) {
    fold <- which.min(loads)
    assignment[[block]] <- fold
    loads[fold] <- loads[fold] + as.numeric(block_counts[[block]])
  }
  ids <- as.integer(assignment[keys])
  rk_cv_plan_from_ids(ids, "spatial_block", seed, size, "base_grid")
}

rk_make_cv_plan <- function(points_sf, method, k, seed, block_size = "auto", prediction_raster = NULL) {
  n <- nrow(points_sf)
  if (n < 4) stop("At least four points are required to create spatial CV folds.")
  k <- max(2L, min(as.integer(k), n - 1L))
  method <- tolower(as.character(method)[1])
  size <- rk_cv_normalize_block_size(points_sf, k, block_size)
  set.seed(seed)

  if (identical(method, "random")) {
    return(rk_cv_plan_from_ids(sample(rep(seq_len(k), length.out = n)), method, seed))
  }
  if (identical(method, "spatial_kmeans")) {
    xy <- sf::st_coordinates(points_sf)
    km <- stats::kmeans(scale(xy), centers = k, nstart = 50)
    return(rk_cv_plan_from_ids(km$cluster, method, seed, engine = "stats_kmeans"))
  }
  if (identical(method, "spatial_block")) {
    if (requireNamespace("blockCV", quietly = TRUE)) {
      cv <- suppressWarnings(try(blockCV::cv_spatial(
        x = points_sf, k = k, hexagon = FALSE, size = size,
        selection = "random", iteration = 100, biomod2 = FALSE,
        seed = seed, progress = FALSE, report = FALSE, plot = FALSE
      ), silent = TRUE))
      if (!inherits(cv, "try-error") && !is.null(cv$folds_list)) {
        folds <- lapply(cv$folds_list, function(z) {
          list(train = as.integer(z[[1]]), test = as.integer(z[[2]]))
        })
        folds <- Filter(function(x) length(x$train) > 0 && length(x$test) > 0, folds)
        if (length(folds) >= 2) {
          return(list(method = method, seed = as.integer(seed), folds = folds,
            fold_ids = as.integer(cv$folds_ids), effective_folds = length(folds),
            block_size = as.numeric(cv$size %||% size), engine = "blockCV"))
        }
      }
    }
    return(rk_cv_grid_block_plan(points_sf, k, seed, size))
  }
  if (identical(method, "buffer")) {
    if (!requireNamespace("blockCV", quietly = TRUE)) stop("CV method 'buffer' requires package blockCV.")
    cv <- blockCV::cv_buffer(x = points_sf, size = size, progress = FALSE, report = FALSE)
    folds <- lapply(cv$folds_list, function(z) list(train = as.integer(z[[1]]), test = as.integer(z[[2]])))
    folds <- Filter(function(x) length(x$train) >= 4 && length(x$test) > 0, folds)
    return(list(method = method, seed = as.integer(seed), folds = folds, fold_ids = seq_len(n),
      effective_folds = length(folds), block_size = size, engine = "blockCV"))
  }
  if (identical(method, "nndm")) {
    if (!requireNamespace("blockCV", quietly = TRUE)) stop("CV method 'nndm' requires package blockCV.")
    if (is.null(prediction_raster)) stop("CV method 'nndm' requires a prediction raster.")
    cv <- blockCV::cv_nndm(
      x = points_sf, r = prediction_raster, size = size,
      num_sample = min(10000, terra::ncell(prediction_raster)),
      plot = FALSE, report = FALSE
    )
    folds <- lapply(cv$folds_list, function(z) list(train = as.integer(z[[1]]), test = as.integer(z[[2]])))
    folds <- Filter(function(x) length(x$train) >= 4 && length(x$test) > 0, folds)
    return(list(method = method, seed = as.integer(seed), folds = folds, fold_ids = seq_len(n),
      effective_folds = length(folds), block_size = size, engine = "blockCV"))
  }
  stop(paste0("Unknown CV method: ", method))
}

rk_subset_points <- function(points_sf, idx) points_sf[idx, , drop = FALSE]

rk_maximin_neighbor_grid <- function(nmax_values, radius_values, max_candidates = Inf) {
  grid <- expand.grid(
    nmax_neighbors = sort(unique(as.integer(nmax_values))),
    search_radius = sort(unique(as.numeric(radius_values))),
    stringsAsFactors = FALSE
  )
  grid <- grid[is.finite(grid$nmax_neighbors) & grid$nmax_neighbors > 0 &
    is.finite(grid$search_radius) & grid$search_radius > 0, , drop = FALSE]
  if (nrow(grid) == 0 || nrow(grid) <= max_candidates) return(grid)
  z <- cbind(
    (grid$nmax_neighbors - min(grid$nmax_neighbors)) / max(diff(range(grid$nmax_neighbors)), 1),
    (grid$search_radius - min(grid$search_radius)) / max(diff(range(grid$search_radius)), 1)
  )
  center <- c(0.5, 0.5)
  selected <- which.min(rowSums((z - matrix(center, nrow(z), 2, byrow = TRUE))^2))
  while (length(selected) < max_candidates) {
    remaining <- setdiff(seq_len(nrow(grid)), selected)
    min_dist <- vapply(remaining, function(i) {
      min(rowSums((z[selected, , drop = FALSE] -
        matrix(z[i, ], length(selected), 2, byrow = TRUE))^2))
    }, numeric(1))
    selected <- c(selected, remaining[which.max(min_dist)])
  }
  grid[sort(selected), , drop = FALSE]
}

rk_inner_transform_candidates <- function(target_field, values) {
  requested <- tolower(as.character(TARGET_TRANSFORM %||% "auto")[1])
  if (requested %in% c("none", "log1p")) return(requested)
  candidates <- unique(tolower(as.character(CV_TRANSFORM_CANDIDATES %||% c("none", "log1p"))))
  candidates <- candidates[candidates %in% c("none", "log1p")]
  profiles <- load_evaluation_profiles(EVALUATION_PROFILE_FILE %||% "_UNG_DUNG/engine/config/evaluation_profiles.R")
  profile <- if (exists("TARGET_PROFILE_OVERRIDE") &&
      !is.null(TARGET_PROFILE_OVERRIDE) &&
      TARGET_PROFILE_OVERRIDE %in% names(profiles)) {
    profiles[[TARGET_PROFILE_OVERRIDE]]
  } else {
    match_indicator_profile(target_field, profiles)
  }
  x <- suppressWarnings(as.numeric(values))
  x <- x[is.finite(x)]
  if (any(x <= -1, na.rm = TRUE) ||
      (isTRUE(profile$transform_requires_nonnegative) && any(x < 0, na.rm = TRUE))) {
    candidates <- setdiff(candidates, "log1p")
  }
  if (length(candidates) == 0) candidates <- "none"
  candidates
}

rk_inner_tune_pipeline <- function(model_df, points_sf, regression_formula, target_field,
    target_model_field, manual_vgm, seed, prediction_raster = NULL) {
  inner_plan <- rk_make_cv_plan(
    points_sf, CV_INNER_METHOD, CV_INNER_FOLDS, seed,
    block_size = CV_OUTER_BLOCK_SIZE, prediction_raster = prediction_raster
  )
  transforms <- rk_inner_transform_candidates(target_field, model_df[[target_field]])
  models <- unique(as.character(VARIOGRAM_CANDIDATE_MODELS))
  neighbor_grid <- rk_maximin_neighbor_grid(
    AUTO_NEIGHBOR_NMAX_CANDIDATES, AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES,
    CV_INNER_NEIGHBOR_MAX_CANDIDATES %||% 18
  )
  if (!isTRUE(AUTO_NEIGHBORS)) {
    neighbor_grid <- data.frame(nmax_neighbors = NMAX_NEIGHBORS, search_radius = SEARCH_RADIUS)
  }

  xy <- sf::st_coordinates(points_sf)
  base_df <- model_df
  base_df$.x <- xy[, 1]
  base_df$.y <- xy[, 2]
  rows <- list()
  row_i <- 1L

  for (transform in transforms) {
    work_df <- base_df
    work_df[[target_model_field]] <- rk_transform_values(work_df[[target_field]], transform)
    for (vgm_model in models) {
      predictions <- lapply(seq_len(nrow(neighbor_grid)), function(i) rep(NA_real_, nrow(work_df)))
      fit_failures <- 0L
      singular_fits <- 0L
      pure_nugget_fits <- 0L
      nugget_ratios <- numeric(0)
      range_hits <- logical(0)

      for (fold in inner_plan$folds) {
        train_idx <- fold$train
        test_idx <- fold$test
        train_df <- work_df[train_idx, , drop = FALSE]
        test_df <- work_df[test_idx, , drop = FALSE]
        reg <- try(stats::lm(regression_formula, data = train_df), silent = TRUE)
        if (inherits(reg, "try-error")) {
          fit_failures <- fit_failures + 1L
          next
        }
        trend_test <- suppressWarnings(as.numeric(stats::predict(reg, newdata = test_df)))
        train_df$.residual <- train_df[[target_model_field]] -
          suppressWarnings(as.numeric(stats::predict(reg, newdata = train_df)))
        train_sp <- train_df
        test_sp <- test_df
        sp::coordinates(train_sp) <- ~.x + .y
        sp::coordinates(test_sp) <- ~.x + .y
        sp::proj4string(train_sp) <- sp::CRS(SRS_string = paste0("EPSG:", UTM_EPSG))
        sp::proj4string(test_sp) <- sp::CRS(SRS_string = paste0("EPSG:", UTM_EPSG))

        fit <- fit_variogram_for_cv(
          train_sp, .residual ~ 1, train_df$.residual,
          candidate_models = vgm_model, allow_fallback = FALSE
        )
        if (is.null(fit)) {
          fit_failures <- fit_failures + 1L
          next
        }
        singular <- isTRUE(attr(fit, "singular"))
        singular_fits <- singular_fits + as.integer(singular)
        if (singular) next
        params <- get_vgm_params(fit)
        sill <- params$nugget + params$psill
        pure_nugget <- is_pure_nugget_variogram(fit)
        pure_nugget_fits <- pure_nugget_fits + as.integer(pure_nugget)
        nugget_ratios <- c(
          nugget_ratios,
          ifelse(sill > 0, params$nugget / sill, NA_real_)
        )
        range_hits <- c(
          range_hits,
          is.finite(params$range) &&
            params$range >= 0.98 * VARIOGRAM_RANGE_MAX
        )

        for (j in seq_len(nrow(neighbor_grid))) {
          if (pure_nugget) {
            # No residual covariance: RK must reduce to regression-only.
            predictions[[j]][test_idx] <- trend_test
            next
          }
          pred <- suppressWarnings(try(gstat::krige(
            .residual ~ 1, locations = train_sp, newdata = test_sp, model = fit,
            nmax = neighbor_grid$nmax_neighbors[j],
            maxdist = if (isTRUE(CV_REQUIRE_KRIGING_NEIGHBORS))
              neighbor_grid$search_radius[j] else Inf,
            debug.level = 0
          ), silent = TRUE))
          if (!inherits(pred, "try-error")) {
            predictions[[j]][test_idx] <- trend_test + pred$var1.pred
          }
        }
      }

      for (j in seq_len(nrow(neighbor_grid))) {
        pred_original <- rk_back_transform_values(predictions[[j]], transform)
        metrics <- metric_table(
          work_df[[target_field]], pred_original, NULL,
          "Regression Kriging", paste0("inner_", CV_INNER_METHOD)
        )
        rows[[row_i]] <- data.frame(
          transform = transform, variogram_model = vgm_model,
          nmax_neighbors = neighbor_grid$nmax_neighbors[j],
          search_radius = neighbor_grid$search_radius[j],
          n_total = metrics$n_total, n_predicted = metrics$n_predicted,
          n_missing = metrics$n_missing, RMSE = metrics$RMSE,
          MAE = metrics$MAE, ME = metrics$ME, R2_pred = metrics$R2,
          fit_failure_rate = fit_failures / max(length(inner_plan$folds), 1),
          singular_fit_rate = singular_fits / max(length(inner_plan$folds), 1),
          pure_nugget_fit_rate =
            pure_nugget_fits / max(length(inner_plan$folds), 1),
          mean_nugget_sill_ratio = if (length(nugget_ratios))
            mean(nugget_ratios, na.rm = TRUE) else NA_real_,
          range_hit_fraction = if (length(range_hits))
            mean(range_hits, na.rm = TRUE) else NA_real_,
          inner_method = inner_plan$method,
          inner_folds = inner_plan$effective_folds,
          stringsAsFactors = FALSE
        )
        row_i <- row_i + 1L
      }
    }
  }

  table <- if (length(rows)) do.call(rbind, rows) else data.frame()
  fallback <- list(transform = transforms[1], variogram_model = VARIOGRAM_MODEL,
    nmax_neighbors = NMAX_NEIGHBORS, search_radius = SEARCH_RADIUS)
  if (nrow(table) == 0) {
    return(list(selected = fallback, table = table, plan = inner_plan, fallback = TRUE))
  }
  valid <- is.finite(table$RMSE) &
    table$n_predicted >= max(4, 0.70 * table$n_total) &
    table$singular_fit_rate == 0
  table$selection_score <- Inf
  if (any(valid)) {
    v <- table[valid, , drop = FALSE]
    rank01 <- function(x) {
      if (length(x) <= 1) return(rep(0, length(x)))
      (rank(x, ties.method = "average") - 1) / (length(x) - 1)
    }
    rmse_rank <- rank01(v$RMSE)
    bias_ratio <- pmin(abs(v$ME) / pmax(v$RMSE, 1e-9), 1)
    missing_rate <- v$n_missing / pmax(v$n_total, 1)
    nugget_penalty <- pmax(0, (v$mean_nugget_sill_ratio - 0.50) / 0.50)
    nugget_penalty[!is.finite(nugget_penalty)] <- 0.5
    range_penalty <- pmin(pmax(v$range_hit_fraction, 0), 1)
    r2_penalty <- ifelse(is.finite(v$R2_pred) & v$R2_pred > 0, 0, 1)
    table$selection_score[valid] <-
      0.50 * rmse_rank + 0.15 * bias_ratio + 0.10 * missing_rate +
      0.10 * nugget_penalty + 0.05 * range_penalty + 0.10 * r2_penalty
  }
  acceptable <- table[is.finite(table$selection_score), , drop = FALSE]
  if (nrow(acceptable) == 0) {
    return(list(selected = fallback, table = table, plan = inner_plan, fallback = TRUE))
  }
  best <- acceptable[order(
    acceptable$selection_score, acceptable$RMSE, abs(acceptable$ME)
  ), , drop = FALSE][1, ]
  list(
    selected = list(
      transform = as.character(best$transform),
      variogram_model = as.character(best$variogram_model),
      nmax_neighbors = as.integer(best$nmax_neighbors),
      search_radius = as.numeric(best$search_radius)
    ),
    table = table[order(table$selection_score, table$RMSE), , drop = FALSE],
    plan = inner_plan, fallback = FALSE
  )
}

rk_predict_outer_fold <- function(model_df, points_sf, train_idx, test_idx,
    regression_formula, target_field, target_model_field, manual_vgm, selected) {
  xy <- sf::st_coordinates(points_sf)
  df <- model_df
  df$.x <- xy[, 1]
  df$.y <- xy[, 2]
  transform <- selected$transform
  df[[target_model_field]] <- rk_transform_values(df[[target_field]], transform)
  train_df <- df[train_idx, , drop = FALSE]
  test_df <- df[test_idx, , drop = FALSE]
  reg <- try(stats::lm(regression_formula, data = train_df), silent = TRUE)
  if (inherits(reg, "try-error")) return(list(ok = FALSE, reason = "regression_fit_failed"))
  pred_reg_model <- suppressWarnings(as.numeric(stats::predict(reg, newdata = test_df)))
  train_df$.residual <- train_df[[target_model_field]] -
    suppressWarnings(as.numeric(stats::predict(reg, newdata = train_df)))
  train_sp <- train_df
  test_sp <- test_df
  sp::coordinates(train_sp) <- ~.x + .y
  sp::coordinates(test_sp) <- ~.x + .y
  sp::proj4string(train_sp) <- sp::CRS(SRS_string = paste0("EPSG:", UTM_EPSG))
  sp::proj4string(test_sp) <- sp::CRS(SRS_string = paste0("EPSG:", UTM_EPSG))

  ok_fit <- fit_variogram_for_cv(
    train_sp, stats::as.formula(paste(bt(target_model_field), "~ 1")),
    train_df[[target_model_field]], candidate_models = selected$variogram_model,
    allow_fallback = FALSE
  )
  rk_fit <- fit_variogram_for_cv(
    train_sp, .residual ~ 1, train_df$.residual,
    candidate_models = selected$variogram_model, allow_fallback = FALSE
  )
  if (is.null(ok_fit) || is.null(rk_fit)) {
    return(list(ok = FALSE, reason = "outer_variogram_fit_failed"))
  }
  if (isTRUE(attr(ok_fit, "singular")) || isTRUE(attr(rk_fit, "singular"))) {
    return(list(ok = FALSE, reason = "outer_variogram_singular"))
  }

  maxdist <- if (isTRUE(CV_REQUIRE_KRIGING_NEIGHBORS)) selected$search_radius else Inf
  ok_pred <- suppressWarnings(try(gstat::krige(
    stats::as.formula(paste(bt(target_model_field), "~ 1")),
    train_sp, test_sp, model = ok_fit,
    nmax = selected$nmax_neighbors, maxdist = maxdist,
    debug.level = 0
  ), silent = TRUE))
  rk_pure_nugget <- is_pure_nugget_variogram(rk_fit)
  rk_pred <- if (rk_pure_nugget) {
    NULL
  } else {
    suppressWarnings(try(gstat::krige(
      .residual ~ 1, train_sp, test_sp, model = rk_fit,
      nmax = selected$nmax_neighbors, maxdist = maxdist,
      debug.level = 0
    ), silent = TRUE))
  }

  pred_ok_model <- rep(NA_real_, length(test_idx))
  pred_rk_model <- if (rk_pure_nugget) {
    pred_reg_model
  } else {
    rep(NA_real_, length(test_idx))
  }
  var_ok_model <- rep(NA_real_, length(test_idx))
  var_rk_model <- rep(NA_real_, length(test_idx))
  if (!inherits(ok_pred, "try-error")) {
    pred_ok_model <- ok_pred$var1.pred
    var_ok_model <- ok_pred$var1.var
  }
  if (!rk_pure_nugget && !inherits(rk_pred, "try-error")) {
    pred_rk_model <- pred_reg_model + rk_pred$var1.pred
    var_rk_model <- rk_pred$var1.var
  }
  # Keep Regression-only, OK and RK comparable on the same back-transform.
  # Production bias correction is reported separately and is not used in CV.
  use_bias <- FALSE
  pred_reg <- rk_back_transform_values(pred_reg_model, transform)
  pred_ok <- rk_back_transform_values(pred_ok_model, transform, var_ok_model, use_bias)
  pred_rk <- rk_back_transform_values(pred_rk_model, transform, var_rk_model, use_bias)
  var_ok <- rk_back_transform_variance_values(
    var_ok_model, pred_ok_model, transform, use_bias)
  var_rk <- rk_back_transform_variance_values(
    var_rk_model, pred_rk_model, transform, use_bias)
  rk_params <- get_vgm_params(rk_fit)
  sill <- rk_params$nugget + rk_params$psill
  list(
    ok = TRUE, regression_only = pred_reg, ordinary_kriging = pred_ok,
    regression_kriging = pred_rk, ok_variance = var_ok, rk_variance = var_rk,
    transform = transform, variogram_model = selected$variogram_model,
    nmax_neighbors = selected$nmax_neighbors,
    search_radius = selected$search_radius,
    nugget_sill_ratio = ifelse(sill > 0, rk_params$nugget / sill, NA_real_),
    variogram_range = rk_params$range,
    residual_pure_nugget = rk_pure_nugget
  )
}

rk_aggregate_outer_predictions <- function(raw, model_df, points_sf, target_field) {
  n <- nrow(model_df)
  median_finite <- function(x) {
    x <- x[is.finite(x)]
    if (length(x) == 0) NA_real_ else stats::median(x)
  }
  split_rows <- split(raw, raw$point_index)
  get_agg <- function(name) {
    out <- rep(NA_real_, n)
    for (key in names(split_rows)) {
      out[as.integer(key)] <- median_finite(split_rows[[key]][[name]])
    }
    out
  }
  xy <- sf::st_coordinates(points_sf)
  data.frame(
    point_id = if (CODE_COL %in% names(model_df)) model_df[[CODE_COL]] else seq_len(n),
    code = if (CODE_COL %in% names(model_df)) model_df[[CODE_COL]] else seq_len(n),
    cv_method = "nested_spatial_block", fold = NA_integer_,
    x = xy[, 1], y = xy[, 2],
    lon = if (LON_COL %in% names(model_df)) model_df[[LON_COL]] else NA_real_,
    lat = if (LAT_COL %in% names(model_df)) model_df[[LAT_COL]] else NA_real_,
    observed = model_df[[target_field]],
    regression_only = get_agg("regression_only"),
    ordinary_kriging = get_agg("ordinary_kriging"),
    regression_kriging = get_agg("regression_kriging"),
    ok_variance = get_agg("ok_variance"),
    rk_residual_variance = get_agg("rk_residual_variance"),
    stringsAsFactors = FALSE
  )
}

rk_nested_spatial_cv <- function(model_df, points_sf, regression_formula,
    target_field, target_model_field, manual_vgm, prediction_raster = NULL) {
  repeats <- max(1L, as.integer(CV_OUTER_REPEATS))
  raw_rows <- list()
  fold_rows <- list()
  tuning_rows <- list()
  raw_i <- fold_i <- tuning_i <- 1L

  for (repeat_id in seq_len(repeats)) {
    outer_seed <- as.integer(CV_RANDOM_SEED + 1000L * repeat_id)
    outer_plan <- rk_make_cv_plan(
      points_sf, CV_OUTER_METHOD, CV_OUTER_FOLDS, outer_seed,
      block_size = CV_OUTER_BLOCK_SIZE, prediction_raster = prediction_raster
    )
    for (fold_id in seq_along(outer_plan$folds)) {
      fold <- outer_plan$folds[[fold_id]]
      train_idx <- fold$train
      test_idx <- fold$test
      train_df <- model_df[train_idx, , drop = FALSE]
      train_points <- rk_subset_points(points_sf, train_idx)
      tune <- rk_inner_tune_pipeline(
        train_df, train_points, regression_formula, target_field,
        target_model_field, manual_vgm,
        seed = outer_seed + 37L * fold_id,
        prediction_raster = prediction_raster
      )
      if (nrow(tune$table) > 0) {
        tt <- tune$table
        tt$outer_repeat <- repeat_id
        tt$outer_fold <- fold_id
        tuning_rows[[tuning_i]] <- tt
        tuning_i <- tuning_i + 1L
      }

      pred <- rk_predict_outer_fold(
        model_df, points_sf, train_idx, test_idx, regression_formula,
        target_field, target_model_field, manual_vgm, tune$selected
      )
      status <- if (isTRUE(pred$ok)) "ok" else pred$reason %||% "failed"
      fold_rows[[fold_i]] <- data.frame(
        cv_method = "nested_spatial_block", cv_repeat = repeat_id, fold = fold_id,
        n_train = length(train_idx), n_test = length(test_idx),
        outer_method = outer_plan$method, outer_engine = outer_plan$engine,
        outer_block_size = outer_plan$block_size,
        selected_transform = tune$selected$transform,
        selected_variogram_model = tune$selected$variogram_model,
        selected_nmax_neighbors = tune$selected$nmax_neighbors,
        selected_search_radius = tune$selected$search_radius,
        inner_tuning_fallback = isTRUE(tune$fallback),
        residual_pure_nugget = if (isTRUE(pred$ok)) {
          isTRUE(pred$residual_pure_nugget)
        } else {
          NA
        },
        status = status, stringsAsFactors = FALSE
      )
      fold_i <- fold_i + 1L

      base <- data.frame(
        point_index = test_idx, cv_repeat = repeat_id, fold = fold_id,
        observed = model_df[[target_field]][test_idx], stringsAsFactors = FALSE
      )
      if (isTRUE(pred$ok)) {
        base$regression_only <- pred$regression_only
        base$ordinary_kriging <- pred$ordinary_kriging
        base$regression_kriging <- pred$regression_kriging
        base$ok_variance <- pred$ok_variance
        base$rk_residual_variance <- pred$rk_variance
      } else {
        base$regression_only <- base$ordinary_kriging <-
          base$regression_kriging <- NA_real_
        base$ok_variance <- base$rk_residual_variance <- NA_real_
      }
      raw_rows[[raw_i]] <- base
      raw_i <- raw_i + 1L
    }
  }

  raw <- if (length(raw_rows)) do.call(rbind, raw_rows) else data.frame()
  folds <- if (length(fold_rows)) do.call(rbind, fold_rows) else data.frame()
  tuning <- if (length(tuning_rows)) do.call(rbind, tuning_rows) else data.frame()
  if (nrow(raw) == 0) stop("Nested spatial CV did not create outer predictions.")

  aggregated <- rk_aggregate_outer_predictions(raw, model_df, points_sf, target_field)
  summary <- rbind(
    metric_table(aggregated$observed, aggregated$regression_only, NULL,
      "Regression-only", "nested_spatial_block"),
    metric_table(aggregated$observed, aggregated$ordinary_kriging,
      aggregated$ok_variance, "Ordinary Kriging", "nested_spatial_block"),
    metric_table(aggregated$observed, aggregated$regression_kriging,
      aggregated$rk_residual_variance, "Regression Kriging", "nested_spatial_block")
  )
  summary$evaluation_role <- "primary_outer"

  repeat_metrics <- do.call(rbind, lapply(sort(unique(raw$cv_repeat)), function(rid) {
    z <- raw[raw$cv_repeat == rid, , drop = FALSE]
    out <- rbind(
      metric_table(z$observed, z$regression_only, NULL,
        "Regression-only", "nested_spatial_block"),
      metric_table(z$observed, z$ordinary_kriging, z$ok_variance,
        "Ordinary Kriging", "nested_spatial_block"),
      metric_table(z$observed, z$regression_kriging, z$rk_residual_variance,
        "Regression Kriging", "nested_spatial_block")
    )
    out$cv_repeat <- rid
    out
  }))

  by_repeat <- split(repeat_metrics, repeat_metrics$cv_repeat)
  improvement_reg <- vapply(by_repeat, function(z) {
    rk <- z$RMSE[z$model == "Regression Kriging"]
    reg <- z$RMSE[z$model == "Regression-only"]
    length(rk) && length(reg) && is.finite(rk[1]) &&
      is.finite(reg[1]) && rk[1] < reg[1]
  }, logical(1))
  improvement_ok <- vapply(by_repeat, function(z) {
    rk <- z$RMSE[z$model == "Regression Kriging"]
    ok <- z$RMSE[z$model == "Ordinary Kriging"]
    length(rk) && length(ok) && is.finite(rk[1]) &&
      is.finite(ok[1]) && rk[1] < ok[1]
  }, logical(1))
  rk_repeat <- repeat_metrics[
    repeat_metrics$model == "Regression Kriging", , drop = FALSE]
  stability <- list(
    outer_method = CV_OUTER_METHOD, outer_folds = as.integer(CV_OUTER_FOLDS),
    outer_repeats = repeats, inner_method = CV_INNER_METHOD,
    inner_folds = as.integer(CV_INNER_FOLDS),
    strict_outer_holdout = TRUE, tuning_uses_outer_test = FALSE,
    inner_tuning_fallback_fraction = mean(
      folds$inner_tuning_fallback, na.rm = TRUE),
    pure_nugget_outer_fold_fraction = mean(
      folds$residual_pure_nugget, na.rm = TRUE),
    median_rmse = stats::median(rk_repeat$RMSE, na.rm = TRUE),
    iqr_rmse = stats::IQR(rk_repeat$RMSE, na.rm = TRUE),
    median_r2_pred = stats::median(rk_repeat$R2, na.rm = TRUE),
    rk_better_than_regression_fraction = mean(improvement_reg, na.rm = TRUE),
    rk_better_than_ok_fraction = mean(improvement_ok, na.rm = TRUE)
  )
  list(
    summary = summary, predictions = aggregated, raw_predictions = raw,
    folds = folds, repeat_metrics = repeat_metrics, tuning = tuning,
    stability = stability,
    metadata = list(
      method = "nested_spatial_block", strict_outer_cv = TRUE,
      outer_method = CV_OUTER_METHOD, outer_folds = as.integer(CV_OUTER_FOLDS),
      outer_repeats = repeats, inner_method = CV_INNER_METHOD,
      inner_folds = as.integer(CV_INNER_FOLDS),
      transform_selected_inside_outer_train = TRUE,
      variogram_selected_inside_outer_train = TRUE,
      neighbors_selected_inside_outer_train = TRUE,
      tuning_uses_outer_test = FALSE,
      cv_log_bias_correction_requested =
        isTRUE(CV_LOG_BACKTRANSFORM_BIAS_CORRECTION),
      cv_log_bias_correction = FALSE,
      cv_backtransform_comparison = "direct_inverse_for_all_baselines"
    )
  )
}
