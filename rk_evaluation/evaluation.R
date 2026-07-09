# ============================================================
# RK evaluation module
# Scientific quality assessment for Regression Kriging outputs.
# Uses base R only; optional profiles are loaded from config/evaluation_profiles.R.
# ============================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

rk_eval_make_bins <- function(labels, cuts) {
  bins <- vector("list", length(labels))
  for (i in seq_along(labels)) {
    bins[[i]] <- list(
      label = labels[i],
      min = if (i == 1) NA_real_ else cuts[i - 1],
      max = if (i > length(cuts)) NA_real_ else cuts[i]
    )
  }
  bins
}

rk_eval_default_profiles <- function() {
  common_weights <- list(data_quality = 15, regression_trend = 15, residual_variogram = 25, cross_validation = 30, uncertainty = 10, class_evaluation = 5)
  class_weights <- list(data_quality = 15, regression_trend = 10, residual_variogram = 20, cross_validation = 25, uncertainty = 10, class_evaluation = 20)
  vgm <- list(nugget_sill_good_max = 0.50, nugget_sill_acceptable_max = 0.75, range_min_factor_of_mean_nn = 2.0, range_max_fraction_of_extent = 0.70, warn_if_range_hits_max = TRUE)
  base <- function(display_name, unit, aliases, transform, valid, soft, bins = NULL, weights = common_weights, focus = "balanced") {
    list(display_name = display_name, unit = unit, aliases = aliases, default_transform = transform,
      transform_candidates = unique(c(transform, "none", "log1p")), valid_range = valid, soft_warning_range = soft,
      evaluation_focus = focus, nrmse_mean_thresholds = list(excellent = 0.15, good = 0.25, acceptable = 0.40),
      rmse_thresholds = list(excellent = NA_real_, good = NA_real_, acceptable = NA_real_),
      bias_threshold = list(good_abs_me = 0.10, acceptable_abs_me = 0.20),
      variogram_constraints = vgm, class_bins = list(enabled = !is.null(bins), bins = bins %||% list()), scoring_weights = weights)
  }
  list(
    generic_continuous = base("Chỉ tiêu liên tục", "", character(0), "auto", list(min = NA_real_, max = NA_real_), list(min = NA_real_, max = NA_real_), NULL),
    pH = within(base("pH đất", "pH unit", c("pH", "PH", "soil_pH"), "none", list(min = 3, max = 10), list(min = 3.5, max = 9.5), rk_eval_make_bins(c("Rất chua", "Chua", "Chua nhẹ", "Trung tính", "Kiềm nhẹ", "Kiềm mạnh"), c(4.5, 5.5, 6.5, 7.5, 8.5))), {rmse_thresholds <- list(excellent = 0.20, good = 0.30, acceptable = 0.50)}),
    Humus = within(base("Mùn / Chất hữu cơ", "%", c("Humus", "OM", "OrganicMatter", "SOC"), "auto", list(min = 0, max = 20), list(min = 0.2, max = 10), rk_eval_make_bins(c("Rất thấp", "Thấp", "Trung bình", "Cao", "Rất cao"), c(1, 2, 4, 6))), {nrmse_mean_thresholds <- list(excellent = 0.15, good = 0.20, acceptable = 0.30)}),
    CEC = within(base("Dung tích trao đổi cation", "cmol(+)/kg", c("CEC", "CationExchangeCapacity"), "auto", list(min = 0, max = 80), list(min = 1, max = 60), rk_eval_make_bins(c("Rất thấp", "Thấp", "Trung bình", "Cao", "Rất cao"), c(6, 12, 25, 40))), {nrmse_mean_thresholds <- list(excellent = 0.15, good = 0.20, acceptable = 0.30)}),
    N_total = within(base("Đạm tổng số", "%", c("N", "N_total", "TotalN", "TN"), "auto", list(min = 0, max = 2), list(min = 0.01, max = 1), rk_eval_make_bins(c("Rất thấp", "Thấp", "Trung bình", "Cao", "Rất cao"), c(0.05, 0.10, 0.20, 0.30))), {nrmse_mean_thresholds <- list(excellent = 0.20, good = 0.25, acceptable = 0.35)}),
    P_Olsen = base("Lân dễ tiêu Olsen", "mg/kg", c("P", "P_Olsen", "AvailableP", "OlsenP"), "log1p", list(min = 0, max = 500), list(min = 0, max = 200), rk_eval_make_bins(c("Rất thấp", "Thấp", "Trung bình", "Cao", "Rất cao"), c(5, 10, 20, 40)), class_weights, "class_accuracy"),
    P_Bray = base("Lân dễ tiêu Bray", "mg/kg", c("P_Bray", "AvailableP_Bray", "BrayP"), "log1p", list(min = 0, max = 500), list(min = 0, max = 250), rk_eval_make_bins(c("Rất thấp", "Thấp", "Trung bình", "Cao", "Rất cao"), c(7, 15, 30, 50)), class_weights, "class_accuracy"),
    K_available_mgkg = base("Kali dễ tiêu", "mg/kg", c("K", "K2O", "AvailableK", "K_available"), "auto", list(min = 0, max = 2000), list(min = 0, max = 1000), rk_eval_make_bins(c("Rất thấp", "Thấp", "Trung bình", "Cao", "Rất cao"), c(50, 100, 200, 300)), class_weights, "class_accuracy"),
    K_exchangeable_cmol = base("Kali trao đổi", "cmol(+)/kg", c("K_ex", "ExchangeableK", "K_cmol"), "auto", list(min = 0, max = 5), list(min = 0, max = 3), rk_eval_make_bins(c("Rất thấp", "Thấp", "Trung bình", "Cao", "Rất cao"), c(0.10, 0.20, 0.40, 0.80)), class_weights, "class_accuracy"),
    Ca_exchangeable = base("Canxi trao đổi", "cmol(+)/kg", c("Ca", "Ca_ex", "ExchangeableCa"), "auto", list(min = 0, max = 50), list(min = 0, max = 50), rk_eval_make_bins(c("Thấp", "Trung bình", "Cao", "Rất cao"), c(2, 5, 10))),
    Mg_exchangeable = base("Magie trao đổi", "cmol(+)/kg", c("Mg", "Mg_ex", "ExchangeableMg"), "auto", list(min = 0, max = 20), list(min = 0, max = 20), rk_eval_make_bins(c("Thấp", "Trung bình", "Cao", "Rất cao"), c(0.5, 1.5, 3))),
    S_available = base("Lưu huỳnh dễ tiêu", "mg/kg", c("S", "SO4", "AvailableS"), "auto", list(min = 0, max = 500), list(min = 0, max = 500), rk_eval_make_bins(c("Thấp", "Trung bình", "Du", "Cao"), c(5, 10, 20))),
    B_available = base("Bo dễ tiêu", "mg/kg", c("B", "Boron"), "log1p", list(min = 0, max = 20), list(min = 0, max = 20), rk_eval_make_bins(c("Thiếu", "Du", "Cao", "Nguy cơ độc"), c(0.5, 1, 2)), class_weights, "class_accuracy"),
    Zn_available = base("Kẽm dễ tiêu", "mg/kg", c("Zn", "Zinc"), "log1p", list(min = 0, max = 200), list(min = 0, max = 200), rk_eval_make_bins(c("Thiếu", "Thấp", "Du", "Cao"), c(0.5, 1, 3)), class_weights, "class_accuracy"),
    Cu_available = base("Đồng dễ tiêu", "mg/kg", c("Cu", "Copper"), "log1p", list(min = 0, max = 200), list(min = 0, max = 200), rk_eval_make_bins(c("Thiếu", "Thấp", "Du", "Cao"), c(0.2, 0.5, 2)), class_weights, "class_accuracy"),
    Mn_available = base("Mangan dễ tiêu", "mg/kg", c("Mn", "Manganese"), "log1p", list(min = 0, max = 500), list(min = 0, max = 500), rk_eval_make_bins(c("Thấp", "Trung bình", "Đủ/Cao", "Rất cao"), c(1, 5, 20)), class_weights, "class_accuracy"),
    Fe_available = base("Sắt dễ tiêu", "mg/kg", c("Fe", "Iron"), "log1p", list(min = 0, max = 1000), list(min = 0, max = 1000), rk_eval_make_bins(c("Thấp", "Trung bình", "Du", "Cao"), c(2.5, 4.5, 10)), class_weights, "class_accuracy"),
    EC = base("Độ dẫn điện EC", "dS/m", c("EC", "ECe", "Salinity"), "log1p", list(min = 0, max = 100), list(min = 0, max = 100), rk_eval_make_bins(c("Không mặn", "Mặn nhẹ", "Mặn trung bình", "Mặn nặng", "Mặn rất nặng"), c(2, 4, 8, 16)), class_weights, "class_accuracy")
  )
}

load_evaluation_profiles <- function(config_path = "config/evaluation_profiles.R") {
  profiles <- rk_eval_default_profiles()
  if (file.exists(config_path)) {
    env <- new.env(parent = baseenv())
    env$rk_eval_make_bins <- rk_eval_make_bins
    env$rk_eval_default_profiles <- rk_eval_default_profiles
    try(source(config_path, local = env), silent = TRUE)
    if (exists("EVALUATION_PROFILES", envir = env)) {
      profiles <- utils::modifyList(profiles, get("EVALUATION_PROFILES", envir = env))
    }
  }
  profiles
}

match_indicator_profile <- function(target_field, profiles) {
  clean <- tolower(gsub("[^A-Za-z0-9]+", "", target_field))
  for (nm in names(profiles)) {
    aliases <- profiles[[nm]]$aliases %||% character(0)
    candidates <- tolower(gsub("[^A-Za-z0-9]+", "", unique(c(nm, aliases))))
    if (clean %in% candidates) {
      p <- profiles[[nm]]
      p$profile_name <- nm
      p$profile_matched <- TRUE
      return(p)
    }
  }
  p <- profiles$generic_continuous
  p$profile_name <- "generic_continuous"
  p$profile_matched <- FALSE
  p
}

rk_eval_skewness <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) < 3 || stats::sd(x) == 0) return(NA_real_)
  mean(((x - mean(x)) / stats::sd(x))^3)
}

rk_eval_metrics <- function(observed, predicted) {
  ok <- is.finite(observed) & is.finite(predicted)
  if (!any(ok)) {
    return(list(n = 0, RMSE = NA_real_, MAE = NA_real_, ME = NA_real_, R2_pred = NA_real_, Pearson = NA_real_, NRMSE_mean = NA_real_, NRMSE_range = NA_real_, RPD = NA_real_, RPIQ = NA_real_))
  }
  obs <- observed[ok]
  pred <- predicted[ok]
  err <- pred - obs
  rmse <- sqrt(mean(err^2))
  denom <- sum((obs - mean(obs))^2)
  list(
    n = length(obs),
    RMSE = rmse,
    MAE = mean(abs(err)),
    ME = mean(err),
    R2_pred = ifelse(denom > 0, 1 - sum(err^2) / denom, NA_real_),
    Pearson = suppressWarnings(stats::cor(obs, pred, use = "complete.obs")),
    NRMSE_mean = ifelse(abs(mean(obs)) > 0, rmse / abs(mean(obs)), NA_real_),
    NRMSE_range = ifelse(diff(range(obs)) > 0, rmse / diff(range(obs)), NA_real_),
    RPD = ifelse(rmse > 0, stats::sd(obs) / rmse, NA_real_),
    RPIQ = ifelse(rmse > 0, stats::IQR(obs) / rmse, NA_real_)
  )
}

rk_eval_data_quality <- function(values, coordinates, profile) {
  x <- suppressWarnings(as.numeric(values))
  valid <- is.finite(x)
  xv <- x[valid]
  warnings <- character(0)
  if (length(xv) < 30) warnings <- c(warnings, "Số điểm hợp lệ quá ít; kết quả nội suy có độ tin cậy thấp.")
  vr <- profile$valid_range %||% list(min = NA_real_, max = NA_real_)
  sr <- profile$soft_warning_range %||% list(min = NA_real_, max = NA_real_)
  outside_valid <- sum((!is.na(vr$min) & xv < vr$min) | (!is.na(vr$max) & xv > vr$max), na.rm = TRUE)
  outside_soft <- sum((!is.na(sr$min) & xv < sr$min) | (!is.na(sr$max) & xv > sr$max), na.rm = TRUE)
  if (outside_valid > 0) warnings <- c(warnings, paste0(outside_valid, " giá trị nằm ngoài valid_range của profile."))
  if (outside_soft > 0) warnings <- c(warnings, paste0(outside_soft, " giá trị nằm ngoài soft_warning_range."))
  outlier_count <- 0
  if (length(xv) >= 5) {
    q <- stats::quantile(xv, c(0.25, 0.75), na.rm = TRUE)
    iqr <- q[2] - q[1]
    outlier_count <- sum(xv < q[1] - 1.5 * iqr | xv > q[2] + 1.5 * iqr)
    if (outlier_count / length(xv) > 0.1) warnings <- c(warnings, "Tỷ lệ outlier cao; cần kiểm tra dữ liệu đầu vào.")
  }
  duplicate_count <- NA_integer_
  mean_nn <- NA_real_
  extent_axis <- NA_real_
  sample_density <- NA_real_
  if (!is.null(coordinates) && nrow(coordinates) > 1) {
    xy <- as.matrix(coordinates[, 1:2, drop = FALSE])
    duplicate_count <- sum(duplicated(data.frame(round(xy[, 1], 4), round(xy[, 2], 4))))
    d <- as.matrix(stats::dist(xy))
    diag(d) <- NA_real_
    nn <- apply(d, 1, min, na.rm = TRUE)
    mean_nn <- mean(nn, na.rm = TRUE)
    width <- diff(range(xy[, 1], na.rm = TRUE))
    height <- diff(range(xy[, 2], na.rm = TRUE))
    extent_axis <- max(width, height)
    sample_density <- ifelse(width * height > 0, length(xv) / (width * height / 1e6), NA_real_)
    if (duplicate_count > 0) warnings <- c(warnings, paste0("Co ", duplicate_count, " tọa độ trùng nhau."))
  }
  list(n_total = length(x), n_valid = length(xv), n_missing = sum(!valid), min = min(xv, na.rm = TRUE), max = max(xv, na.rm = TRUE), mean = mean(xv, na.rm = TRUE), median = stats::median(xv, na.rm = TRUE), sd = stats::sd(xv, na.rm = TRUE), cv_percent = 100 * stats::sd(xv, na.rm = TRUE) / abs(mean(xv, na.rm = TRUE)), skewness = rk_eval_skewness(xv), outlier_count = outlier_count, duplicate_coordinate_count = duplicate_count, mean_nearest_neighbor_distance = mean_nn, sample_density_per_km2 = sample_density, extent_major_axis = extent_axis, warnings = unique(warnings))
}

rk_eval_transform_recommendation <- function(values, profile) {
  x <- suppressWarnings(as.numeric(values))
  x <- x[is.finite(x)]
  default <- profile$default_transform %||% "auto"
  candidates <- profile$transform_candidates %||% c("none", "log1p")
  skew <- rk_eval_skewness(x)
  ratio <- ifelse(length(x) > 0 && stats::median(x) > 0, max(x) / stats::median(x), NA_real_)
  if (identical(default, "none")) return(list(transform = "none", reason = "Profile khuyến nghị không transform.", skewness = skew, max_median_ratio = ratio))
  if (any(x < 0) && "log1p" %in% candidates) return(list(transform = "none", reason = "Có giá trị âm, không tự động dùng log1p.", skewness = skew, max_median_ratio = ratio))
  if ((is.finite(skew) && skew > 1) || (is.finite(ratio) && ratio > 5)) return(list(transform = ifelse("log1p" %in% candidates, "log1p", "none"), reason = "Phân bố lệch phải; nên cân nhắc transform.", skewness = skew, max_median_ratio = ratio))
  list(transform = ifelse(default == "auto", "none", default), reason = "Chưa cần transform bắt buộc theo dữ liệu hiện tại.", skewness = skew, max_median_ratio = ratio)
}

assign_value_class <- function(value, bins) {
  if (!is.finite(value)) return(NA_character_)
  for (b in bins) {
    lo <- b$min
    hi <- b$max
    if ((is.na(lo) || value >= lo) && (is.na(hi) || value < hi)) return(b$label)
  }
  NA_character_
}

rk_eval_class_prediction <- function(observed, predicted, profile) {
  cb <- profile$class_bins %||% list(enabled = FALSE)
  if (!isTRUE(cb$enabled)) return(list(enabled = FALSE, warnings = character(0)))
  bins <- cb$bins
  labels <- vapply(bins, function(b) b$label, character(1))
  obs_class <- vapply(observed, assign_value_class, character(1), bins = bins)
  pred_class <- vapply(predicted, assign_value_class, character(1), bins = bins)
  oi <- match(obs_class, labels)
  pi <- match(pred_class, labels)
  ok <- !is.na(oi) & !is.na(pi)
  accuracy <- ifelse(any(ok), mean(oi[ok] == pi[ok]), NA_real_)
  within_one <- ifelse(any(ok), mean(abs(oi[ok] - pi[ok]) <= 1), NA_real_)
  severe <- ifelse(any(ok), mean(abs(oi[ok] - pi[ok]) >= 2), NA_real_)
  cm <- table(factor(obs_class, levels = labels), factor(pred_class, levels = labels))
  warnings <- character(0)
  if (is.finite(accuracy) && accuracy < 0.50) warnings <- c(warnings, "Độ chính xác theo cấp giá trị thấp.")
  if (is.finite(severe) && severe > 0.20) warnings <- c(warnings, "Tỷ lệ sai lệch nghiêm trọng từ 2 cấp trở lên cao.")
  list(enabled = TRUE, observed_class = obs_class, predicted_class = pred_class, class_error_level = ifelse(ok, abs(oi - pi), NA_integer_), class_accuracy = accuracy, within_one_class_rate = within_one, severe_misclassification_rate = severe, confusion_matrix = cm, warnings = warnings)
}

rk_eval_variogram <- function(params, experimental_vgm, coordinates, profile, range_max = NA_real_) {
  warnings <- character(0)
  nugget <- params$nugget %||% 0
  psill <- params$psill %||% NA_real_
  total_sill <- nugget + psill
  range <- params$range %||% NA_real_
  practical <- params$practical_range %||% range
  ratio <- ifelse(is.finite(total_sill) && total_sill > 0, nugget / total_sill, NA_real_)
  cons <- profile$variogram_constraints %||% list()
  dq <- rk_eval_data_quality(rep(1, nrow(coordinates)), coordinates, list())
  mean_nn <- dq$mean_nearest_neighbor_distance
  extent <- dq$extent_major_axis
  if (is.finite(ratio) && ratio > (cons$nugget_sill_acceptable_max %||% 0.75)) warnings <- c(warnings, "Nugget/Sill cao, phần dư có cấu trúc không gian yếu.")
  if (is.finite(practical) && is.finite(mean_nn) && practical < (cons$range_min_factor_of_mean_nn %||% 2) * mean_nn) warnings <- c(warnings, "Range quá ngắn so với mật độ điểm mẫu; bản đồ có thể bị đốm/nhiễu.")
  if (is.finite(practical) && is.finite(extent) && practical > (cons$range_max_fraction_of_extent %||% 0.70) * extent) warnings <- c(warnings, "Range quá dài so với kích thước vùng dữ liệu; có thể đang mô phỏng trend.")
  if (isTRUE(cons$warn_if_range_hits_max) && is.finite(range_max) && is.finite(range) && abs(range - range_max) / max(1, range_max) < 0.02) warnings <- c(warnings, "Range chạm giới hạn tối đa; variogram có thể bị fit ép.")
  low_pair_bins <- NA_integer_
  n_lags <- NA_integer_
  if (!is.null(experimental_vgm) && nrow(experimental_vgm) > 0) {
    n_lags <- nrow(experimental_vgm)
    if ("np" %in% names(experimental_vgm)) {
      low_pair_bins <- sum(experimental_vgm$np < 20, na.rm = TRUE)
      if (low_pair_bins > 0) warnings <- c(warnings, "Một số lag variogram có quá ít cặp điểm.")
    }
  }
  quality <- ifelse(is.finite(ratio) && ratio <= 0.5, "good", ifelse(is.finite(ratio) && ratio <= 0.75, "moderate", "weak"))
  list(model = params$model %||% NA_character_, nugget = nugget, partial_sill = psill, sill = total_sill, range = range, practical_range = practical, nugget_sill_ratio = ratio, range_mean_nn_ratio = ifelse(is.finite(mean_nn) && mean_nn > 0, practical / mean_nn, NA_real_), range_extent_ratio = ifelse(is.finite(extent) && extent > 0, practical / extent, NA_real_), lag_width = params$lag_width %||% NA_real_, n_lags = n_lags, low_pair_bins = low_pair_bins, fit_sse = params$fit_sse %||% NA_real_, quality_label = quality, warnings = unique(warnings))
}

rk_eval_regression <- function(observed, predicted, residuals) {
  m <- rk_eval_metrics(observed, predicted)
  warnings <- character(0)
  if (is.finite(m$R2_pred) && m$R2_pred < 0.1) warnings <- c(warnings, "Regression trend giải thích yếu biến động dữ liệu.")
  if (is.finite(m$R2_pred) && m$R2_pred > 0.6) warnings <- c(warnings, "Regression R² cao; cần kiểm tra overfitting bằng CV.")
  list(metrics = m, residual_mean = mean(residuals, na.rm = TRUE), residual_sd = stats::sd(residuals, na.rm = TRUE), residual_skewness = rk_eval_skewness(residuals), warnings = warnings)
}

rk_eval_cross_validation <- function(observed, predicted_rk, profile, predicted_reg = NULL, predicted_ok = NULL, method = NA_character_, cv_folds = NA_integer_, refit_variogram = NA) {
  m <- rk_eval_metrics(observed, predicted_rk)
  warnings <- character(0)
  if (is.finite(m$R2_pred) && m$R2_pred < 0) warnings <- c(warnings, "R²_pred âm; dự báo kém hơn giá trị trung bình mẫu.")
  if (!is.null(predicted_reg)) {
    br <- rk_eval_metrics(observed, predicted_reg)
    if (is.finite(m$RMSE) && is.finite(br$RMSE) && m$RMSE > 0.95 * br$RMSE) warnings <- c(warnings, "RK không cải thiện rõ so với regression-only.")
  }
  if (identical(method, "in_sample_fallback")) warnings <- c(warnings, "Không có dự báo cross-validation độc lập; chỉ dùng fallback in-sample nên không được xếp hạng cao.")
  if (!is.null(predicted_ok)) {
    bo <- rk_eval_metrics(observed, predicted_ok)
    if (is.finite(m$RMSE) && is.finite(bo$RMSE) && m$RMSE > 0.95 * bo$RMSE) warnings <- c(warnings, "Biến phụ trợ chưa cải thiện rõ so với nội suy không gian đơn thuần.")
  }
  list(metrics = m, method = method, cv_folds = cv_folds, refit_variogram = refit_variogram, leakage_guard = isTRUE(refit_variogram), warnings = unique(warnings))
}

rk_eval_uncertainty <- function(sd_values) {
  x <- as.numeric(sd_values)
  x <- x[is.finite(x)]
  if (length(x) == 0) return(list(available = FALSE, warnings = "Không có uncertainty raster để đánh giá."))
  threshold <- as.numeric(stats::quantile(x, 0.80, na.rm = TRUE))
  high_pct <- mean(x >= threshold) * 100
  warnings <- character(0)
  if (high_pct > 30) warnings <- c(warnings, "Tỷ lệ diện tích uncertainty cao lớn; nên bổ sung mẫu.")
  list(available = TRUE, min_sd = min(x), mean_sd = mean(x), max_sd = max(x), min_variance = min(x^2), mean_variance = mean(x^2), max_variance = max(x^2), high_uncertainty_threshold = threshold, high_uncertainty_area_percent = high_pct, warnings = warnings)
}

rk_eval_component_score <- function(kind, result, profile) {
  if (kind == "data_quality") {
    n <- result$n_valid %||% 0
    s <- ifelse(n >= 100, 100, ifelse(n >= 60, 80, ifelse(n >= 30, 60, 35)))
    if ((result$outlier_count %||% 0) > 0.1 * max(1, n)) s <- s - 15
    return(max(0, s))
  }
  if (kind == "regression_trend") {
    r2 <- result$metrics$R2_pred %||% NA_real_
    if (!is.finite(r2)) return(50)
    return(max(20, min(100, 40 + 80 * r2)))
  }
  if (kind == "residual_variogram") {
    ratio <- result$nugget_sill_ratio %||% NA_real_
    s <- ifelse(!is.finite(ratio), 55, ifelse(ratio <= 0.5, 85, ifelse(ratio <= 0.75, 65, 40)))
    if (length(result$warnings) > 1) s <- s - 10
    return(max(0, s))
  }
  if (kind == "cross_validation") {
    nrmse <- result$metrics$NRMSE_mean %||% NA_real_
    thr <- profile$nrmse_mean_thresholds %||% list(excellent = 0.15, good = 0.25, acceptable = 0.40)
    if (!is.finite(nrmse)) return(50)
    return(ifelse(nrmse <= thr$excellent, 95, ifelse(nrmse <= thr$good, 80, ifelse(nrmse <= thr$acceptable, 65, 40))))
  }
  if (kind == "uncertainty") return(ifelse(isTRUE(result$available), 75, 55))
  if (kind == "class_evaluation") {
    if (!isTRUE(result$enabled)) return(70)
    acc <- result$class_accuracy %||% NA_real_
    if (!is.finite(acc)) return(45)
    return(ifelse(acc >= 0.70, 90, ifelse(acc >= 0.50, 70, 40)))
  }
  50
}

rk_eval_grade <- function(result, profile) {
  w <- profile$scoring_weights %||% rk_eval_default_profiles()$generic_continuous$scoring_weights
  comp <- list(
    data_quality = rk_eval_component_score("data_quality", result$data_quality, profile),
    regression_trend = rk_eval_component_score("regression_trend", result$regression, profile),
    residual_variogram = rk_eval_component_score("residual_variogram", result$variogram, profile),
    cross_validation = rk_eval_component_score("cross_validation", result$cross_validation, profile),
    uncertainty = rk_eval_component_score("uncertainty", result$uncertainty, profile),
    class_evaluation = rk_eval_component_score("class_evaluation", result$class_evaluation, profile)
  )
  score <- sum(unlist(comp[names(w)]) * unlist(w), na.rm = TRUE) / sum(unlist(w), na.rm = TRUE)
  cap <- 100
  if ((result$data_quality$n_valid %||% 999) < 30) cap <- min(cap, 69)
  if (is.finite(result$cross_validation$metrics$R2_pred) && result$cross_validation$metrics$R2_pred < 0) cap <- min(cap, 69)
  if (identical(result$cross_validation$method %||% "", "in_sample_fallback")) cap <- min(cap, 69)
  if (any(grepl("không cải thiện|khong cai thien", result$cross_validation$warnings, ignore.case = TRUE))) cap <- min(cap, 84)
  if (isTRUE(result$class_evaluation$enabled) && is.finite(result$class_evaluation$class_accuracy) && result$class_evaluation$class_accuracy < 0.50 && identical(profile$evaluation_focus, "class_accuracy")) cap <- min(cap, 69)
  score <- min(score, cap)
  grade <- ifelse(score >= 85, "A", ifelse(score >= 70, "B", ifelse(score >= 50, "C", "D")))
  list(final_score = round(score, 1), final_grade = grade, component_scores = comp)
}

rk_eval_fmt <- function(x) {
  if (length(x) == 0 || is.null(x)) return("NA")
  if (is.numeric(x) || is.integer(x)) {
    if (!is.finite(x[1])) return("NA")
    return(format(round(x[1], 3), trim = TRUE))
  }
  as.character(x[1])
}

rk_eval_interpretation <- function(result, profile) {
  paste0("Kết quả nội suy ", result$display_name, " đạt mức ", result$quality$final_grade, " (", result$quality$final_score, "/100). ",
    "RK RMSE = ", rk_eval_fmt(result$cross_validation$metrics$RMSE), " ", result$unit, ", ME = ", rk_eval_fmt(result$cross_validation$metrics$ME), ", R2_pred = ", rk_eval_fmt(result$cross_validation$metrics$R2_pred), ". ",
    "Variogram phần dư: ", result$variogram$model, ", range = ", rk_eval_fmt(result$variogram$range), " m, nugget/sill = ", rk_eval_fmt(result$variogram$nugget_sill_ratio), ". ",
    ifelse(length(result$warnings) > 0, "Cần xem các cảnh báo và đề xuất trước khi dùng bản đồ cho quyết định nông học chi tiết.", "Không có cảnh báo lớn theo ngưỡng hiện tại."))
}

rk_eval_json_sanitize <- function(x) {
  if (is.null(x)) return(NULL)
  if (inherits(x, "table")) x <- as.data.frame(x, stringsAsFactors = FALSE)
  if (is.matrix(x)) x <- as.data.frame(x, stringsAsFactors = FALSE)
  if (is.data.frame(x)) {
    x <- as.data.frame(lapply(x, function(col) {
      if (is.factor(col)) as.character(col) else col
    }), stringsAsFactors = FALSE, check.names = FALSE)
    return(lapply(seq_len(nrow(x)), function(i) rk_eval_json_sanitize(as.list(x[i, , drop = FALSE]))))
  }
  if (is.list(x)) return(lapply(x, rk_eval_json_sanitize))
  if (is.factor(x)) x <- as.character(x)
  if (inherits(x, c("POSIXct", "POSIXlt", "Date"))) x <- as.character(x)
  if (is.character(x)) {
    Encoding(x) <- "UTF-8"
    return(x)
  }
  x
}
rk_eval_write_json <- function(x, path) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Required package jsonlite is missing; run dependency setup before evaluation.", call. = FALSE)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(rk_eval_json_sanitize(x), path, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
  invisible(path)
}

rk_eval_html_escape <- function(x) gsub("<", "&lt;", gsub(">", "&gt;", as.character(x)))
rk_eval_rows <- function(x) {
  paste(vapply(names(x), function(nm) paste0("<tr><th>", rk_eval_html_escape(nm), "</th><td>", rk_eval_html_escape(rk_eval_fmt(x[[nm]])), "</td></tr>"), character(1)), collapse = "\n")
}

rk_eval_write_html <- function(result, path) {
  warnings_html <- if (length(result$warnings) == 0) "<p>Không có cảnh báo theo ngưỡng hiện tại.</p>" else paste0("<div class='warn'>", rk_eval_html_escape(result$warnings), "</div>", collapse = "\n")
  rec_html <- paste0("<li>", rk_eval_html_escape(result$recommendations), "</li>", collapse = "\n")
  cls_rows <- if (isTRUE(result$class_evaluation$enabled)) rk_eval_rows(list(class_accuracy = result$class_evaluation$class_accuracy, within_one_class_rate = result$class_evaluation$within_one_class_rate, severe_misclassification_rate = result$class_evaluation$severe_misclassification_rate)) else "<tr><td colspan='2'>Chỉ tiêu này không bật đánh giá phân cấp.</td></tr>"
  cv_meta <- result$cross_validation[c("method", "cv_folds", "refit_variogram", "leakage_guard")]
  links <- result$report_links %||% list()
  link_html <- paste(vapply(names(links), function(nm) {
    href <- links[[nm]]
    if (is.null(href) || is.na(href) || href == "") return("")
    paste0("<li><a href='", rk_eval_html_escape(href), "'>", rk_eval_html_escape(nm), "</a></li>")
  }, character(1)), collapse = "\n")
  if (nchar(link_html) == 0) link_html <- "<li>Không có liên kết phụ trợ.</li>"

  html <- c(
    "<!doctype html><html><head><meta charset='utf-8'><title>RK evaluation</title>",
    "<style>body{font-family:Arial,sans-serif;margin:24px;color:#222;line-height:1.45}section{margin:22px 0}.grade{display:inline-block;padding:10px 16px;border-radius:6px;background:#222;color:white;font-weight:bold}table{border-collapse:collapse;max-width:1050px;width:100%;margin-top:8px}th,td{border:1px solid #ddd;padding:7px;text-align:left}th{background:#f3f3f3}.warn{background:#fff7df;border-left:4px solid #d9822b;padding:9px;margin:8px 0}.grid{display:grid;grid-template-columns:1fr 1fr;gap:18px}@media(max-width:800px){.grid{grid-template-columns:1fr}}</style></head><body>",
    paste0("<h1>Đánh giá chất lượng Regression Kriging - ", rk_eval_html_escape(result$display_name), "</h1>"),
    paste0("<div class='grade'>Grade ", result$quality$final_grade, " - ", result$quality$final_score, "/100</div>"),
    paste0("<p><b>Kết luận:</b> ", rk_eval_html_escape(result$summary), "</p>"),
    "<section><h2>1. Mở file nào?</h2><p>Đây là report chính. Nếu cần chỉnh variogram, mở liên kết variogram tương tác bên dưới.</p><ul>", link_html, "</ul></section>",
    "<section><h2>2. Tổng quan kết quả</h2><table>",
    rk_eval_rows(list(target = result$target_field, unit = result$unit, profile = result$profile_name, n_valid = result$data_quality$n_valid, transform_recommendation = result$transform_recommendation$transform, variogram_model = result$variogram$model, range_m = result$variogram$range, nugget_sill = result$variogram$nugget_sill_ratio, RK_RMSE = result$cross_validation$metrics$RMSE, RK_MAE = result$cross_validation$metrics$MAE, RK_ME = result$cross_validation$metrics$ME, RK_R2_pred = result$cross_validation$metrics$R2_pred)),
    "</table></section>",
    "<div class='grid'><section><h2>3. Chất lượng dữ liệu đầu vào</h2><table>", rk_eval_rows(result$data_quality[setdiff(names(result$data_quality), "warnings")]), "</table></section>",
    "<section><h2>4. Regression trend</h2><table>", rk_eval_rows(result$regression$metrics), "</table></section></div>",
    "<div class='grid'><section><h2>5. Residual variogram</h2><table>", rk_eval_rows(result$variogram[setdiff(names(result$variogram), "warnings")]), "</table></section>",
    "<section><h2>6. Cross-validation</h2><table>", rk_eval_rows(c(cv_meta, result$cross_validation$metrics)), "</table></section></div>",
    "<div class='grid'><section><h2>7. Phân cấp giá trị</h2><table>", cls_rows, "</table></section>",
    "<section><h2>8. Residual kriging uncertainty STD</h2><p>Đây là độ lệch chuẩn kriging phần dư, chưa bao gồm toàn bộ bất định từ mô hình hồi quy và biến phụ trợ.</p><table>", rk_eval_rows(result$uncertainty[setdiff(names(result$uncertainty), "warnings")]), "</table></section></div>",
    "<section><h2>9. Cảnh báo</h2>", warnings_html, "</section>",
    "<section><h2>10. Đề xuất hành động</h2><ul>", rec_html, "</ul></section>",
    "</body></html>"
  )
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(paste(html, collapse = "\n")), con)
}
rk_eval_recommendations <- function(warnings) {
  txt <- paste(warnings, collapse = " ")
  rec <- character(0)
  if (grepl("outlier|valid_range|soft_warning", txt, ignore.case = TRUE)) rec <- c(rec, "Kiểm tra outlier, đơn vị phân tích và các giá trị ngoài khoảng hợp lý.")
  if (grepl("Range|variogram|Nugget", txt, ignore.case = TRUE)) rec <- c(rec, "Mở variogram tương tác để kiểm tra lại model, nugget, sill và range.")
  if (grepl("Số điểm|So diem|điểm mẫu|diem mau|uncertainty", txt, ignore.case = TRUE)) rec <- c(rec, "Bổ sung điểm mẫu ở vùng thưa mẫu hoặc vùng uncertainty cao.")
  if (grepl("không cải thiện|khong cai thien", txt, ignore.case = TRUE)) rec <- c(rec, "Kiểm tra lại biến phụ trợ, residual variogram và cân nhắc regression-only/OK nếu RK không cải thiện.")
  if (length(rec) == 0) rec <- "Có thể sử dụng bản đồ để tham khảo xu thế không gian, nhưng vẫn cần xem kèm uncertainty và CV."
  unique(rec)
}

rk_eval_model_comparison <- function(cv_summary) {
  if (is.null(cv_summary) || nrow(cv_summary) == 0) return(data.frame())
  out <- cv_summary
  out$Notes <- ""
  if ("model" %in% names(out)) {
    out$Notes[out$model == "Regression Kriging"] <- "RK = regression trend + kriged residual"
    out$Notes[out$model == "Ordinary Kriging"] <- "Spatial-only baseline"
    out$Notes[out$model == "Regression-only"] <- "Covariate trend baseline"
  }
  out
}

rk_eval_cv_detail <- function(context, cls) {
  d <- context$cv_predictions
  if (is.null(d) || nrow(d) == 0) return(data.frame())
  names(d)[names(d) == "regression_only"] <- "predicted_regression"
  names(d)[names(d) == "ordinary_kriging"] <- "predicted_ok_or_idw"
  names(d)[names(d) == "regression_kriging"] <- "predicted_rk"
  d$residual <- d$predicted_rk - d$observed
  d$absolute_error <- abs(d$residual)
  d$squared_error <- d$residual^2
  if (isTRUE(cls$enabled)) {
    d$observed_class <- cls$observed_class
    d$predicted_class <- cls$predicted_class
    d$class_error_level <- cls$class_error_level
  } else {
    d$observed_class <- NA_character_
    d$predicted_class <- NA_character_
    d$class_error_level <- NA_integer_
  }
  d
}

rk_eval_summary_table <- function(result) {
  data.frame(
    target = result$target_field,
    display_name = result$display_name,
    unit = result$unit,
    profile = result$profile_name,
    final_score = result$quality$final_score,
    final_grade = result$quality$final_grade,
    n_valid = result$data_quality$n_valid,
    transform_recommendation = result$transform_recommendation$transform,
    rk_rmse = result$cross_validation$metrics$RMSE,
    rk_mae = result$cross_validation$metrics$MAE,
    rk_me = result$cross_validation$metrics$ME,
    rk_r2_pred = result$cross_validation$metrics$R2_pred,
    nrmse_mean = result$cross_validation$metrics$NRMSE_mean,
    rpd = result$cross_validation$metrics$RPD,
    rpiq = result$cross_validation$metrics$RPIQ,
    variogram_model = result$variogram$model,
    variogram_range = result$variogram$range,
    nugget_sill_ratio = result$variogram$nugget_sill_ratio,
    class_accuracy = ifelse(isTRUE(result$class_evaluation$enabled), result$class_evaluation$class_accuracy, NA_real_),
    severe_misclassification_rate = ifelse(isTRUE(result$class_evaluation$enabled), result$class_evaluation$severe_misclassification_rate, NA_real_),
    n_warnings = length(result$warnings),
    summary = result$summary,
    stringsAsFactors = FALSE
  )
}

run_rk_quality_evaluation <- function(context) {
  profiles <- load_evaluation_profiles(context$config_path %||% "config/evaluation_profiles.R")
  profile <- match_indicator_profile(context$target_field, profiles)
  warnings <- context$warnings %||% character(0)
  if (!isTRUE(profile$profile_matched)) warnings <- unique(c(warnings, "Chưa có Evaluation Profile riêng cho chỉ tiêu này; đang dùng profile tổng quát."))

  dq <- rk_eval_data_quality(context$observed, context$coordinates, profile)
  tr <- rk_eval_transform_recommendation(context$observed, profile)
  reg <- rk_eval_regression(context$observed, context$regression_predicted, context$residuals)
  vg <- rk_eval_variogram(context$variogram_params, context$experimental_variogram, context$coordinates, profile, context$range_max %||% NA_real_)
  cv <- rk_eval_cross_validation(context$cv_observed, context$cv_rk_predicted, profile, context$cv_regression_predicted, context$cv_ok_predicted, context$cv_method %||% NA_character_, context$cv_folds %||% NA_integer_, context$cv_refit_variogram %||% NA)
  cls <- rk_eval_class_prediction(context$cv_observed, context$cv_rk_predicted, profile)
  unc <- rk_eval_uncertainty(context$prediction_sd_values)

  all_warnings <- unique(c(warnings, dq$warnings, tr$reason, reg$warnings, vg$warnings, cv$warnings, cls$warnings, unc$warnings))
  result <- list(
    target_field = context$target_field,
    display_name = profile$display_name %||% context$target_field,
    unit = profile$unit %||% "",
    profile_name = profile$profile_name,
    transform_recommendation = tr,
    data_quality = dq,
    regression = reg,
    variogram = vg,
    cross_validation = cv,
    class_evaluation = cls,
    uncertainty = unc,
    warnings = all_warnings,
    recommendations = rk_eval_recommendations(all_warnings),
    report_links = context$report_links %||% list()
  )
  result$quality <- rk_eval_grade(result, profile)
  result$summary <- rk_eval_interpretation(result, profile)

  out_dir <- context$output_dir
  target <- context$target_name
  write.csv(rk_eval_summary_table(result), file.path(out_dir, paste0("summary_", target, ".csv")), row.names = FALSE)
  write.csv(rk_eval_model_comparison(context$cv_summary), file.path(out_dir, "tables", paste0("model_comparison_", target, ".csv")), row.names = FALSE)
  write.csv(rk_eval_cv_detail(context, cls), file.path(out_dir, "tables", paste0("cv_results_", target, ".csv")), row.names = FALSE)
  if (isTRUE(cls$enabled)) {
    write.csv(data.frame(metric = c("class_accuracy", "within_one_class_rate", "severe_misclassification_rate"), value = c(cls$class_accuracy, cls$within_one_class_rate, cls$severe_misclassification_rate)), file.path(out_dir, "tables", paste0("class_evaluation_", target, ".csv")), row.names = FALSE)
    write.csv(as.data.frame(cls$confusion_matrix), file.path(out_dir, "tables", paste0("confusion_matrix_", target, ".csv")), row.names = FALSE)
  }
  rk_eval_write_json(result, file.path(out_dir, "json", paste0("evaluation_", target, ".json")))
  rk_eval_write_json(vg, file.path(out_dir, "json", paste0("variogram_diagnostics_", target, ".json")))
  rk_eval_write_html(result, file.path(out_dir, paste0("index_", target, ".html")))
  result
}

rk_eval_self_test <- function() {
  profiles <- rk_eval_default_profiles()
  ph <- profiles$pH
  vals <- c(4.2, 5.0, 6.0, 7.0, 8.0, 9.0)
  expected <- c("Rất chua", "Chua", "Chua nhẹ", "Trung tính", "Kiềm nhẹ", "Kiềm mạnh")
  got <- vapply(vals, assign_value_class, character(1), bins = ph$class_bins$bins)
  stopifnot(identical(got, expected))
  m <- rk_eval_metrics(c(1, 2, 3), c(1, 2, 4))
  stopifnot(is.finite(m$RMSE), is.finite(m$MAE), is.finite(m$ME), is.finite(m$R2_pred))
  stopifnot(identical(match_indicator_profile("OM", profiles)$profile_name, "Humus"))
  stopifnot(identical(match_indicator_profile("UnknownX", profiles)$profile_name, "generic_continuous"))
  TRUE
}
