# ============================================================
# Validate an AI decision JSON before creating the next RK run request.
# ============================================================

source("scripts/agent_utils.R")

agent_parse_args <- function(args) {
  out <- list()
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (startsWith(key, "--")) {
      nm <- sub("^--", "", key)
      val <- TRUE
      if (i + 1L <= length(args) && !startsWith(args[[i + 1L]], "--")) {
        val <- args[[i + 1L]]
        i <- i + 1L
      }
      out[[nm]] <- val
    }
    i <- i + 1L
  }
  out
}

args <- agent_parse_args(commandArgs(trailingOnly = TRUE))
decision_path <- args$decision %||% args$d %||% "agent/decisions/ai_decision_template.json"
request_path <- args$request %||% args$r %||% "agent/requests/run_request_template.json"
output_path <- args$output %||% args$o %||% "agent/decisions/validated_decision.json"

valid_decisions <- c("ACCEPT", "RERUN", "MANUAL_REVIEW", "REJECT")
valid_confidence <- c("low", "medium", "high")
accepted <- list()
rejected <- list()
warnings <- character(0)
manual_review <- FALSE

request <- agent_read_json(request_path)
decision <- agent_read_json(decision_path)
safety_limits <- agent_merge_lists(agent_default_safety_limits(), request$safety_limits %||% list())

dec <- decision$decision %||% NA_character_
conf <- decision$confidence %||% NA_character_
if (!(dec %in% valid_decisions)) {
  warnings <- c(warnings, "Invalid decision value.")
  manual_review <- TRUE
  dec <- "MANUAL_REVIEW"
}
if (!(conf %in% valid_confidence)) {
  warnings <- c(warnings, "Invalid confidence value.")
  manual_review <- TRUE
}

param_check <- agent_validate_parameter_list(decision$next_parameters %||% list(), safety_limits)
accepted <- param_check$accepted
rejected <- param_check$rejected
warnings <- unique(c(warnings, param_check$warnings))
if (length(rejected) > 0) manual_review <- TRUE

must_keep <- decision$must_keep %||% list()
if (length(must_keep) > 0) {
  protected_must_keep <- intersect(names(must_keep), agent_protected_parameters())
  for (nm in protected_must_keep) rejected[[nm]] <- "AI is not allowed to modify protected input, CRS, or source settings."
  if (length(protected_must_keep) > 0) manual_review <- TRUE
  if ("RUN_CROSS_VALIDATION" %in% names(must_keep) && !isTRUE(must_keep$RUN_CROSS_VALIDATION)) {
    rejected$RUN_CROSS_VALIDATION <- "AI is not allowed to disable cross-validation in agent workflow."
    manual_review <- TRUE
  }
  if ("CV_METHODS" %in% names(must_keep)) {
    cv_err <- agent_validate_parameter("CV_METHODS", must_keep$CV_METHODS, safety_limits)
    if (!is.null(cv_err)) {
      rejected$CV_METHODS <- cv_err
      manual_review <- TRUE
    } else {
      accepted$CV_METHODS <- must_keep$CV_METHODS
    }
  }
}

if (identical(dec, "RERUN") && length(accepted) == 0) {
  warnings <- c(warnings, "RERUN decision has no accepted next_parameters.")
  manual_review <- TRUE
}

valid <- !manual_review && length(rejected) == 0
out_decision <- if (manual_review) "MANUAL_REVIEW" else dec
next_action <- switch(out_decision,
  ACCEPT = "FINALIZE_CURRENT_RUN",
  RERUN = "CREATE_NEXT_RUN_REQUEST",
  MANUAL_REVIEW = "STOP_AND_REQUEST_HUMAN_REVIEW",
  REJECT = "STOP_AND_REJECT_RUN",
  "STOP_AND_REQUEST_HUMAN_REVIEW"
)

result <- list(
  valid = valid,
  decision = out_decision,
  confidence = if (conf %in% valid_confidence) conf else NULL,
  accepted_parameters = accepted,
  rejected_parameters = rejected,
  warnings = unique(warnings),
  next_action = next_action,
  whitelist_parameters = agent_allowed_parameters(),
  protected_parameters = agent_protected_parameters()
)
agent_write_json(result, output_path)
cat("[INFO] Validated decision written to ", agent_norm_path(output_path), "\n", sep = "")
if (!valid) quit(status = 2L)