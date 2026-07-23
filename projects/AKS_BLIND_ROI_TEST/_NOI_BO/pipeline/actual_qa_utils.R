actual_bool_value <- function(x, field) {
  text <- trimws(tolower(as.character(x)))
  text[is.na(text) | text == ""] <- NA_character_
  out <- rep(NA, length(text))
  out[text %in% c("true", "yes", "y", "1")] <- TRUE
  out[text %in% c("false", "no", "n", "0")] <- FALSE
  invalid <- !is.na(text) & !text %in% c("true", "yes", "y", "1", "false", "no", "n", "0")
  if (any(invalid)) stop("Unsupported boolean value in ", field, ": ", paste(unique(text[invalid]), collapse = ", "))
  out
}

actual_review_columns <- function() {
  c(
    "code", "planned_point_id", "target_population_in_scope",
    "sampling_support_compatible", "relocation_reason",
    "include_in_model_development", "reviewer", "review_date", "review_note"
  )
}

actual_sync_review_file <- function(path, outside_codes, default_relocation_reason = NA_character_) {
  columns <- actual_review_columns()
  if (file.exists(path)) {
    old <- as.data.frame(readr::read_csv(path, show_col_types = FALSE, progress = FALSE, col_types = readr::cols(.default = "c")))
    if (!"code" %in% names(old)) stop("outside_sample_review.csv must contain code.")
    old$code <- trimws(as.character(old$code))
    if (any(!nzchar(old$code)) || anyDuplicated(old$code)) stop("outside_sample_review.csv has blank or duplicate code values.")
    for (nm in setdiff(columns, names(old))) old[[nm]] <- NA_character_
    old <- old[, columns, drop = FALSE]
  } else {
    old <- as.data.frame(setNames(replicate(length(columns), character(0), simplify = FALSE), columns), stringsAsFactors = FALSE)
  }

  current <- as.data.frame(setNames(replicate(length(columns), rep(NA_character_, length(outside_codes)), simplify = FALSE), columns), stringsAsFactors = FALSE)
  current$code <- outside_codes
  idx <- match(outside_codes, old$code)
  hit <- !is.na(idx)
  for (nm in setdiff(columns, "code")) current[[nm]][hit] <- as.character(old[[nm]][idx[hit]])
  new_row <- !hit
  if (length(default_relocation_reason) && !is.na(default_relocation_reason) && nzchar(default_relocation_reason)) {
    current$relocation_reason[new_row] <- default_relocation_reason
  }
  # Rewriting is a key-based merge: existing answers are retained verbatim;
  # rows are only added/removed when geographic outside-ROI membership changes.
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(current, path, na = "")
  current
}

actual_read_assessment <- function(path, codes) {
  empty <- data.frame(
    code = codes,
    planned_point_id = NA_character_,
    relocation_reason = NA_character_,
    target_population_status = "pending_manual_confirmation",
    sampling_support_status = "pending_manual_confirmation",
    include_in_model_development = NA,
    reviewer = NA_character_,
    review_date = NA_character_,
    assessment_note = NA_character_,
    stringsAsFactors = FALSE
  )
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    attr(empty, "file_status") <- "not_provided"
    return(empty)
  }

  raw <- as.data.frame(readr::read_csv(path, show_col_types = FALSE, progress = FALSE, col_types = readr::cols(.default = "c")))
  if (!"code" %in% names(raw)) stop("outside_sample_review.csv must contain code.")
  raw$code <- trimws(as.character(raw$code))
  if (any(!nzchar(raw$code)) || anyDuplicated(raw$code)) stop("outside_sample_review.csv has blank or duplicate code values.")
  unknown <- setdiff(raw$code, codes)
  if (length(unknown)) stop("Review contains code(s) absent from sample_actual.csv: ", paste(unknown, collapse = ", "))

  idx <- match(codes, raw$code)
  hit <- !is.na(idx)
  copy_text <- function(source, target) {
    if (source %in% names(raw)) empty[[target]][hit] <<- as.character(raw[[source]][idx[hit]])
  }
  copy_text("planned_point_id", "planned_point_id")
  copy_text("relocation_reason", "relocation_reason")
  copy_text("reviewer", "reviewer")
  copy_text("review_date", "review_date")
  copy_text("review_note", "assessment_note")

  if ("target_population_in_scope" %in% names(raw)) {
    value <- actual_bool_value(raw$target_population_in_scope, "target_population_in_scope")
    mapped <- rep("pending_manual_confirmation", nrow(raw))
    mapped[!is.na(value) & value] <- "confirmed_in_scope"
    mapped[!is.na(value) & !value] <- "confirmed_out_of_scope"
    empty$target_population_status[hit] <- mapped[idx[hit]]
  }
  if ("sampling_support_compatible" %in% names(raw)) {
    value <- actual_bool_value(raw$sampling_support_compatible, "sampling_support_compatible")
    mapped <- rep("pending_manual_confirmation", nrow(raw))
    mapped[!is.na(value) & value] <- "confirmed_compatible"
    mapped[!is.na(value) & !value] <- "confirmed_incompatible"
    empty$sampling_support_status[hit] <- mapped[idx[hit]]
  }
  if ("include_in_model_development" %in% names(raw)) {
    value <- actual_bool_value(raw$include_in_model_development, "include_in_model_development")
    empty$include_in_model_development[hit] <- value[idx[hit]]
  }
  for (nm in c("planned_point_id", "relocation_reason", "reviewer", "review_date", "assessment_note")) {
    empty[[nm]] <- trimws(as.character(empty[[nm]]))
    empty[[nm]][is.na(empty[[nm]]) | empty[[nm]] == ""] <- NA_character_
  }
  attr(empty, "file_status") <- "provided"
  empty
}

actual_resolve_plan_link <- function(codes, assessment, planned_ids) {
  supplied <- assessment$planned_point_id
  exact_code <- codes %in% planned_ids
  candidate <- supplied
  candidate[is.na(candidate) & exact_code] <- codes[is.na(candidate) & exact_code]
  supplied_invalid <- !is.na(supplied) & !supplied %in% planned_ids
  linked <- !is.na(candidate) & candidate %in% planned_ids
  status <- rep("unavailable_no_identifier", length(codes))
  status[exact_code & is.na(supplied)] <- "matched_exact_code"
  status[linked & !is.na(supplied)] <- "matched_declared_planned_id"
  status[supplied_invalid] <- "invalid_declared_planned_id"
  candidate[!linked] <- NA_character_
  data.frame(planned_link_status = status, planned_point_id = candidate, stringsAsFactors = FALSE)
}
