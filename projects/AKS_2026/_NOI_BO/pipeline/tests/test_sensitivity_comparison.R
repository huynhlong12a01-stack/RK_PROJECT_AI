suppressPackageStartupMessages(library(jsonlite))
source("projects/AKS_2026/_NOI_BO/pipeline/sensitivity_comparison_utils.R")

make_evaluation <- function(path, n, rmse, mae, me, r2, aoa, clipped,
    score, failures = character()) {
  jsonlite::write_json(list(
    target_field = "P_Olsen",
    product_status = "SCIENTIFIC_QA",
    prediction_method = "regression_kriging",
    point_support = list(n_model_points = n),
    cross_validation = list(metrics = list(
      n = n, RMSE = rmse, MAE = mae, ME = me, R2_pred = r2)),
    extrapolation = list(outside_aoa_percent = aoa),
    clipping = list(total_clipped_percent = clipped),
    quality = list(final_grade = "B", final_score = score),
    hard_failures = failures
  ), path, auto_unbox = TRUE, pretty = TRUE)
}

primary_file <- tempfile(fileext = ".json")
inside_file <- tempfile(fileext = ".json")
make_evaluation(primary_file, 94, 1.0, 0.8, 0.1, 0.50, 8, 3, 82)
make_evaluation(
  inside_file, 72, 1.2, 0.9, -0.05, 0.40, 12, 5, 75,
  failures = "synthetic warning gate")

primary <- sensitivity_read_evaluation(
  primary_file, "PRIMARY", "PC_ONLY")
inside <- sensitivity_read_evaluation(
  inside_file, "INSIDE_ROI_ONLY", "PC_ONLY")
comparison <- sensitivity_compare_to_primary(rbind(primary, inside))
row <- comparison[comparison$scenario_id == "INSIDE_ROI_ONLY", ]

stopifnot(nrow(row) == 1L)
stopifnot(abs(row$delta_n_model_points + 22) < 1e-12)
stopifnot(abs(row$delta_cv_RMSE - 0.2) < 1e-12)
stopifnot(abs(row$delta_cv_R2_pred + 0.1) < 1e-12)
stopifnot(abs(row$delta_outside_aoa_percent - 4) < 1e-12)
stopifnot(row$delta_n_hard_failures == 1)
stopifnot(row$comparison_role ==
  "outside_sample_sensitivity_not_validation")
stopifnot(!row$automatic_model_choice)

unlink(c(primary_file, inside_file))
cat("sensitivity comparison tests passed\n")
