# Target-free covariate-support diagnostics for samples outside the original ROI.
#
# This module deliberately does not use a laboratory target. Its output is a
# pre-inclusion support diagnostic, not a final-model Area of Applicability
# (AOA), a validation set, or an automatic include/exclude decision.

outside_pc_matrix <- function(x, label = "PC matrix") {
  x <- as.matrix(x)
  storage.mode(x) <- "double"
  if (!nrow(x) || !ncol(x)) stop(label, " is empty.")
  if (is.null(colnames(x))) colnames(x) <- paste0("PC", seq_len(ncol(x)))
  if (any(!is.finite(x))) stop(label, " contains missing or non-finite values.")
  x
}

outside_standardization <- function(reference, tolerance = 1e-12) {
  reference <- outside_pc_matrix(reference, "Inside-frame reference")
  center <- colMeans(reference)
  scale <- apply(reference, 2, stats::sd)
  active <- is.finite(scale) & scale > tolerance
  if (!any(active)) {
    stop("Inside-frame reference has no variable PC dimension.")
  }
  list(
    center = center,
    scale = scale,
    active = active,
    active_predictors = colnames(reference)[active],
    inactive_predictors = colnames(reference)[!active]
  )
}

outside_apply_standardization <- function(x, standardization) {
  x <- outside_pc_matrix(x)
  active <- standardization$active
  if (length(active) != ncol(x)) {
    stop("PC column count differs from the inside-frame reference.")
  }
  z <- sweep(x[, active, drop = FALSE], 2,
    standardization$center[active], FUN = "-")
  sweep(z, 2, standardization$scale[active], FUN = "/")
}

outside_nearest_reference <- function(reference_z, candidate_z,
    reference_ids) {
  reference_z <- outside_pc_matrix(reference_z, "Standardized reference")
  candidate_z <- outside_pc_matrix(candidate_z, "Standardized candidates")
  if (ncol(reference_z) != ncol(candidate_z)) {
    stop("Reference and candidate matrices have different active dimensions.")
  }
  if (length(reference_ids) != nrow(reference_z)) {
    stop("reference_ids length does not match reference rows.")
  }
  distance <- numeric(nrow(candidate_z))
  nearest <- character(nrow(candidate_z))
  for (i in seq_len(nrow(candidate_z))) {
    delta <- sweep(reference_z, 2, candidate_z[i, ], FUN = "-")
    d <- sqrt(rowSums(delta^2))
    hit <- which.min(d)
    distance[i] <- d[hit]
    nearest[i] <- as.character(reference_ids[hit])
  }
  list(distance = distance, nearest_id = nearest)
}

outside_reference_loo_distance <- function(reference_z) {
  reference_z <- outside_pc_matrix(reference_z, "Standardized reference")
  if (nrow(reference_z) < 3L) {
    stop("At least three complete inside-frame samples are required.")
  }
  vapply(seq_len(nrow(reference_z)), function(i) {
    other <- reference_z[-i, , drop = FALSE]
    delta <- sweep(other, 2, reference_z[i, ], FUN = "-")
    min(sqrt(rowSums(delta^2)))
  }, numeric(1))
}

outside_covariate_diagnostic <- function(reference, candidates,
    reference_ids, candidate_ids, threshold_probability = 0.95) {
  reference <- outside_pc_matrix(reference, "Inside-frame reference")
  candidates <- outside_pc_matrix(candidates, "Outside candidates")
  if (!identical(colnames(reference), colnames(candidates))) {
    stop("Reference and candidate PC columns must be identical and ordered.")
  }
  if (length(reference_ids) != nrow(reference) ||
      length(candidate_ids) != nrow(candidates)) {
    stop("Sample identifier lengths do not match the PC matrices.")
  }
  if (!is.finite(threshold_probability) || threshold_probability <= 0 ||
      threshold_probability >= 1) {
    stop("threshold_probability must be strictly between zero and one.")
  }

  standardization <- outside_standardization(reference)
  reference_z <- outside_apply_standardization(reference, standardization)
  candidate_z <- outside_apply_standardization(candidates, standardization)
  loo <- outside_reference_loo_distance(reference_z)
  threshold_q <- as.numeric(stats::quantile(
    loo, probs = threshold_probability, names = FALSE, type = 8))
  threshold_max <- max(loo)
  nearest <- outside_nearest_reference(
    reference_z, candidate_z, reference_ids)

  reference_min <- apply(reference, 2, min)
  reference_max <- apply(reference, 2, max)
  range_flags <- vapply(seq_len(nrow(candidates)), function(i) {
    candidates[i, ] < reference_min | candidates[i, ] > reference_max
  }, logical(ncol(candidates)))
  if (is.null(dim(range_flags))) {
    range_flags <- matrix(range_flags, nrow = ncol(candidates), ncol = 1L)
  }
  range_flags <- t(range_flags)
  colnames(range_flags) <- colnames(candidates)
  range_count <- rowSums(range_flags)
  range_fields <- apply(range_flags, 1, function(flag) {
    paste(colnames(candidates)[flag], collapse = ";")
  })

  status <- ifelse(
    nearest$distance <= threshold_q & range_count == 0L,
    "similar_to_inside_reference",
    ifelse(
      nearest$distance <= threshold_max & range_count <= 1L,
      "edge_of_inside_reference_requires_review",
      "dissimilar_to_inside_reference_requires_review"
    )
  )

  result <- data.frame(
    code = as.character(candidate_ids),
    nearest_inside_code = nearest$nearest_id,
    standardized_nn_distance = nearest$distance,
    inside_loo_q95_threshold = threshold_q,
    inside_loo_max_threshold = threshold_max,
    pc_range_exceed_count = as.integer(range_count),
    pc_range_exceed_fields = range_fields,
    empirical_support_status = status,
    recommended_action = ifelse(
      status == "similar_to_inside_reference",
      "continue_manual_target_population_and_sampling_support_review",
      "manual_review_and_inside_only_sensitivity_comparison_required"
    ),
    diagnostic_role = "pre_inclusion_covariate_support_diagnostic",
    is_final_model_aoa = FALSE,
    is_independent_validation = FALSE,
    stringsAsFactors = FALSE
  )

  list(
    table = result,
    standardization = standardization,
    reference_loo_distance = loo,
    threshold_probability = threshold_probability,
    threshold_q = threshold_q,
    threshold_max = threshold_max
  )
}
