source(
  "projects/PHU_YEN_MOCK/_NOI_BO/pipeline/outside_covariate_dissimilarity_utils.R")

reference <- rbind(
  c(0.0, 0.0, 0.0, 0.0, 1.0),
  c(1.0, 0.0, 1.0, 0.0, 1.0),
  c(0.0, 1.0, 0.0, 1.0, 1.0),
  c(1.0, 1.0, 1.0, 1.0, 1.0),
  c(0.5, 0.5, 0.5, 0.5, 1.0),
  c(0.2, 0.8, 0.3, 0.7, 1.0)
)
colnames(reference) <- paste0("PC", 1:5)
candidates <- rbind(
  c(0.52, 0.48, 0.51, 0.49, 1.0),
  c(10.0, 10.0, 10.0, 10.0, 1.0)
)
colnames(candidates) <- colnames(reference)

result <- outside_covariate_diagnostic(
  reference, candidates,
  reference_ids = paste0("I", seq_len(nrow(reference))),
  candidate_ids = c("OUT_NEAR", "OUT_FAR")
)

stopifnot(nrow(result$table) == 2L)
stopifnot(result$table$code[1] == "OUT_NEAR")
stopifnot(result$table$empirical_support_status[1] ==
  "similar_to_inside_reference")
stopifnot(result$table$empirical_support_status[2] ==
  "dissimilar_to_inside_reference_requires_review")
stopifnot(result$table$standardized_nn_distance[2] >
  result$table$inside_loo_max_threshold[2])
stopifnot(result$table$pc_range_exceed_count[2] == 4L)
stopifnot(identical(result$standardization$inactive_predictors, "PC5"))
stopifnot(all(!result$table$is_final_model_aoa))
stopifnot(all(!result$table$is_independent_validation))
stopifnot(all(result$table$diagnostic_role ==
  "pre_inclusion_covariate_support_diagnostic"))

all_constant <- matrix(1, nrow = 4, ncol = 5,
  dimnames = list(NULL, paste0("PC", 1:5)))
constant_error <- try(outside_covariate_diagnostic(
  all_constant, all_constant[1, , drop = FALSE],
  reference_ids = paste0("C", 1:4), candidate_ids = "OUT"), silent = TRUE)
stopifnot(inherits(constant_error, "try-error"))

cat("outside covariate dissimilarity tests passed\n")
