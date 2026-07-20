`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

sensitivity_scalar <- function(x, default = NA) {
  if (is.null(x) || !length(x)) return(default)
  x[[1]]
}

sensitivity_number <- function(x) {
  value <- suppressWarnings(as.numeric(sensitivity_scalar(x, NA_real_)))
  if (length(value) != 1L || !is.finite(value)) NA_real_ else value
}

sensitivity_read_evaluation <- function(path, scenario_id, model_branch) {
  evaluation <- jsonlite::read_json(path, simplifyVector = TRUE)
  metrics <- evaluation$cross_validation$metrics %||% list()
  quality <- evaluation$quality %||% list()
  point_support <- evaluation$point_support %||% list()
  extrapolation <- evaluation$extrapolation %||% list()
  clipping <- evaluation$clipping %||% list()
  data.frame(
    scenario_id = as.character(scenario_id),
    model_branch = as.character(model_branch),
    target = as.character(sensitivity_scalar(
      evaluation$target_field, basename(path))),
    product_status = as.character(sensitivity_scalar(
      evaluation$product_status, NA_character_)),
    prediction_method = as.character(sensitivity_scalar(
      evaluation$prediction_method, NA_character_)),
    n_model_points = sensitivity_number(point_support$n_model_points),
    cv_n = sensitivity_number(metrics$n),
    cv_RMSE = sensitivity_number(metrics$RMSE),
    cv_MAE = sensitivity_number(metrics$MAE),
    cv_ME = sensitivity_number(metrics$ME),
    cv_R2_pred = sensitivity_number(metrics$R2_pred),
    outside_aoa_percent = sensitivity_number(
      extrapolation$outside_aoa_percent),
    clipped_area_percent = sensitivity_number(
      clipping$total_clipped_percent),
    final_grade = as.character(sensitivity_scalar(
      quality$final_grade, NA_character_)),
    final_score = sensitivity_number(quality$final_score),
    n_hard_failures = length(evaluation$hard_failures %||% character()),
    evaluation_json = normalizePath(path, winslash = "/", mustWork = FALSE),
    stringsAsFactors = FALSE
  )
}

sensitivity_compare_to_primary <- function(rows) {
  if (!is.data.frame(rows) || !nrow(rows)) return(rows)
  metric_names <- c(
    "n_model_points", "cv_n", "cv_RMSE", "cv_MAE", "cv_ME",
    "cv_R2_pred", "outside_aoa_percent", "clipped_area_percent",
    "final_score", "n_hard_failures"
  )
  for (name in metric_names) {
    rows[[paste0("primary_", name)]] <- NA_real_
    rows[[paste0("delta_", name)]] <- NA_real_
  }
  rows$comparison_role <- ifelse(
    rows$scenario_id == "PRIMARY",
    "primary_reference",
    "outside_sample_sensitivity_not_validation"
  )
  rows$automatic_model_choice <- FALSE

  for (i in seq_len(nrow(rows))) {
    if (rows$scenario_id[i] == "PRIMARY") next
    primary <- which(
      rows$scenario_id == "PRIMARY" &
        rows$model_branch == rows$model_branch[i] &
        rows$target == rows$target[i]
    )
    if (length(primary) != 1L) next
    for (name in metric_names) {
      primary_value <- suppressWarnings(as.numeric(rows[[name]][primary]))
      scenario_value <- suppressWarnings(as.numeric(rows[[name]][i]))
      rows[[paste0("primary_", name)]][i] <- primary_value
      if (is.finite(primary_value) && is.finite(scenario_value)) {
        rows[[paste0("delta_", name)]][i] <- scenario_value - primary_value
      }
    }
  }
  rows
}
