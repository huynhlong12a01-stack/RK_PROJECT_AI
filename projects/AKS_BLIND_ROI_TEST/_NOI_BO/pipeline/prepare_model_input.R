suppressPackageStartupMessages({
  library(readr)
  library(jsonlite)
  library(yaml)
})

base <- "projects/AKS_BLIND_ROI_TEST"
input_file <- file.path(base, "_NOI_BO/work/interpolation/sample_actual_clean.csv")
point_qa_file <- file.path(base, "_NOI_BO/work/interpolation/qa/sample_roi_status.csv")
metadata_file <- file.path(base, "02_NOI_SUY_BAN_DO/01_DAU_VAO/indicator_metadata.yml")
output_file <- file.path(base, "_NOI_BO/work/models/input/soil_points.csv")
sensitivity_dir <- file.path(base, "_NOI_BO/work/models/input/sensitivity")
qa_dir <- file.path(base, "_NOI_BO/work/models/qa")
qa_file <- file.path(qa_dir, "model_input_summary.json")
metadata_qa_csv <- file.path(qa_dir, "indicator_metadata_status.csv")
metadata_qa_json <- file.path(qa_dir, "indicator_metadata_status.json")
if (!file.exists(input_file)) stop("Run actual-sample preflight first.")
if (!file.exists(point_qa_file)) stop("Actual-sample point QA is required. Run preflight first.")

x <- as.data.frame(readr::read_csv(input_file, show_col_types = FALSE, progress = FALSE))
required <- c("code", "lat", "lon")
missing <- setdiff(required, names(x))
if (length(missing)) stop("Missing column(s): ", paste(missing, collapse = ", "))
indicators <- setdiff(names(x), required)
if (!length(indicators)) {
  stop("Add at least one analysis indicator column to 02_NOI_SUY_BAN_DO/01_DAU_VAO/sample_actual.csv.")
}

numeric_ok <- vapply(indicators, function(nm) {
  text <- trimws(as.character(x[[nm]]))
  blank <- is.na(x[[nm]]) | text == ""
  value <- suppressWarnings(as.numeric(text))
  all(blank | is.finite(value))
}, logical(1))
if (any(!numeric_ok)) stop("Non-numeric indicator column(s): ", paste(indicators[!numeric_ok], collapse = ", "))
for (nm in indicators) x[[nm]] <- suppressWarnings(as.numeric(x[[nm]]))
has_results <- vapply(x[indicators], function(v) any(is.finite(v)), logical(1))
filled <- indicators[has_results]

metadata <- if (file.exists(metadata_file)) yaml::read_yaml(metadata_file) else list()
targets <- metadata$targets
if (is.null(targets)) targets <- list()
has_metadata_value <- function(value) {
  if (is.null(value) || !length(value)) return(FALSE)
  text <- trimws(as.character(value[[1]]))
  !is.na(text) && nzchar(text) &&
    !tolower(text) %in% c(
      "na", "n/a", "none", "null", "unknown", "unspecified",
      "unvalidated", "not_defined", "not defined"
    )
}

metadata_rows <- lapply(seq_along(indicators), function(i) {
  nm <- indicators[[i]]
  entry <- targets[[nm]]
  entry_exists <- !is.null(entry)
  confirmed <- entry_exists && isTRUE(entry$confirmed)
  unit_value <- if (entry_exists && !is.null(entry$unit)) {
    as.character(entry$unit)
  } else NA_character_
  method_value <- if (entry_exists && !is.null(entry$laboratory_method)) {
    as.character(entry$laboratory_method)
  } else NA_character_
  mapping_metadata_complete <- confirmed &&
    has_metadata_value(unit_value) && has_metadata_value(method_value)
  mapping_missing <- c(
    if (!has_metadata_value(unit_value)) "unit" else character(0),
    if (!has_metadata_value(method_value)) "laboratory_method" else character(0)
  )
  base_status <- if (!has_results[[i]]) {
    "WAITING_LAB"
  } else if (!confirmed) {
    "DRAFT_UNCONFIRMED_METADATA"
  } else if (!mapping_metadata_complete) {
    "DRAFT_INCOMPLETE_TARGET_METADATA"
  } else {
    "READY_FOR_CONTINUOUS_MODEL"
  }
  reason <- if (!has_results[[i]]) {
    "no_numeric_result"
  } else if (!entry_exists) {
    "metadata_entry_missing"
  } else if (!confirmed) {
    "metadata_not_confirmed"
  } else if (!mapping_metadata_complete) {
    paste0("missing_", paste(mapping_missing, collapse = ";"))
  } else {
    "confirmed_mapping_metadata_complete"
  }
  data.frame(
    indicator = nm,
    has_results = has_results[[i]],
    metadata_entry_exists = entry_exists,
    metadata_confirmed = confirmed,
    mapping_metadata_complete = mapping_metadata_complete,
    mapping_metadata_missing_fields = paste(mapping_missing, collapse = ";"),
    profile_name = if (entry_exists && !is.null(entry$profile_name)) as.character(entry$profile_name) else NA_character_,
    unit = unit_value,
    laboratory_method = method_value,
    extraction_ratio = if (entry_exists && !is.null(entry$extraction_ratio)) as.character(entry$extraction_ratio) else NA_character_,
    product_status = base_status,
    confirmation_status = reason,
    stringsAsFactors = FALSE
  )
})
metadata_status <- do.call(rbind, metadata_rows)

point_qa <- as.data.frame(readr::read_csv(point_qa_file, show_col_types = FALSE, progress = FALSE))
idx <- match(x$code, point_qa$code)
if (any(is.na(idx))) stop("Point QA is missing one or more sample codes.")
inside <- as.logical(point_qa$inside_roi[idx])
outside <- !inside
include_review <- as.logical(point_qa$include_in_model_development[idx])
target_reviewed <- point_qa$target_population_status[idx] %in% c("confirmed_in_scope", "confirmed_out_of_scope")
support_reviewed <- point_qa$sampling_support_status[idx] %in% c("confirmed_compatible", "confirmed_incompatible")
outside_review_pending <- outside & (is.na(include_review) | !target_reviewed | !support_reviewed)
explicitly_excluded <- outside & !is.na(include_review) & !include_review
primary_keep <- !explicitly_excluded
outside_review_status <- if (any(outside_review_pending)) "pending_manual_confirmation" else "complete"
if (any(outside_review_pending) && length(filled)) {
    eligible_for_outside_status <- metadata_status$has_results &
    metadata_status$product_status == "READY_FOR_CONTINUOUS_MODEL"
  metadata_status$product_status[eligible_for_outside_status] <-
    "DRAFT_PENDING_OUTSIDE_REVIEW"
}

dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
dir.create(sensitivity_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(qa_dir, recursive = TRUE, showWarnings = FALSE)
all_actual_file <- file.path(sensitivity_dir, "soil_points_all_actual_audit.csv")
readr::write_csv(x, all_actual_file, na = "")
readr::write_csv(x[primary_keep, , drop = FALSE], output_file, na = "")

scenario_rows <- list()
add_scenario <- function(id, file, keep, role, interpretation) {
  readr::write_csv(x[keep, , drop = FALSE], file, na = "")
  scenario_rows[[length(scenario_rows) + 1L]] <<- data.frame(
    scenario_id = id,
    scenario_role = role,
    point_file = normalizePath(file, winslash = "/", mustWork = FALSE),
    n_samples = sum(keep),
    status = if (length(filled)) "input_ready" else "pending_lab_results",
    interpretation = interpretation,
    stringsAsFactors = FALSE
  )
}
add_scenario(
  "REVIEW_FILTERED_PRIMARY", output_file, primary_keep, "primary",
  "inside-frame and pending outside samples retained; outside samples explicitly marked include=false are excluded"
)
add_scenario(
  "ALL_ACTUAL_AUDIT", all_actual_file, rep(TRUE, nrow(x)), "audit_sensitivity",
  "all observed coordinates retained for audit/sensitivity; not an independent validation set"
)
inside_file <- file.path(sensitivity_dir, "soil_points_inside_roi_only.csv")
add_scenario(
  "INSIDE_ROI_ONLY", inside_file, inside, "geographic_sensitivity",
  "geographic sensitivity only; outside samples are not a validation set"
)
reviewed_eligible <- outside &
  point_qa$target_population_status[idx] == "confirmed_in_scope" &
  point_qa$sampling_support_status[idx] == "confirmed_compatible" &
  !is.na(include_review) & include_review
eligible <- inside | reviewed_eligible
eligible_file <- file.path(sensitivity_dir, "soil_points_eligible_after_target_support_review.csv")
add_scenario(
  "ELIGIBLE_AFTER_TARGET_SUPPORT_REVIEW", eligible_file, eligible, "support_sensitivity",
  "inside-frame samples plus outside samples explicitly accepted after target-population and sampling-support review"
)
scenarios <- do.call(rbind, scenario_rows)
readr::write_csv(scenarios, file.path(qa_dir, "sensitivity_input_manifest.csv"), na = "")

readr::write_csv(metadata_status, metadata_qa_csv, na = "")
jsonlite::write_json(
  list(
    metadata_file = normalizePath(metadata_file, winslash = "/", mustWork = FALSE),
    metadata_file_status = if (file.exists(metadata_file)) "provided" else "missing",
    outside_review_status = outside_review_status,
    n_pending_outside_review = sum(outside_review_pending),
    targets = metadata_status,
    policy = "unconfirmed or outside-review-pending continuous models are DRAFT; no classification or fertilizer recommendation is created"
  ),
  metadata_qa_json, pretty = TRUE, auto_unbox = TRUE, dataframe = "rows", na = "null"
)

missing_filled_metadata <- metadata_status$indicator[
  metadata_status$has_results & !metadata_status$metadata_entry_exists
]
unconfirmed_filled <- metadata_status$indicator[
  metadata_status$has_results & !metadata_status$metadata_confirmed
]
product_status <- if (!length(filled)) {
  "WAITING_LAB"
} else if (any(outside_review_pending)) {
  "DRAFT_PENDING_OUTSIDE_REVIEW"
} else if (length(unconfirmed_filled)) {
  "DRAFT"
} else {
  "READY_FOR_CONTINUOUS_MODEL"
}
summary <- list(
  interpretation = "one average result row per sample",
  n_samples = nrow(x),
  n_samples_primary = sum(primary_keep),
  n_pending_outside_review = sum(outside_review_pending),
  n_explicitly_excluded_outside = sum(explicitly_excluded),
  outside_review_status = outside_review_status,
  indicator_columns = indicators,
  indicators_with_results = filled,
  metadata_entries_required_for_filled_indicators = TRUE,
  indicators_missing_metadata_entry = missing_filled_metadata,
  indicators_requiring_confirmation = unconfirmed_filled,
  product_status = product_status,
  classification_created = FALSE,
  fertilizer_recommendation_created = FALSE,
  aoa_status = "pending_model_fit_model_dependent",
  final_map_domain = "original_roi_only",
  output_file = normalizePath(output_file, winslash = "/", mustWork = FALSE),
  all_actual_audit_file = normalizePath(all_actual_file, winslash = "/", mustWork = FALSE),
  explicit_outside_include_false_excluded_from_primary = TRUE,
  pending_outside_retained_in_primary_as_draft = TRUE,
  indicator_metadata_status_csv = normalizePath(metadata_qa_csv, winslash = "/", mustWork = FALSE),
  sensitivity_scenarios = scenarios
)
jsonlite::write_json(summary, qa_file, pretty = TRUE, auto_unbox = TRUE, dataframe = "rows", na = "null")

if (length(missing_filled_metadata)) {
  stop(
    "Filled indicator(s) lack an indicator_metadata.yml entry: ",
    paste(missing_filled_metadata, collapse = ", "),
    ". QA files were written before stopping."
  )
}
if (!length(filled)) {
  cat(
    "WAITING_LAB: predictor, PCA, Soil Type, point QA and model-input hooks are ready; ",
    "no interpolation map was created. Add numeric lab results and run again.\n",
    sep = ""
  )
}
cat(
  "Model input prepared: ", output_file,
  "; product status: ", product_status,
  "; excluded outside by explicit review: ", sum(explicitly_excluded), "\n", sep = ""
)
