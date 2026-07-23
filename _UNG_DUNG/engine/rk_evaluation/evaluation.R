# ============================================================
# RK evaluation module
# Scientific quality assessment for Regression Kriging outputs.
# Uses base R only; optional profiles are loaded from _UNG_DUNG/engine/config/evaluation_profiles.R.
# ============================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
rk_eval_has_metadata_value <- function(x) {
  if (is.null(x) || length(x) == 0) return(FALSE)
  value <- trimws(as.character(x[1]))
  if (is.na(value) || !nzchar(value)) return(FALSE)
  !tolower(value) %in% c(
    "na", "n/a", "none", "null", "unknown", "unspecified",
    "unvalidated", "not_defined", "not defined"
  ) && !grepl("internal reference only|project default", value,
    ignore.case = TRUE)
}

rk_eval_primary_model_role <- function(x) {
  value <- tolower(trimws(as.character(x)))
  positive <- grepl(
    "model.?development|model.?candidate.?confirmed|primary|training",
    value
  )
  negative <- grepl("validation|holdout|test|sensitivity|pending|exclude", value)
  !is.na(value) & nzchar(value) & positive & !negative
}
rk_eval_missing_metadata <- function(values) {
  names(values)[!vapply(values, rk_eval_has_metadata_value, logical(1))]
}

rk_eval_product_semantics <- function(target_metadata, profile,
    class_evaluation = list(), point_support = list()) {
  confirmed <- isTRUE(target_metadata$confirmed)
  mapping_required <- list(
    unit = target_metadata$unit,
    laboratory_method = target_metadata$laboratory_method
  )
  mapping_missing <- rk_eval_missing_metadata(mapping_required)
  mapping_metadata_complete <- confirmed && length(mapping_missing) == 0
  outside_review_gate <- if (
      !is.null(point_support$outside_review_gate_passed)) {
    isTRUE(point_support$outside_review_gate_passed)
  } else TRUE
  requested_use <- if (rk_eval_has_metadata_value(target_metadata$decision_use)) {
    as.character(target_metadata$decision_use[1])
  } else {
    "soil_property_mapping_and_screening"
  }
  fertilizer_requested <- grepl(
    "fertili|fertiliz|recommend.*rate|rate.*recommend|phan.?bon|phân.?bón",
    requested_use, ignore.case = TRUE
  )
  fertilizer_metadata <- target_metadata$fertilizer_recommendation %||% list()
  recommendation_required <- list(
    crop = target_metadata$crop,
    region = target_metadata$region,
    laboratory_method = target_metadata$laboratory_method,
    unit = target_metadata$unit,
    source = fertilizer_metadata$source
  )
  recommendation_missing <- rk_eval_missing_metadata(recommendation_required)
  recommendation_gate <- confirmed && outside_review_gate &&
    isTRUE(fertilizer_metadata$approved) &&
    length(recommendation_missing) == 0

  messages <- c(
    "Sản phẩm là bản đồ thuộc tính/hàm lượng đất; không phải bản đồ liều phân bón."
  )
  hard_failures <- character(0)
  if (!confirmed) {
    hard_failures <- c(hard_failures,
      paste0(
        "Metadata chỉ tiêu chưa confirmed=true; sản phẩm giữ trạng thái DRAFT, ",
        "không được phân cấp hoặc dùng cho khuyến cáo."
      ))
  }
  if (confirmed && !mapping_metadata_complete) {
    hard_failures <- c(hard_failures, paste0(
      "Target metadata confirmed=true but continuous mapping metadata is incomplete; missing: ",
      paste(mapping_missing, collapse = ", "),
      ". Product remains DRAFT_INCOMPLETE_TARGET_METADATA and cannot be auto-ACCEPTED."
    ))
  }
  if (confirmed && !outside_review_gate) {
    hard_failures <- c(hard_failures, paste0(
      "Outside-ROI governance gate chưa đạt; sản phẩm giữ trạng thái ",
      "DRAFT_PENDING_OUTSIDE_REVIEW. Continuous run chỉ dùng cho QA/sensitivity, ",
      "không được auto-ACCEPT."
    ))
  }
  if (fertilizer_requested && !recommendation_gate) {
    hard_failures <- c(hard_failures, paste0(
      "decision_use yêu cầu khuyến cáo phân bón nhưng recommendation gate không đạt",
      if (length(recommendation_missing) > 0) paste0(
        "; thiếu: ", paste(recommendation_missing, collapse = ", ")) else "",
      ". Bản đồ chỉ được xuất như sản phẩm thuộc tính đất DRAFT/screening."
    ))
  }

  list(
    product_type = "soil_property_prediction_map",
    product_semantics = if (outside_review_gate &&
        isTRUE(class_evaluation$enabled)) {
      "approved_soil_property_status_map"
    } else {
      "continuous_soil_property_or_concentration_map"
    },
    product_status = if (!confirmed) {
      "DRAFT_UNCONFIRMED_METADATA"
    } else if (!mapping_metadata_complete) {
      "DRAFT_INCOMPLETE_TARGET_METADATA"
    } else if (!outside_review_gate) {
      "DRAFT_PENDING_OUTSIDE_REVIEW"
    } else "SCIENTIFIC_QA",
    metadata_confirmed = confirmed,
    mapping_metadata_complete = mapping_metadata_complete,
    mapping_metadata_required_fields = names(mapping_required),
    mapping_metadata_missing_fields = mapping_missing,
    requested_decision_use = requested_use,
    outside_review_gate_passed = outside_review_gate,
    primary_product_eligible = mapping_metadata_complete && outside_review_gate,
    decision_use = if (recommendation_gate && fertilizer_requested) {
      "input_to_separate_approved_fertilizer_recommendation_workflow"
    } else {
      "soil_property_mapping_and_screening_only"
    },
    fertilizer_rate_product = FALSE,
    fertilizer_recommendation_authorized = FALSE,
    may_feed_separate_recommendation_workflow = recommendation_gate,
    recommendation_language_allowed = recommendation_gate,
    recommendation_gate_required_fields = names(recommendation_required),
    recommendation_gate_missing_fields = recommendation_missing,
    class_status_map_approved = mapping_metadata_complete &&
      outside_review_gate && isTRUE(class_evaluation$enabled) &&
      isTRUE(class_evaluation$gate_passed),
    messages = messages,
    hard_failures = hard_failures
  )
}

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
  common_weights <- list(data_quality = 15, regression_trend = 15, residual_variogram = 25, cross_validation = 40, uncertainty = 0, class_evaluation = 5)
  class_weights <- list(data_quality = 15, regression_trend = 10, residual_variogram = 20, cross_validation = 35, uncertainty = 0, class_evaluation = 20)
  vgm <- list(nugget_sill_good_max = 0.50, nugget_sill_acceptable_max = 0.75, range_min_factor_of_mean_nn = 2.0, range_max_fraction_of_extent = 0.70, warn_if_range_hits_max = TRUE)
  base <- function(display_name, unit, aliases, transform, valid, soft, bins = NULL, weights = common_weights, focus = "balanced", transform_requires_nonnegative = NULL) {
    if (is.null(transform_requires_nonnegative)) {
      vmin <- suppressWarnings(as.numeric(valid$min %||% NA_real_))
      transform_requires_nonnegative <- is.finite(vmin) && vmin >= 0
    }
    list(display_name = display_name, unit = unit, aliases = aliases, default_transform = transform,
      transform_candidates = unique(c(transform, "none", "log1p")), transform_requires_nonnegative = transform_requires_nonnegative,
      valid_range = valid, soft_warning_range = soft,
      evaluation_focus = focus, nrmse_mean_thresholds = list(excellent = 0.15, good = 0.25, acceptable = 0.40),
      rmse_thresholds = list(excellent = NA_real_, good = NA_real_, acceptable = NA_real_),
      bias_threshold = list(good_abs_me = 0.10, acceptable_abs_me = 0.20),
      variogram_constraints = vgm, class_bins = list(enabled = !is.null(bins), approved = FALSE, bins = bins %||% list(), source = 'Project default - internal reference only', version = 'unvalidated', method = 'unspecified', unit = 'unspecified', crop = 'unspecified', region = 'unspecified'), uncertainty_sd_threshold = NA_real_, scoring_weights = weights)
  }
  list(
    generic_continuous = base("Chỉ tiêu liên tục", "", character(0), "auto", list(min = NA_real_, max = NA_real_), list(min = NA_real_, max = NA_real_), NULL),
    pH_H2O = within(base("pH đất đo trong nước", "pH unit", c("pH_H2O"), "none", list(min = 3, max = 10), list(min = 3.5, max = 9.5), rk_eval_make_bins(c("Rất chua", "Chua", "Chua nhẹ", "Trung tính", "Kiềm nhẹ", "Kiềm mạnh"), c(4.5, 5.5, 6.5, 7.5, 8.5))), {rmse_thresholds <- list(excellent = 0.20, good = 0.30, acceptable = 0.50); uncertainty_sd_threshold <- 0.30}),
    pH_KCl = within(base("pH đất đo trong KCl", "pH unit", c("pH_KCl"), "none", list(min = 2, max = 9), list(min = 2.5, max = 8.5), NULL), {rmse_thresholds <- list(excellent = 0.20, good = 0.30, acceptable = 0.50); uncertainty_sd_threshold <- 0.30}),
    OM_pct = within(base("Chất hữu cơ", "%", c("OM_pct", "Humus", "Humus_pct", "OrganicMatter_pct"), "auto", list(min = 0, max = 20), list(min = 0.2, max = 10), rk_eval_make_bins(c("Rất thấp", "Thấp", "Trung bình", "Cao", "Rất cao"), c(1, 2, 4, 6))), {nrmse_mean_thresholds <- list(excellent = 0.15, good = 0.20, acceptable = 0.30)}),
    SOC_pct = within(base("Carbon hữu cơ đất", "%", c("SOC_pct"), "auto", list(min = 0, max = 15), list(min = 0, max = 10), NULL), {nrmse_mean_thresholds <- list(excellent = 0.15, good = 0.20, acceptable = 0.30)}),
    CEC = within(base("Dung tích trao đổi cation", "cmol(+)/kg", c("CEC", "CationExchangeCapacity"), "auto", list(min = 0, max = 80), list(min = 1, max = 60), rk_eval_make_bins(c("Rất thấp", "Thấp", "Trung bình", "Cao", "Rất cao"), c(6, 12, 25, 40))), {nrmse_mean_thresholds <- list(excellent = 0.15, good = 0.20, acceptable = 0.30)}),
    N_total = within(base("Đạm tổng số", "%", c("N", "N_total", "TotalN", "TN"), "auto", list(min = 0, max = 2), list(min = 0.01, max = 1), rk_eval_make_bins(c("Rất thấp", "Thấp", "Trung bình", "Cao", "Rất cao"), c(0.05, 0.10, 0.20, 0.30))), {nrmse_mean_thresholds <- list(excellent = 0.20, good = 0.25, acceptable = 0.35)}),
    P_Olsen_mgkg = base("Lân dễ tiêu Olsen", "mg/kg", c("P_Olsen", "P_Olsen_mgkg", "OlsenP_mgkg"), "log1p", list(min = 0, max = 500), list(min = 0, max = 200), rk_eval_make_bins(c("Rất thấp", "Thấp", "Trung bình", "Cao", "Rất cao"), c(5, 10, 20, 40)), class_weights, "class_accuracy"),
    P_Bray1_mgkg = base("Lân dễ tiêu Bray", "mg/kg", c("P_Bray", "P_Bray1_mgkg", "Bray1P_mgkg"), "log1p", list(min = 0, max = 500), list(min = 0, max = 250), rk_eval_make_bins(c("Rất thấp", "Thấp", "Trung bình", "Cao", "Rất cao"), c(7, 15, 30, 50)), class_weights, "class_accuracy"),
    P_Mehlich3_mgkg = base("Lân chiết Mehlich-3", "mg/kg", c("P_Mehlich3_mgkg", "Mehlich3P_mgkg"), "log1p", list(min = 0, max = 1000), list(min = 0, max = 500), NULL),
    K_available_mgkg = base("Kali dễ tiêu", "mg/kg", c("K_available_mgkg"), "auto", list(min = 0, max = 2000), list(min = 0, max = 1000), rk_eval_make_bins(c("Rất thấp", "Thấp", "Trung bình", "Cao", "Rất cao"), c(50, 100, 200, 300)), class_weights, "class_accuracy"),
    K_exchangeable_cmolkg = base("Kali trao đổi", "cmol(+)/kg", c("K_exchangeable_cmolkg"), "auto", list(min = 0, max = 5), list(min = 0, max = 3), rk_eval_make_bins(c("Rất thấp", "Thấp", "Trung bình", "Cao", "Rất cao"), c(0.10, 0.20, 0.40, 0.80)), class_weights, "class_accuracy"),
    Ca_exchangeable = base("Canxi trao đổi", "cmol(+)/kg", c("Ca", "Ca_ex", "ExchangeableCa"), "auto", list(min = 0, max = 50), list(min = 0, max = 50), rk_eval_make_bins(c("Thấp", "Trung bình", "Cao", "Rất cao"), c(2, 5, 10))),
    Mg_exchangeable = base("Magie trao đổi", "cmol(+)/kg", c("Mg", "Mg_ex", "ExchangeableMg"), "auto", list(min = 0, max = 20), list(min = 0, max = 20), rk_eval_make_bins(c("Thấp", "Trung bình", "Cao", "Rất cao"), c(0.5, 1.5, 3))),
    S_available = base("Lưu huỳnh dễ tiêu", "mg/kg", c("S", "SO4", "AvailableS"), "auto", list(min = 0, max = 500), list(min = 0, max = 500), rk_eval_make_bins(c("Thấp", "Trung bình", "Du", "Cao"), c(5, 10, 20))),
    B_available = base("Bo dễ tiêu", "mg/kg", c("B", "Boron"), "log1p", list(min = 0, max = 20), list(min = 0, max = 20), rk_eval_make_bins(c("Thiếu", "Du", "Cao", "Nguy cơ độc"), c(0.5, 1, 2)), class_weights, "class_accuracy"),
    Zn_available = base("Kẽm dễ tiêu", "mg/kg", c("Zn", "Zinc"), "log1p", list(min = 0, max = 200), list(min = 0, max = 200), rk_eval_make_bins(c("Thiếu", "Thấp", "Du", "Cao"), c(0.5, 1, 3)), class_weights, "class_accuracy"),
    Cu_available = base("Đồng dễ tiêu", "mg/kg", c("Cu", "Copper"), "log1p", list(min = 0, max = 200), list(min = 0, max = 200), rk_eval_make_bins(c("Thiếu", "Thấp", "Du", "Cao"), c(0.2, 0.5, 2)), class_weights, "class_accuracy"),
    Mn_available = base("Mangan dễ tiêu", "mg/kg", c("Mn", "Manganese"), "log1p", list(min = 0, max = 500), list(min = 0, max = 500), rk_eval_make_bins(c("Thấp", "Trung bình", "Đủ/Cao", "Rất cao"), c(1, 5, 20)), class_weights, "class_accuracy"),
    Fe_available = base("Sắt dễ tiêu", "mg/kg", c("Fe", "Iron"), "log1p", list(min = 0, max = 1000), list(min = 0, max = 1000), rk_eval_make_bins(c("Thấp", "Trung bình", "Du", "Cao"), c(2.5, 4.5, 10)), class_weights, "class_accuracy"),
    ECe_dSm = base("Độ dẫn điện EC", "dS/m", c("ECe_dSm"), "log1p", list(min = 0, max = 100), list(min = 0, max = 100), rk_eval_make_bins(c("Không mặn", "Mặn nhẹ", "Mặn trung bình", "Mặn nặng", "Mặn rất nặng"), c(2, 4, 8, 16)), class_weights, "class_accuracy")
  )
}

load_evaluation_profiles <- function(config_path = "_UNG_DUNG/engine/config/evaluation_profiles.R") {
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
  ambiguous <- list(
    ph = "Tên pH không xác định phép đo pH_H2O hay pH_KCl.",
    soilph = "Tên soil_pH không xác định phép đo pH_H2O hay pH_KCl.",
    p = "Tên P không xác định phương pháp Olsen, Bray hay Mehlich và đơn vị.",
    availablep = "Tên AvailableP không xác định phương pháp chiết và đơn vị.",
    k = "Tên K không xác định kali tổng số, trao đổi hay dễ tiêu và đơn vị.",
    k2o = "K2O là dạng quy đổi, không tự động đồng nhất với K trao đổi hoặc K dễ tiêu.",
    availablek = "Tên AvailableK không xác định phương pháp và đơn vị.",
    soc = "SOC không đồng nhất với OM/Humus nếu chưa có hệ số chuyển đổi và phương pháp.",
    om = "OM cần ghi rõ đơn vị phần trăm và phương pháp xác định.",
    ec = "EC cần ghi rõ ECe, EC1:5 hoặc phương pháp đo và đơn vị.",
    n = "Tên N không xác định đạm tổng số, khoáng hay dạng chiết và đơn vị.",
    ca = "Tên Ca không xác định canxi tổng số, trao đổi hay hòa tan và đơn vị.",
    mg = "Tên Mg không xác định magie tổng số, trao đổi hay hòa tan và đơn vị.",
    s = "Tên S không xác định lưu huỳnh tổng số hay dạng chiết và đơn vị.",
    b = "Tên B không xác định bo tổng số hay dễ tiêu, phương pháp chiết và đơn vị.",
    boron = "Tên Boron không xác định dạng phân tích, phương pháp chiết và đơn vị.",
    zn = "Tên Zn không xác định kẽm tổng số hay dễ tiêu, phương pháp chiết và đơn vị.",
    zinc = "Tên Zinc không xác định dạng phân tích, phương pháp chiết và đơn vị.",
    cu = "Tên Cu không xác định đồng tổng số hay dễ tiêu, phương pháp chiết và đơn vị.",
    copper = "Tên Copper không xác định dạng phân tích, phương pháp chiết và đơn vị.",
    mn = "Tên Mn không xác định mangan tổng số hay dễ tiêu, phương pháp chiết và đơn vị.",
    manganese = "Tên Manganese không xác định dạng phân tích, phương pháp chiết và đơn vị.",
    fe = "Tên Fe không xác định sắt tổng số hay dễ tiêu, phương pháp chiết và đơn vị.",
    iron = "Tên Iron không xác định dạng phân tích, phương pháp chiết và đơn vị."
  )
  if (clean %in% names(ambiguous)) {
    p <- profiles$generic_continuous
    p$profile_name <- "generic_continuous"
    p$profile_matched <- FALSE
    p$profile_ambiguous <- TRUE
    p$ambiguity_reason <- ambiguous[[clean]]
    p$manual_review_required <- TRUE
    return(p)
  }
  for (nm in names(profiles)) {
    aliases <- profiles[[nm]]$aliases %||% character(0)
    candidates <- tolower(gsub("[^A-Za-z0-9]+", "", unique(c(nm, aliases))))
    if (clean %in% candidates) {
      p <- profiles[[nm]]
      p$profile_name <- nm
      p$profile_matched <- TRUE
      p$profile_ambiguous <- FALSE
      p$manual_review_required <- FALSE
      return(p)
    }
  }
  p <- profiles$generic_continuous
  p$profile_name <- "generic_continuous"
  p$profile_matched <- FALSE
  p$profile_ambiguous <- FALSE
  p$manual_review_required <- TRUE
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
  if (!isTRUE(cb$enabled)) {
    return(list(
      enabled = FALSE, approved = FALSE, gate_passed = FALSE,
      warnings = character(0),
      messages = "Chỉ tiêu này không có bảng phân cấp."
    ))
  }
  required <- list(
    source = cb$source, unit = cb$unit, laboratory_method = cb$method,
    crop = cb$crop, region = cb$region
  )
  missing <- rk_eval_missing_metadata(required)
  approval_requested <- isTRUE(cb$approved)
  gate_passed <- approval_requested && length(missing) == 0
  if (!gate_passed) {
    return(list(
      enabled = FALSE, approved = FALSE,
      approval_requested = approval_requested, gate_passed = FALSE,
      available_for_reference = TRUE, missing_required_metadata = missing,
      source = cb$source %||% NA_character_,
      version = cb$version %||% NA_character_,
      method = cb$method %||% NA_character_,
      unit = cb$unit %||% NA_character_,
      crop = cb$crop %||% NA_character_,
      region = cb$region %||% NA_character_,
      warnings = character(0),
      messages = if (!approval_requested) {
        paste0(
          "Có ngưỡng phân cấp tham khảo nhưng classification.approved chưa true; ",
          "không tạo/chấm bản đồ trạng thái."
        )
      } else {
        paste0(
          "classification.approved=true nhưng thiếu metadata bắt buộc: ",
          paste(missing, collapse = ", "),
          "; classification gate bị đóng."
        )
      }
    ))
  }
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
  if (is.finite(accuracy) && accuracy < 0.50) {
    warnings <- c(warnings, "Độ chính xác theo cấp giá trị thấp.")
  }
  if (is.finite(severe) && severe > 0.20) {
    warnings <- c(warnings, "Tỷ lệ sai lệch nghiêm trọng từ 2 cấp trở lên cao.")
  }
  list(
    enabled = TRUE, approved = TRUE, gate_passed = TRUE,
    missing_required_metadata = character(0),
    observed_class = obs_class, predicted_class = pred_class,
    class_error_level = ifelse(ok, abs(oi - pi), NA_integer_),
    class_accuracy = accuracy, within_one_class_rate = within_one,
    severe_misclassification_rate = severe, confusion_matrix = cm,
    source = cb$source %||% NA_character_,
    version = cb$version %||% NA_character_,
    method = cb$method %||% NA_character_,
    unit = cb$unit %||% NA_character_,
    crop = cb$crop %||% NA_character_,
    region = cb$region %||% NA_character_,
    warnings = warnings, messages = character(0)
  )
}

rk_eval_variogram <- function(params, experimental_vgm, coordinates, profile, range_max = NA_real_) {
  warnings <- character(0)
  hard_failures <- character(0)
  messages <- character(0)
  nugget <- params$nugget %||% 0
  psill <- params$psill %||% NA_real_
  total_sill <- nugget + psill
  range <- params$range %||% NA_real_
  practical <- params$practical_range %||% range
  ratio <- ifelse(
    is.finite(total_sill) && total_sill > 0,
    nugget / total_sill,
    NA_real_
  )
  pure_nugget <- identical(as.character(params$model %||% ""), "Nug") ||
    (is.finite(ratio) && ratio >= 0.95)
  singular <- isTRUE(params$singular)
  anisotropy_ratio <- suppressWarnings(as.numeric(params$anisotropy_ratio %||% NA_real_))
  robust_relative_difference <- suppressWarnings(
    as.numeric(params$robust_relative_difference %||% NA_real_))
  cons <- profile$variogram_constraints %||% list()
  dq <- rk_eval_data_quality(rep(1, nrow(coordinates)), coordinates, list())
  mean_nn <- dq$mean_nearest_neighbor_distance
  extent <- dq$extent_major_axis

  if (singular) {
    hard_failures <- c(hard_failures,
      "Variogram fit singular; không được tự động chấp nhận mô hình.")
  }
  if (is.finite(ratio) && ratio > (cons$nugget_sill_acceptable_max %||% 0.75)) {
    warnings <- c(warnings, "Nugget/Sill cao, phần dư có cấu trúc không gian yếu.")
  }
  if (pure_nugget) {
    hard_failures <- c(hard_failures,
      "Residual variogram gần pure nugget; RK chưa có bằng chứng cấu trúc không gian để cộng phần dư.")
  }
  if (!pure_nugget &&
      is.finite(practical) && is.finite(mean_nn) &&
      practical < (cons$range_min_factor_of_mean_nn %||% 2) * mean_nn) {
    warnings <- c(warnings,
      "Range quá ngắn so với mật độ điểm mẫu; bản đồ có thể bị đốm/nhiễu.")
  }
  if (!pure_nugget &&
      is.finite(practical) && is.finite(extent) &&
      practical > (cons$range_max_fraction_of_extent %||% 0.70) * extent) {
    warnings <- c(warnings,
      "Range quá dài so với kích thước vùng dữ liệu; có thể đang mô phỏng trend.")
  }
  range_hit_max <- isTRUE(cons$warn_if_range_hits_max) &&
    is.finite(range_max) && is.finite(range) &&
    abs(range - range_max) / max(1, range_max) < 0.02
  if (range_hit_max) {
    warnings <- c(warnings, "Range chạm giới hạn tối đa; variogram có thể bị fit ép.")
    hard_failures <- c(hard_failures,
      "Range variogram chạm giới hạn cấu hình; cần xem thủ công trước khi ACCEPT.")
  }
  if (is.finite(anisotropy_ratio) && anisotropy_ratio >=
      (get0("ANISOTROPY_RATIO_WARNING", ifnotfound = 1.5))) {
    warnings <- c(warnings, paste0(
      "Directional range ratio = ", round(anisotropy_ratio, 2),
      "; phần dư có dấu hiệu anisotropy."))
  }
  if (is.finite(anisotropy_ratio) && anisotropy_ratio >=
      (get0("ANISOTROPY_RATIO_MANUAL_REVIEW", ifnotfound = 2.0))) {
    hard_failures <- c(hard_failures,
      "Anisotropy mạnh nhưng mô hình cuối vẫn đẳng hướng; cần chuyên gia xem directional variogram.")
  }
  if (is.finite(robust_relative_difference) && robust_relative_difference > 0.30) {
    warnings <- c(warnings,
      "Classical và Cressie robust variogram khác nhau đáng kể; cần kiểm tra outlier/support.")
  }

  low_pair_bins <- n_lags <- NA_integer_
  if (!is.null(experimental_vgm) && nrow(experimental_vgm) > 0) {
    n_lags <- nrow(experimental_vgm)
    if ("np" %in% names(experimental_vgm)) {
      low_pair_bins <- sum(experimental_vgm$np < 20, na.rm = TRUE)
      if (low_pair_bins > 0) {
        warnings <- c(warnings, "Một số lag variogram có quá ít cặp điểm.")
      }
    }
  }
  quality <- ifelse(
    singular, "invalid_singular",
    ifelse(is.finite(ratio) && ratio <= 0.5, "good",
      ifelse(is.finite(ratio) && ratio <= 0.75, "moderate", "weak"))
  )
  list(
    model = params$model %||% NA_character_, nugget = nugget,
    partial_sill = psill, sill = total_sill, range = range,
    practical_range = practical, nugget_sill_ratio = ratio,
    range_mean_nn_ratio = ifelse(is.finite(mean_nn) && mean_nn > 0,
      practical / mean_nn, NA_real_),
    range_extent_ratio = ifelse(is.finite(extent) && extent > 0,
      practical / extent, NA_real_),
    range_hit_max = range_hit_max, singular = singular,
    anisotropy_ratio = anisotropy_ratio,
    anisotropy_major_direction = params$anisotropy_major_direction %||% NA_real_,
    robust_relative_difference = robust_relative_difference,
    lag_width = params$lag_width %||% NA_real_, n_lags = n_lags,
    low_pair_bins = low_pair_bins, fit_sse = params$fit_sse %||% NA_real_,
    fit_method = params$fit_method %||% NA_integer_,
    quality_label = quality, messages = unique(messages),
    warnings = unique(warnings), hard_failures = unique(hard_failures)
  )
}

rk_eval_regression <- function(observed, predicted, residuals) {
  m <- rk_eval_metrics(observed, predicted)
  warnings <- character(0)
  messages <- character(0)
  if (is.finite(m$R2_pred) && m$R2_pred < 0.1) {
    warnings <- c(
      warnings,
      "Regression trend giải thích yếu biến động dữ liệu."
    )
  }
  if (is.finite(m$R2_pred) && m$R2_pred > 0.6) {
    messages <- c(
      messages,
      "Regression R² in-sample cao; diễn giải độ khái quát bằng outer spatial CV."
    )
  }
  list(
    metrics = m,
    residual_mean = mean(residuals, na.rm = TRUE),
    residual_sd = stats::sd(residuals, na.rm = TRUE),
    residual_skewness = rk_eval_skewness(residuals),
    messages = messages,
    warnings = warnings
  )
}

rk_eval_cross_validation <- function(observed, predicted_rk, profile,
    predicted_reg = NULL, predicted_ok = NULL, method = NA_character_,
    cv_folds = NA_integer_, refit_variogram = NA, metadata = list(),
    stability = list(), metric_row = NULL) {
  m <- rk_eval_metrics(observed, predicted_rk)
  if (!is.null(metric_row) && nrow(metric_row) > 0) {
    for (nm in c("n_interval", "interval_fraction", "coverage_95",
        "mean_standardized_error", "variance_standardized_RMSE",
        "interval_score_95")) {
      if (nm %in% names(metric_row)) m[[nm]] <- metric_row[[nm]][1]
    }
  }
  warnings <- character(0)
  hard_failures <- character(0)
  messages <- character(0)
  strict_outer <- isTRUE(metadata$strict_outer_cv)
  validation_design <- metadata$validation_design %||% if (strict_outer) {
    "nested_spatial_cv_outer_held_out"
  } else {
    "no_strict_outer_held_out_evaluation"
  }
  validation_task <- metadata$validation_task %||%
    "internal_model_performance_estimation"
  independent_field_validation <- FALSE
  pure_fold_fraction <- suppressWarnings(as.numeric(
    stability$pure_nugget_outer_fold_fraction %||% NA_real_))
  pure_nugget_dominant <- is.finite(pure_fold_fraction) &&
    pure_fold_fraction >= 0.50
  if (is.finite(pure_fold_fraction) && pure_fold_fraction > 0) {
    messages <- c(messages, paste0(
      "Residual variogram là pure nugget trong ",
      round(100 * pure_fold_fraction, 1),
      "% outer folds; tại các fold này RK được đánh giá đúng bằng regression-only."
    ))
  }
  if (pure_nugget_dominant) {
    warnings <- c(warnings, paste0(
      "Pure nugget chiếm ", round(100 * pure_fold_fraction, 1),
      "% outer folds; không có bằng chứng ổn định rằng kriging phần dư cải thiện hồi quy."
    ))
  }
  if (!strict_outer) {
    hard_failures <- c(hard_failures, paste0(
      "Không có outer held-out spatial CV; metric hiện tại không đủ điều kiện ",
      "auto-ACCEPT."))
  }
  if (is.finite(m$R2_pred) && m$R2_pred <= 0) {
    hard_failures <- c(hard_failures,
      "R²_pred outer CV không dương; dự báo không tốt hơn giá trị trung bình mẫu.")
  }
  if (!pure_nugget_dominant && !is.null(predicted_reg)) {
    br <- rk_eval_metrics(observed, predicted_reg)
    if (is.finite(m$RMSE) && is.finite(br$RMSE) && m$RMSE > 0.95 * br$RMSE) {
      warnings <- c(warnings, "RK không cải thiện rõ so với regression-only.")
    }
  }
  if (!is.null(predicted_ok)) {
    bo <- rk_eval_metrics(observed, predicted_ok)
    if (is.finite(m$RMSE) && is.finite(bo$RMSE) && m$RMSE > 0.95 * bo$RMSE) {
      warnings <- c(warnings,
        "Biến phụ trợ chưa cải thiện rõ so với nội suy không gian đơn thuần.")
    }
  }
  if (identical(method, "in_sample_fallback")) {
    hard_failures <- c(hard_failures,
      "Chỉ có fallback in-sample; không được dùng để xếp hạng chất lượng.")
  }
  interval_fraction <- suppressWarnings(as.numeric(
    m$interval_fraction %||% NA_real_))
  if (is.finite(interval_fraction) && interval_fraction > 0 &&
      interval_fraction < 0.80) {
    warnings <- c(warnings, paste0(
      "Chỉ ", round(100 * interval_fraction, 1),
      "% outer predictions có variance hợp lệ; coverage và standardized metrics ",
      "chỉ là chẩn đoán trên tập con này."
    ))
  } else if (!is.finite(interval_fraction) || interval_fraction <= 0) {
    messages <- c(messages,
      "Không có variance hợp lệ ở outer predictions; không tính coverage/standardized metrics.")
  }
  stable_reg <- suppressWarnings(as.numeric(
    stability$rk_better_than_regression_fraction %||% NA_real_))
  if (!pure_nugget_dominant &&
      is.finite(stable_reg) && stable_reg < 0.80) {
    warnings <- c(warnings, paste0(
      "RK chỉ thắng regression-only trong ", round(100 * stable_reg, 1),
      "% outer-CV repeats; hiệu quả chưa ổn định."))
  }
  messages <- c(messages, paste0(
    "Metric chính: ", method, "; outer held-out spatial = ", strict_outer,
    ". Đây là đánh giá nội bộ trên fold được giữ lại khỏi fitting/tuning, ",
    "không phải independent field validation."))
  list(
    metrics = m, method = method, cv_folds = cv_folds,
    refit_variogram = refit_variogram,
    leakage_guard = strict_outer && isFALSE(metadata$tuning_uses_outer_test),
    strict_outer_cv = strict_outer,
    validation_design = validation_design,
    validation_task = validation_task,
    validation_independence =
      "outer_fold_held_out_from_fitting_not_independent_field_sample",
    independent_field_validation = independent_field_validation,
    outer_method = metadata$outer_method %||% NA_character_,
    outer_folds = metadata$outer_folds %||% cv_folds,
    outer_repeats = metadata$outer_repeats %||% 1L,
    inner_method = metadata$inner_method %||% NA_character_,
    inner_folds = metadata$inner_folds %||% NA_integer_,
    stability = stability, messages = unique(messages),
    warnings = unique(warnings), hard_failures = unique(hard_failures)
  )
}

rk_eval_uncertainty <- function(sd_values = NULL, summary = NULL) {
  if (!is.null(summary) && isTRUE(summary$available)) {
    claimed_before_gate <- isTRUE(summary$calibrated) ||
      isTRUE(summary$prediction_interval_claim_allowed)
    summary$uncertainty_type <- summary$uncertainty_type %||%
      "residual_kriging_standard_deviation"
    summary$product_semantics <-
      "partial_residual_kriging_sd_not_total_predictive_uncertainty"
    summary$legacy_filename_compatibility <- "RK_uncertainty_STD_*.tif"
    summary$total_predictive_uncertainty_available <-
      isTRUE(summary$total_predictive_uncertainty_available)
    summary$warnings <- unique(summary$warnings %||% character(0))
    summary$messages <- unique(c(
      summary$messages %||% character(0),
      paste0(
        "Raster chỉ là residual kriging SD; không bao gồm bất định regression, ",
        "covariate, variogram parameter hoặc measurement error."
      )
    ))
    source <- as.character(summary$threshold_source %||% "not_defined")
    high_pct <- suppressWarnings(
      as.numeric(summary$high_uncertainty_area_percent %||% NA_real_))
    if (identical(source, "self_quantile")) {
      summary$warnings <- unique(c(summary$warnings,
        paste0(
          "Ngưỡng residual SD dựa trên quantile của chính raster chỉ dùng để ",
          "hiển thị, không được dùng để chấm điểm."
        )))
      summary$high_uncertainty_area_percent <- NA_real_
    } else if (is.finite(high_pct) && high_pct > 30) {
      summary$warnings <- unique(c(summary$warnings,
        "Diện tích vượt ngưỡng residual kriging SD lớn; nên xem xét bổ sung mẫu."))
    }

    coverage <- suppressWarnings(as.numeric(summary$coverage_95 %||% NA_real_))
    std_rmse <- suppressWarnings(
      as.numeric(summary$variance_standardized_RMSE %||% NA_real_))
    mse <- suppressWarnings(
      as.numeric(summary$mean_standardized_error %||% NA_real_))
    calibration_required <- list(
      method = summary$calibration_method,
      source = summary$calibration_source,
      validation_design = summary$calibration_validation_design
    )
    calibration_missing <- rk_eval_missing_metadata(calibration_required)
    total_basis <- identical(
      summary$calibration_basis %||% "", "total_predictive")
    evidence_approved <- isTRUE(summary$calibration_approved) &&
      length(calibration_missing) == 0
    diagnostic_metrics_ok <- is.finite(coverage) &&
      coverage >= 0.90 && coverage <= 0.98 &&
      is.finite(mse) && abs(mse) <= 0.20 &&
      is.finite(std_rmse) && std_rmse >= 0.80 && std_rmse <= 1.20

    summary$calibration_gate_missing_fields <- calibration_missing
    summary$calibrated <- total_basis &&
      isTRUE(summary$total_predictive_uncertainty_available) &&
      evidence_approved && diagnostic_metrics_ok
    summary$prediction_interval_claim_allowed <- isTRUE(summary$calibrated)
    summary$prediction_interval_type <- if (isTRUE(summary$calibrated)) {
      "calibrated_total_predictive_interval"
    } else {
      "not_available_from_residual_kriging_sd"
    }
    summary$coverage_95_semantics <- if (isTRUE(summary$calibrated)) {
      "calibrated_total_predictive_interval_coverage"
    } else {
      "residual_variance_diagnostic_only_not_prediction_interval_validation"
    }
    summary$used_in_grade <- isTRUE(summary$calibrated)
    if (claimed_before_gate && !isTRUE(summary$calibrated)) {
      summary$warnings <- unique(c(summary$warnings, paste0(
        "Đã chặn nhãn calibrated/prediction interval vì chưa đủ total ",
        "predictive calibration evidence và metadata."
      )))
    }
    return(summary)
  }

  x <- suppressWarnings(as.numeric(sd_values))
  x <- x[is.finite(x)]
  if (length(x) == 0) {
    return(list(
      available = FALSE,
      uncertainty_type = "residual_kriging_standard_deviation",
      product_semantics =
        "partial_residual_kriging_sd_not_total_predictive_uncertainty",
      total_predictive_uncertainty_available = FALSE,
      calibrated = FALSE, prediction_interval_claim_allowed = FALSE,
      prediction_interval_type = "not_available",
      used_in_grade = FALSE,
      messages = "Không có residual kriging SD raster.",
      warnings = character(0)
    ))
  }
  list(
    available = TRUE,
    uncertainty_type = "residual_kriging_standard_deviation",
    product_semantics =
      "partial_residual_kriging_sd_not_total_predictive_uncertainty",
    legacy_filename_compatibility = "RK_uncertainty_STD_*.tif",
    total_predictive_uncertainty_available = FALSE,
    calibrated = FALSE, prediction_interval_claim_allowed = FALSE,
    prediction_interval_type = "not_available_from_residual_kriging_sd",
    coverage_95_semantics =
      "residual_variance_diagnostic_only_not_prediction_interval_validation",
    used_in_grade = FALSE,
    min_sd = min(x), mean_sd = mean(x), max_sd = max(x),
    min_variance = min(x^2), mean_variance = mean(x^2),
    max_variance = max(x^2),
    high_uncertainty_threshold = NA_real_,
    high_uncertainty_area_percent = NA_real_,
    threshold_source = "not_defined",
    calibration_basis = "residual_kriging_only",
    calibration_gate_missing_fields =
      c("method", "source", "validation_design"),
    messages = paste0(
      "Có residual kriging SD nhưng chưa có total predictive calibration; ",
      "không được gọi là prediction interval."
    ),
    warnings = character(0)
  )
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
    if (isTRUE(result$singular)) return(0)
    ratio <- result$nugget_sill_ratio %||% NA_real_
    s <- ifelse(!is.finite(ratio), 45,
      ifelse(ratio <= 0.5, 85, ifelse(ratio <= 0.75, 65, 35)))
    if (isTRUE(result$range_hit_max)) s <- min(s, 45)
    return(max(0, s))
  }
  if (kind == "cross_validation") {
    nrmse <- result$metrics$NRMSE_mean %||% NA_real_
    thr <- profile$nrmse_mean_thresholds %||%
      list(excellent = 0.15, good = 0.25, acceptable = 0.40)
    if (!is.finite(nrmse)) return(35)
    s <- ifelse(nrmse <= thr$excellent, 95,
      ifelse(nrmse <= thr$good, 80,
        ifelse(nrmse <= thr$acceptable, 65, 35)))
    if (!isTRUE(result$strict_outer_cv)) s <- min(s, 55)
    return(s)
  }
  if (kind == "uncertainty") {
    if (!isTRUE(result$calibrated)) return(NA_real_)
    coverage <- suppressWarnings(as.numeric(result$coverage_95 %||% NA_real_))
    if (!is.finite(coverage)) return(NA_real_)
    return(ifelse(coverage >= 0.90 && coverage <= 0.98, 85, 45))
  }
  if (kind == "class_evaluation") {
    if (!isTRUE(result$enabled) || !isTRUE(result$approved)) return(NA_real_)
    acc <- result$class_accuracy %||% NA_real_
    if (!is.finite(acc)) return(45)
    return(ifelse(acc >= 0.70, 90, ifelse(acc >= 0.50, 70, 40)))
  }
  NA_real_
}

rk_eval_grade <- function(result, profile) {
  w <- profile$scoring_weights %||%
    rk_eval_default_profiles()$generic_continuous$scoring_weights
  comp <- list(
    data_quality = rk_eval_component_score("data_quality", result$data_quality, profile),
    regression_trend = rk_eval_component_score("regression_trend", result$regression, profile),
    residual_variogram = rk_eval_component_score("residual_variogram", result$variogram, profile),
    cross_validation = rk_eval_component_score("cross_validation", result$cross_validation, profile),
    uncertainty = rk_eval_component_score("uncertainty", result$uncertainty, profile),
    class_evaluation = rk_eval_component_score("class_evaluation", result$class_evaluation, profile)
  )
  values <- unlist(comp[names(w)])
  weights <- unlist(w)
  usable <- is.finite(values) & is.finite(weights) & weights > 0
  score <- if (any(usable)) {
    sum(values[usable] * weights[usable]) / sum(weights[usable])
  } else 0
  cap <- 100
  if ((result$data_quality$n_valid %||% 999) < 30) cap <- min(cap, 69)
  if (!isTRUE(result$cross_validation$strict_outer_cv)) cap <- min(cap, 69)
  if (is.finite(result$cross_validation$metrics$R2_pred) &&
      result$cross_validation$metrics$R2_pred <= 0) cap <- min(cap, 69)
  if (identical(result$cross_validation$method %||% "", "in_sample_fallback")) {
    cap <- min(cap, 49)
  }
  if (isTRUE(result$variogram$singular)) cap <- min(cap, 49)
  if (isTRUE(result$variogram$range_hit_max)) cap <- min(cap, 69)
  if (length(result$hard_failures %||% character(0)) > 0) cap <- min(cap, 69)
  if (any(grepl("không cải thiện|khong cai thien",
      result$cross_validation$warnings, ignore.case = TRUE))) {
    cap <- min(cap, 84)
  }
  if (isTRUE(result$class_evaluation$enabled) &&
      is.finite(result$class_evaluation$class_accuracy) &&
      result$class_evaluation$class_accuracy < 0.50 &&
      identical(profile$evaluation_focus, "class_accuracy")) {
    cap <- min(cap, 69)
  }
  score <- min(score, cap)
  grade <- ifelse(score >= 85, "A",
    ifelse(score >= 70, "B", ifelse(score >= 50, "C", "D")))
  list(
    final_score = round(score, 1), final_grade = grade,
    grade_label = paste0("Internal QA grade ", grade,
      " under current project rules"),
    external_validation_status = "not_externally_validated",
    publication_grade = FALSE, score_cap = cap,
    component_scores = comp
  )
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
  paste0(
    result$quality$grade_label, " (", result$quality$final_score, "/100). ",
    "Đây là xếp hạng QA nội bộ, chưa phải chứng nhận publication-grade. ",
    "Trạng thái sản phẩm: ", result$product_status,
    "; decision_use: ", result$decision_use, ". ",
    "Outer held-out spatial CV RK RMSE = ",
    " ", result$unit, ", ME = ",
    rk_eval_fmt(result$cross_validation$metrics$ME),
    ", R2_pred = ", rk_eval_fmt(result$cross_validation$metrics$R2_pred), ". ",
    "Variogram phần dư: ", result$variogram$model,
    ", range = ", rk_eval_fmt(result$variogram$range),
    " m, nugget/sill = ",
    rk_eval_fmt(result$variogram$nugget_sill_ratio), ". ",
    ifelse(length(result$hard_failures) > 0,
      "Có điều kiện chặn tự động ACCEPT; cần xử lý hoặc chuyên gia xem thủ công.",
      ifelse(length(result$warnings) > 0,
        "Cần xem cảnh báo trước khi dùng bản đồ.",
        "Không có cảnh báo theo các rule hiện tại."))
  )
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
  item_html <- function(x, cls, empty_text) {
    if (length(x) == 0) return(paste0("<p>", empty_text, "</p>"))
    paste0("<div class='", cls, "'>", rk_eval_html_escape(x), "</div>", collapse = "\n")
  }
  messages_html <- item_html(result$messages, "msg", "Không có thông báo bổ sung.")
  warnings_html <- item_html(result$warnings, "warn", "Không có cảnh báo.")
  failures_html <- item_html(
    result$hard_failures, "fail", "Không có điều kiện hard-fail.")
  rec_html <- paste0("<li>", rk_eval_html_escape(result$recommendations),
    "</li>", collapse = "\n")
  cls_rows <- if (isTRUE(result$class_evaluation$enabled)) {
    rk_eval_rows(list(
      approved = result$class_evaluation$approved,
      gate_passed = result$class_evaluation$gate_passed,
      source = result$class_evaluation$source,
      method = result$class_evaluation$method,
      unit = result$class_evaluation$unit,
      crop = result$class_evaluation$crop,
      region = result$class_evaluation$region,
      class_accuracy = result$class_evaluation$class_accuracy,
      within_one_class_rate = result$class_evaluation$within_one_class_rate,
      severe_misclassification_rate =
        result$class_evaluation$severe_misclassification_rate
    ))
  } else {
    paste0("<tr><td colspan='2'>",
      rk_eval_html_escape(result$class_evaluation$messages %||%
        "Không chấm phân cấp vì profile chưa được phê duyệt cho bối cảnh này."),
      "</td></tr>")
  }
  cv_meta <- result$cross_validation[c(
    "method", "validation_design", "validation_task",
    "validation_independence", "independent_field_validation",
    "strict_outer_cv", "outer_method", "outer_folds", "outer_repeats",
    "inner_method", "inner_folds", "leakage_guard"
  )]
  links <- result$report_links %||% list()
  link_html <- paste(vapply(names(links), function(nm) {
    href <- links[[nm]]
    if (is.null(href) || is.na(href) || href == "") return("")
    paste0("<li><a href='", rk_eval_html_escape(href), "'>",
      rk_eval_html_escape(nm), "</a></li>")
  }, character(1)), collapse = "\n")
  if (nchar(link_html) == 0) link_html <- "<li>Không có liên kết phụ trợ.</li>"

  html <- c(
    "<!doctype html><html lang='vi'><head><meta charset='utf-8'><title>RK evaluation</title>",
    "<style>body{font-family:Arial,sans-serif;margin:24px;color:#222;line-height:1.45}section{margin:22px 0}.grade{display:inline-block;padding:10px 16px;border-radius:6px;background:#222;color:white;font-weight:bold}table{border-collapse:collapse;max-width:1100px;width:100%;margin-top:8px}th,td{border:1px solid #ddd;padding:7px;text-align:left}th{background:#f3f3f3}.warn{background:#fff7df;border-left:4px solid #d9822b;padding:9px;margin:8px 0}.fail{background:#fdecec;border-left:4px solid #b42318;padding:9px;margin:8px 0}.msg{background:#eef6ff;border-left:4px solid #2878b5;padding:9px;margin:8px 0}.grid{display:grid;grid-template-columns:1fr 1fr;gap:18px}@media(max-width:800px){.grid{grid-template-columns:1fr}}</style></head><body>",
    paste0("<h1>Đánh giá Regression Kriging - ",
      rk_eval_html_escape(result$display_name), "</h1>"),
    paste0("<div class='grade'>", rk_eval_html_escape(result$quality$grade_label),
      " - ", result$quality$final_score, "/100</div>"),
    "<p><b>Lưu ý:</b> Grade là QA nội bộ. Outer held-out spatial CV không phải independent field validation.</p>",
    paste0("<p><b>Kết luận:</b> ", rk_eval_html_escape(result$summary), "</p>"),
    "<section><h2>1. File chính</h2><ul>", link_html, "</ul></section>",
    "<section><h2>2. Tổng quan</h2><table>",
    rk_eval_rows(list(
      target = result$target_field, unit = result$unit,
      profile = result$profile_name,
      prediction_method = result$prediction_method,
      product_status = result$product_status,
      product_semantics = result$product_semantics,
      decision_use = result$decision_use,
      profile_ambiguous = result$profile_ambiguous,
      n_valid = result$data_quality$n_valid,
      transform_used = result$target_transform$used %||% "none",
      transform_bias_correction_requested =
        result$target_transform$log_backtransform_bias_correction_requested %||%
          FALSE,
      transform_bias_correction_applied =
        result$target_transform$log_backtransform_bias_correction %||% FALSE,
      bias_correction_basis =
        result$target_transform$bias_correction_basis %||% "not_applied",
      metric_scale = result$target_transform$metric_scale %||% "original units",
      variogram_model = result$variogram$model,
      variogram_singular = result$variogram$singular,
      range_m = result$variogram$range,
      nugget_sill = result$variogram$nugget_sill_ratio,
      anisotropy_ratio = result$variogram$anisotropy_ratio,
      outer_RK_RMSE = result$cross_validation$metrics$RMSE,
      outer_RK_MAE = result$cross_validation$metrics$MAE,
      outer_RK_ME = result$cross_validation$metrics$ME,
      outer_RK_R2_pred = result$cross_validation$metrics$R2_pred
    )),
    "</table></section>",
    "<div class='grid'><section><h2>3. Dữ liệu đầu vào</h2><table>",
    rk_eval_rows(result$data_quality[setdiff(names(result$data_quality), "warnings")]),
    "</table></section><section><h2>4. Regression trend</h2><table>",
    rk_eval_rows(result$regression$metrics), "</table></section></div>",
    "<div class='grid'><section><h2>5. Residual variogram</h2><table>",
    rk_eval_rows(result$variogram[
      setdiff(names(result$variogram), c("messages", "warnings", "hard_failures"))]),
    "</table></section><section><h2>6. Outer held-out spatial CV (internal)</h2><table>",
    rk_eval_rows(c(cv_meta, result$cross_validation$metrics)),
    "</table></section></div>",
    "<div class='grid'><section><h2>7. Phân cấp nông học</h2><table>",
    cls_rows, "</table></section><section><h2>8. Residual kriging SD (partial)</h2>",
    "<p>File RK_uncertainty_STD được giữ để tương thích; đây không phải total predictive uncertainty hay prediction interval.</p><table>",
    rk_eval_rows(result$uncertainty[
      setdiff(names(result$uncertainty), c("messages", "warnings"))]),
    "</table></section></div>",
    "<div class='grid'><section><h2>9. AOA phụ thuộc mô hình/covariate</h2><table>",
    rk_eval_rows(result$extrapolation), "</table></section>",
    "<section><h2>10. Clamp và clipping</h2><table>",
    rk_eval_rows(result$clipping), "</table></section></div>",
    "<div class='grid'><section><h2>11. Vai trò điểm và ROI</h2><table>",
    rk_eval_rows(result$point_support), "</table></section>",
    "<section><h2>12. Ngữ nghĩa sản phẩm</h2><table>",
    rk_eval_rows(result$product_governance[c(
      "product_type", "product_semantics", "product_status",
      "decision_use", "fertilizer_rate_product",
      "recommendation_language_allowed"
    )]), "</table></section></div>",
    "<section><h2>13. Thông báo</h2>", messages_html, "</section>",
    "<section><h2>14. Cảnh báo</h2>", warnings_html, "</section>",
    "<section><h2>15. Điều kiện chặn ACCEPT</h2>", failures_html, "</section>",
    "<section><h2>16. Hành động QA mô hình (không phải khuyến cáo phân bón)</h2><ul>", rec_html, "</ul></section>",
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
  if (grepl("outer spatial|singular|mơ hồ|mo ho|hard|AOA|clipping|pure nugget", txt, ignore.case = TRUE)) {
    rec <- c(rec, "Không tự động ACCEPT; xử lý hard-failure hoặc yêu cầu chuyên gia xem thủ công.")
  }
  if (length(rec) == 0) rec <- "Chỉ dùng bản đồ để tham khảo xu thế không gian và luôn đọc kèm outer CV, AOA, clipping và uncertainty limitations."
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
    target = result$target_field, display_name = result$display_name,
    unit = result$unit, profile = result$profile_name,
    prediction_method = result$prediction_method,
    product_status = result$product_status,
    product_semantics = result$product_semantics,
    decision_use = result$decision_use,
    profile_ambiguous = result$profile_ambiguous,
    transform_used = result$target_transform$used %||% "none",
    transform_bias_correction_requested =
      result$target_transform$log_backtransform_bias_correction_requested %||%
        FALSE,
    transform_bias_correction_applied =
      result$target_transform$log_backtransform_bias_correction %||% FALSE,
    bias_correction_basis =
      result$target_transform$bias_correction_basis %||% "not_applied",
    metric_scale = result$target_transform$metric_scale %||% "original units",
    ok_baseline_scale =
      result$target_transform$ok_baseline_scale %||% "original units",
    final_score = result$quality$final_score,
    final_grade = result$quality$final_grade,
    grade_label = result$quality$grade_label,
    publication_grade = result$quality$publication_grade,
    n_valid = result$data_quality$n_valid,
    cv_method = result$cross_validation$method,
    strict_outer_cv = result$cross_validation$strict_outer_cv,
    outer_repeats = result$cross_validation$outer_repeats,
    validation_design = result$cross_validation$validation_design,
    validation_task = result$cross_validation$validation_task,
    independent_field_validation =
      isTRUE(result$cross_validation$independent_field_validation),
    rk_rmse = result$cross_validation$metrics$RMSE,
    rk_mae = result$cross_validation$metrics$MAE,
    rk_me = result$cross_validation$metrics$ME,
    rk_r2_pred = result$cross_validation$metrics$R2_pred,
    n_interval = result$cross_validation$metrics$n_interval %||% NA_integer_,
    interval_fraction =
      result$cross_validation$metrics$interval_fraction %||% NA_real_,
    coverage_95 = result$cross_validation$metrics$coverage_95 %||% NA_real_,
    coverage_95_semantics =
      result$uncertainty$coverage_95_semantics %||% "not_available",
    variance_standardized_RMSE =
      result$cross_validation$metrics$variance_standardized_RMSE %||% NA_real_,
    nrmse_mean = result$cross_validation$metrics$NRMSE_mean,
    rpd = result$cross_validation$metrics$RPD,
    rpiq = result$cross_validation$metrics$RPIQ,
    variogram_model = result$variogram$model,
    variogram_range = result$variogram$range,
    variogram_singular = result$variogram$singular,
    nugget_sill_ratio = result$variogram$nugget_sill_ratio,
    anisotropy_ratio = result$variogram$anisotropy_ratio,
    class_accuracy = ifelse(isTRUE(result$class_evaluation$enabled),
      result$class_evaluation$class_accuracy, NA_real_),
    classification_gate_passed =
      isTRUE(result$class_evaluation$gate_passed),
    uncertainty_type = result$uncertainty$uncertainty_type %||%
      "residual_kriging_standard_deviation",
    prediction_interval_claim_allowed =
      isTRUE(result$uncertainty$prediction_interval_claim_allowed),
    uncertainty_calibrated = isTRUE(result$uncertainty$calibrated),
    clipped_area_percent =
      result$clipping$total_clipped_percent %||% NA_real_,
    outside_aoa_percent =
      result$extrapolation$outside_aoa_percent %||% NA_real_,
    n_model_points_outside_roi =
      result$point_support$n_outside_roi_model %||% NA_integer_,
    outside_roi_points_are_validation =
      isTRUE(result$point_support$outside_roi_points_are_validation),
    point_support_role =
      result$point_support$model_point_role %||% "model_development",
    n_messages = length(result$messages),
    n_warnings = length(result$warnings),
    n_hard_failures = length(result$hard_failures),
    summary = result$summary, stringsAsFactors = FALSE
  )
}

run_rk_quality_evaluation <- function(context) {
  profiles <- load_evaluation_profiles(
    context$config_path %||% "_UNG_DUNG/engine/config/evaluation_profiles.R")
  profile <- match_indicator_profile(context$target_field, profiles)
  target_metadata <- context$target_metadata %||% list()
  profile_override <- target_metadata$profile_name %||% NULL
  metadata_confirmed <- isTRUE(target_metadata$confirmed)
  if (rk_eval_has_metadata_value(profile_override) &&
      as.character(profile_override[1]) %in% names(profiles)) {
    profile_override <- as.character(profile_override[1])
    profile <- profiles[[profile_override]]
    profile$profile_name <- profile_override
    profile$profile_matched <- TRUE
    profile$profile_ambiguous <- FALSE
    profile$manual_review_required <- FALSE
  }
  classification_metadata <- target_metadata$classification %||% list()
  if (length(classification_metadata) > 0 && !is.null(profile$class_bins)) {
    profile$class_bins$approved <- metadata_confirmed &&
      isTRUE(classification_metadata$approved)
    for (nm in c("source", "version", "approved_by")) {
      if (!is.null(classification_metadata[[nm]])) {
        profile$class_bins[[nm]] <- classification_metadata[[nm]]
      }
    }
    for (nm in c("laboratory_method", "unit", "crop", "region")) {
      if (!is.null(target_metadata[[nm]])) {
        target_name <- if (nm == "laboratory_method") "method" else nm
        profile$class_bins[[target_name]] <- target_metadata[[nm]]
      }
    }
  }
  warnings <- context$warnings %||% character(0)
  messages <- context$messages %||% character(0)
  hard_failures <- context$hard_failures %||% character(0)

  if (!isTRUE(profile$profile_matched)) {
    if (isTRUE(profile$profile_ambiguous)) {
      hard_failures <- c(hard_failures, paste0(
        "Tên chỉ tiêu mơ hồ: ", profile$ambiguity_reason,
        " Cần canonical name và metadata phương pháp/đơn vị."))
    } else {
      warnings <- c(warnings,
        "Chưa có Evaluation Profile riêng; đang dùng profile tổng quát.")
    }
  }

  dq <- rk_eval_data_quality(context$observed, context$coordinates, profile)
  tr <- rk_eval_transform_recommendation(context$observed, profile)
  reg <- rk_eval_regression(
    context$observed, context$regression_predicted, context$residuals)
  vg <- rk_eval_variogram(
    context$variogram_params, context$experimental_variogram,
    context$coordinates, profile, context$range_max %||% NA_real_)

  metric_row <- NULL
  if (is.data.frame(context$cv_summary) && nrow(context$cv_summary) > 0) {
    metric_row <- context$cv_summary[
      context$cv_summary$model == "Regression Kriging" &
        context$cv_summary$cv_method == (context$cv_method %||% ""), ,
      drop = FALSE
    ]
  }
  cv <- rk_eval_cross_validation(
    context$cv_observed, context$cv_rk_predicted, profile,
    context$cv_regression_predicted, context$cv_ok_predicted,
    context$cv_method %||% NA_character_,
    context$cv_folds %||% NA_integer_,
    context$cv_refit_variogram %||% NA,
    metadata = context$cv_metadata %||% list(),
    stability = context$cv_stability %||% list(),
    metric_row = metric_row
  )
  cls <- rk_eval_class_prediction(
    context$cv_observed, context$cv_rk_predicted, profile)
  unc <- rk_eval_uncertainty(
    context$prediction_sd_values, context$prediction_sd_summary %||% NULL)
  product <- rk_eval_product_semantics(
    target_metadata, profile, cls, context$point_support %||% list())
  resolved_unit <- if (rk_eval_has_metadata_value(target_metadata$unit)) {
    as.character(target_metadata$unit[1])
  } else {
    profile$unit %||% ""
  }
  classification_gate_failure <- if (
      isTRUE(classification_metadata$approved) &&
      !isTRUE(cls$gate_passed)) {
    "Đã chặn classification.approved vì metadata chưa confirmed hoặc thiếu source/unit/laboratory_method/crop/region."
  } else character(0)

  all_messages <- unique(c(
    messages, tr$reason, reg$messages, vg$messages, cv$messages,
    cls$messages, unc$messages, product$messages
  ))
  overfit_gap <- suppressWarnings(
    reg$metrics$R2_pred - cv$metrics$R2_pred)
  overfit_warnings <- if (is.finite(overfit_gap) && overfit_gap > 0.20) {
    paste0(
      "Khoảng cách R² in-sample và outer-CV = ",
      round(overfit_gap, 3),
      "; trend model có dấu hiệu overfitting."
    )
  } else {
    character(0)
  }
  all_warnings <- unique(c(
    warnings, dq$warnings, reg$warnings, overfit_warnings,
    vg$warnings, cv$warnings, cls$warnings, unc$warnings
  ))
  all_hard_failures <- unique(c(
    hard_failures, vg$hard_failures, cv$hard_failures,
    product$hard_failures, classification_gate_failure
  ))
  all_messages <- all_messages[nzchar(all_messages)]
  all_warnings <- all_warnings[nzchar(all_warnings)]
  all_hard_failures <- all_hard_failures[nzchar(all_hard_failures)]

  result <- list(
    target_field = context$target_field,
    prediction_method =
      context$prediction_method %||% "regression_kriging",
    display_name = profile$display_name %||% context$target_field,
    unit = resolved_unit,
    product_status = product$product_status,
    product_semantics = product$product_semantics,
    decision_use = product$decision_use,
    product_governance = product,
    profile_name = profile$profile_name,
    profile_matched = isTRUE(profile$profile_matched),
    profile_ambiguous = isTRUE(profile$profile_ambiguous),
    profile_ambiguity_reason = profile$ambiguity_reason %||% NULL,
    target_transform = context$target_transform %||% list(
      requested = "auto", used = "none", profile = profile$profile_name,
      reason = "", requires_nonnegative = FALSE,
      log_backtransform_bias_correction_requested = FALSE,
      log_backtransform_bias_correction = FALSE,
      bias_correction_basis = "not_applied",
      metric_scale = "original units", ok_baseline_scale = "original units"
    ),
    transform_recommendation = tr, data_quality = dq, regression = reg,
    variogram = vg, cross_validation = cv, class_evaluation = cls,
    uncertainty = unc, extrapolation = context$extrapolation %||% list(),
    point_support = context$point_support %||% list(),
    recommendations_semantics = "model_QA_actions_not_fertilizer_recommendations",
    clipping = context$clipping %||% list(),
    messages = all_messages, warnings = all_warnings,
    hard_failures = all_hard_failures,
    recommendations = rk_eval_recommendations(
      c(all_warnings, all_hard_failures)),
    report_links = context$report_links %||% list()
  )
  result$quality <- rk_eval_grade(result, profile)
  result$summary <- rk_eval_interpretation(result, profile)

  out_dir <- context$output_dir
  target <- context$target_name
  write.csv(
    rk_eval_summary_table(result),
    file.path(out_dir, paste0("summary_", target, ".csv")),
    row.names = FALSE, fileEncoding = "UTF-8"
  )
  write.csv(
    rk_eval_model_comparison(context$cv_summary),
    file.path(out_dir, "tables",
      paste0("model_comparison_", target, ".csv")),
    row.names = FALSE, fileEncoding = "UTF-8"
  )
  write.csv(
    rk_eval_cv_detail(context, cls),
    file.path(out_dir, "tables", paste0("cv_results_", target, ".csv")),
    row.names = FALSE, fileEncoding = "UTF-8"
  )
  if (isTRUE(cls$enabled)) {
    write.csv(
      data.frame(
        metric = c("class_accuracy", "within_one_class_rate",
          "severe_misclassification_rate"),
        value = c(cls$class_accuracy, cls$within_one_class_rate,
          cls$severe_misclassification_rate)
      ),
      file.path(out_dir, "tables",
        paste0("class_evaluation_", target, ".csv")),
      row.names = FALSE, fileEncoding = "UTF-8"
    )
    write.csv(
      as.data.frame(cls$confusion_matrix),
      file.path(out_dir, "tables",
        paste0("confusion_matrix_", target, ".csv")),
      row.names = FALSE, fileEncoding = "UTF-8"
    )
  }
  rk_eval_write_json(
    result, file.path(out_dir, "json",
      paste0("evaluation_", target, ".json")))
  rk_eval_write_json(
    vg, file.path(out_dir, "json",
      paste0("variogram_diagnostics_", target, ".json")))
  rk_eval_write_html(
    result, file.path(out_dir, paste0("index_", target, ".html")))
  result
}

rk_eval_self_test <- function() {
  profiles <- rk_eval_default_profiles()
  ph <- profiles$pH_H2O
  vals <- c(4.2, 5.0, 6.0, 7.0, 8.0, 9.0)
  expected <- c("Rất chua", "Chua", "Chua nhẹ", "Trung tính", "Kiềm nhẹ", "Kiềm mạnh")
  got <- vapply(vals, assign_value_class, character(1), bins = ph$class_bins$bins)
  stopifnot(identical(got, expected))
  m <- rk_eval_metrics(c(1, 2, 3), c(1, 2, 4))
  stopifnot(is.finite(m$RMSE), is.finite(m$MAE), is.finite(m$ME), is.finite(m$R2_pred))
  stopifnot(identical(
    match_indicator_profile("OM_pct", profiles)$profile_name, "OM_pct"))
  stopifnot(isTRUE(
    match_indicator_profile("OM", profiles)$profile_ambiguous))
  stopifnot(identical(match_indicator_profile("UnknownX", profiles)$profile_name, "generic_continuous"))
  TRUE
}
