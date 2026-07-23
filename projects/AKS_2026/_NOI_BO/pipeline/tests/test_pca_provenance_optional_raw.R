expressions <- parse(
  "projects/AKS_2026/_NOI_BO/pipeline/verify_current_pca_provenance.R"
)
is_resolver <- vapply(
  expressions,
  function(expr) {
    is.call(expr) && identical(expr[[1]], as.name("<-")) &&
      identical(expr[[2]], as.name("resolve_expected_pca"))
  },
  logical(1)
)
stopifnot(sum(is_resolver) == 1L)
eval(expressions[[which(is_resolver)]], envir = .GlobalEnv)

ref <- list(
  scaler_mean = rep(0, 5),
  scaler_scale = rep(1, 5),
  pca_components = diag(5)
)
design_complete <- matrix(seq_len(10), nrow = 2, byrow = TRUE)
raw_calls <- 0L
complete_result <- resolve_expected_pca(
  design_complete, 2L, 5L, ref,
  raw_loader = function() {
    raw_calls <<- raw_calls + 1L
    stop("Raw loader must not run when workflow-1 PC support is complete")
  }
)
stopifnot(raw_calls == 0L)
stopifnot(!complete_result$raw_loaded)
stopifnot(all(complete_result$design_complete))
stopifnot(!any(complete_result$use_raw))
stopifnot(isTRUE(all.equal(complete_result$expected, design_complete)))

partial_design <- design_complete
partial_design[2, ] <- NA_real_
raw <- matrix(seq(0.1, 1.0, length.out = 10), nrow = 2, byrow = TRUE)
fallback_result <- resolve_expected_pca(
  partial_design, 2L, 5L, ref,
  raw_loader = function() {
    raw_calls <<- raw_calls + 1L
    raw
  }
)
stopifnot(raw_calls == 1L)
stopifnot(fallback_result$raw_loaded, fallback_result$raw_available)
stopifnot(identical(fallback_result$use_raw, c(FALSE, TRUE)))
stopifnot(isTRUE(all.equal(fallback_result$expected[1, ], partial_design[1, ])))
stopifnot(isTRUE(all.equal(fallback_result$expected[2, ], raw[2, ])))
cat("PCA provenance test passed: raw rasters are lazy and only required for PC gaps.\n")
