# ============================================================
# Smoke validation for the RAG knowledge metadata layer.
# This does not download papers and does not build embeddings.
# ============================================================

source("scripts/agent_utils.R")

required_source_cols <- c(
  "doc_id", "title", "authors", "year", "source_type",
  "journal_or_publisher", "doi", "url", "access_date", "language",
  "topic_tags", "soil_indicators", "geography", "method_tags",
  "quality_level", "license_or_access_note", "notes"
)

valid_source_types <- c("book", "peer_reviewed_paper", "guideline", "report", "thesis", "documentation")
valid_quality_levels <- c("core", "supporting", "weak", "exclude")
valid_strengths <- c("strong", "moderate", "weak")

read_csv_if_exists <- function(path) {
  if (!file.exists(path)) stop(paste0("File not found: ", path))
  agent_require_package("readr")
  x <- as.data.frame(readr::read_csv(path, show_col_types = FALSE, progress = FALSE))
  bom <- rawToChar(as.raw(c(0xef, 0xbb, 0xbf)))
  names(x) <- trimws(sub(paste0("^", bom), "", names(x), useBytes = TRUE))
  x
}

validate_sources <- function(path = "knowledge/metadata/sources.csv") {
  x <- read_csv_if_exists(path)
  warnings <- character(0)
  errors <- character(0)

  missing_cols <- setdiff(required_source_cols, names(x))
  if (length(missing_cols) > 0) errors <- c(errors, paste0("sources.csv missing columns: ", paste(missing_cols, collapse = ", ")))

  if (nrow(x) > 0 && "doc_id" %in% names(x)) {
    blank_ids <- which(!nzchar(trimws(x$doc_id)))
    if (length(blank_ids) > 0) errors <- c(errors, paste0("Blank doc_id rows: ", paste(blank_ids, collapse = ", ")))
    dup_ids <- unique(x$doc_id[duplicated(x$doc_id) & nzchar(x$doc_id)])
    if (length(dup_ids) > 0) errors <- c(errors, paste0("Duplicate doc_id values: ", paste(dup_ids, collapse = ", ")))
  }

  if (nrow(x) > 0 && "source_type" %in% names(x)) {
    bad <- setdiff(unique(x$source_type[nzchar(x$source_type)]), valid_source_types)
    if (length(bad) > 0) errors <- c(errors, paste0("Invalid source_type: ", paste(bad, collapse = ", ")))
  }

  if (nrow(x) > 0 && "quality_level" %in% names(x)) {
    bad <- setdiff(unique(x$quality_level[nzchar(x$quality_level)]), valid_quality_levels)
    if (length(bad) > 0) errors <- c(errors, paste0("Invalid quality_level: ", paste(bad, collapse = ", ")))
  }

  if (nrow(x) == 0) warnings <- c(warnings, "sources.csv has only headers; add verified sources before using RAG for scientific claims.")

  list(path = agent_norm_path(path), n_sources = nrow(x), errors = errors, warnings = warnings)
}

validate_evidence_cards <- function(dir = "knowledge/notes/evidence_cards", source_ids = character(0)) {
  files <- list.files(dir, pattern = "\\.json$", full.names = TRUE)
  files <- files[!grepl("template", basename(files), ignore.case = TRUE)]
  errors <- character(0)
  warnings <- character(0)
  cards <- list()

  for (f in files) {
    card <- try(agent_read_json(f), silent = TRUE)
    if (inherits(card, "try-error")) {
      errors <- c(errors, paste0("Cannot read evidence card: ", agent_norm_path(f)))
      next
    }
    required <- c("claim_id", "claim", "applies_to", "evidence_sources", "strength", "conditions", "limitations", "recommended_action", "not_allowed_action")
    missing <- setdiff(required, names(card))
    if (length(missing) > 0) errors <- c(errors, paste0(agent_norm_path(f), " missing fields: ", paste(missing, collapse = ", ")))
    if (!is.null(card$strength) && !(card$strength %in% valid_strengths)) errors <- c(errors, paste0(agent_norm_path(f), " invalid strength: ", card$strength))
    evidence_sources <- unlist(card$evidence_sources %||% character(0), use.names = FALSE)
    unknown_sources <- setdiff(evidence_sources, source_ids)
    if (length(unknown_sources) > 0) errors <- c(errors, paste0(agent_norm_path(f), " references unknown source doc_id(s): ", paste(unknown_sources, collapse = ", ")))
    cards[[length(cards) + 1L]] <- list(file = agent_norm_path(f), claim_id = card$claim_id %||% NA_character_)
  }

  if (length(files) == 0) warnings <- c(warnings, "No evidence cards yet; RAG can only use metadata/templates.")
  list(directory = agent_norm_path(dir), n_cards = length(files), cards = cards, errors = errors, warnings = warnings)
}

args <- commandArgs(trailingOnly = TRUE)
output <- if (length(args) > 0) args[[1]] else "agent/responses/rag_smoke_test.json"

source_result <- validate_sources()
source_table <- read_csv_if_exists("knowledge/metadata/sources.csv")
source_ids <- if ("doc_id" %in% names(source_table)) source_table$doc_id else character(0)

result <- list(
  status = "completed",
  sources = source_result,
  evidence_cards = validate_evidence_cards(source_ids = source_ids),
  prompts = list(
    rag_system_prompt = file.exists("knowledge/prompts/rag_system_prompt.md"),
    rag_query_prompt = file.exists("knowledge/prompts/rag_query_prompt.md"),
    evidence_check_prompt = file.exists("knowledge/prompts/evidence_check_prompt.md"),
    report_citation_prompt = file.exists("knowledge/prompts/report_citation_prompt.md")
  )
)

all_errors <- c(result$sources$errors, result$evidence_cards$errors)
result$valid <- length(all_errors) == 0
result$errors <- all_errors
result$warnings <- unique(c(result$sources$warnings, result$evidence_cards$warnings))

agent_write_json(result, output)
cat("[INFO] RAG smoke test JSON: ", agent_norm_path(output), "\n", sep = "")
if (length(result$warnings) > 0) cat("[WARN] ", paste(result$warnings, collapse = "\n[WARN] "), "\n", sep = "")
if (!result$valid) stop(paste(result$errors, collapse = "; "))