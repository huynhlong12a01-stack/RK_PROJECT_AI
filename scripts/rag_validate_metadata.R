# ============================================================
# Validate curated RAG metadata, taxonomy, and evidence integrity.
# This smoke test performs no downloads and builds no embeddings.
# ============================================================

source("scripts/agent_utils.R")

required_source_cols <- c(
  "doc_id", "title", "authors", "year", "source_type",
  "journal_or_publisher", "doi", "url", "access_date", "language",
  "topic_tags", "soil_indicators", "geography", "method_tags",
  "quality_level", "license_or_access_note", "notes"
)

fallback_source_types <- c("book", "peer_reviewed_paper", "guideline", "report", "thesis", "documentation")
fallback_quality_levels <- c("core", "supporting", "weak", "exclude")
valid_strengths <- c("strong", "moderate", "weak")
taxonomy_fields <- c("topic_tags", "soil_indicators", "method_tags", "quality_levels", "source_types")

clean_values <- function(x) {
  if (is.null(x) || length(x) == 0L) return(character(0))
  values <- trimws(enc2utf8(as.character(unlist(x, recursive = TRUE, use.names = FALSE))))
  unique(values[!is.na(values) & nzchar(values)])
}

split_tags <- function(x) {
  if (is.null(x) || length(x) == 0L || is.na(x) || !nzchar(trimws(x))) return(character(0))
  clean_values(strsplit(as.character(x), ";", fixed = TRUE)[[1L]])
}

read_csv_if_exists <- function(path) {
  if (!file.exists(path)) stop(paste0("File not found: ", path), call. = FALSE)
  agent_require_package("readr")
  x <- as.data.frame(readr::read_csv(path, show_col_types = FALSE, progress = FALSE))
  names(x) <- trimws(sub("^\ufeff", "", names(x)))
  x
}

validate_taxonomy <- function(path = "knowledge/metadata/topic_taxonomy.json") {
  errors <- character(0)
  warnings <- character(0)
  if (!file.exists(path)) {
    return(list(
      path = agent_norm_path(path), taxonomy = list(),
      errors = paste0("Taxonomy file not found: ", agent_norm_path(path)), warnings = warnings
    ))
  }
  taxonomy <- try(agent_read_json(path), silent = TRUE)
  if (inherits(taxonomy, "try-error") || !is.list(taxonomy)) {
    return(list(
      path = agent_norm_path(path), taxonomy = list(),
      errors = paste0("Cannot parse taxonomy JSON: ", agent_norm_path(path)), warnings = warnings
    ))
  }

  missing <- setdiff(taxonomy_fields, names(taxonomy))
  if (length(missing) > 0L) errors <- c(errors, paste0("Taxonomy missing fields: ", paste(missing, collapse = ", ")))
  for (field in intersect(taxonomy_fields, names(taxonomy))) {
    values <- clean_values(taxonomy[[field]])
    raw_values <- trimws(as.character(unlist(taxonomy[[field]], recursive = TRUE, use.names = FALSE)))
    if (length(values) == 0L) errors <- c(errors, paste0("Taxonomy field is empty: ", field))
    duplicates <- unique(raw_values[duplicated(raw_values) & nzchar(raw_values)])
    if (length(duplicates) > 0L) errors <- c(errors, paste0("Duplicate values in taxonomy ", field, ": ", paste(duplicates, collapse = ", ")))
  }

  all_canonical <- unique(c(
    clean_values(taxonomy$topic_tags),
    clean_values(taxonomy$soil_indicators),
    clean_values(taxonomy$method_tags)
  ))
  alias_keys <- names(taxonomy)[grepl("alias|synonym|bilingual", names(taxonomy), ignore.case = TRUE)]
  for (key in alias_keys) {
    container <- taxonomy[[key]]
    if (!is.list(container)) {
      errors <- c(errors, paste0("Taxonomy alias field must be an object or list: ", key))
      next
    }
    if (!is.null(names(container)) && any(nzchar(names(container)))) {
      canonical <- names(container)[nzchar(names(container))]
      unknown <- setdiff(canonical, all_canonical)
      if (length(unknown) > 0L) {
        errors <- c(errors, paste0("Alias field ", key, " references unknown canonical term(s): ", paste(unknown, collapse = ", ")))
      }
      empty <- canonical[vapply(container[canonical], function(x) length(clean_values(x)) == 0L, logical(1))]
      if (length(empty) > 0L) errors <- c(errors, paste0("Alias groups without aliases in ", key, ": ", paste(empty, collapse = ", ")))
    } else {
      for (i in seq_along(container)) {
        item <- container[[i]]
        canonical <- clean_values(item$canonical %||% character(0))
        if (length(canonical) != 1L) {
          errors <- c(errors, paste0("Alias record ", i, " in ", key, " must contain one canonical value."))
        } else if (!(canonical %in% all_canonical)) {
          errors <- c(errors, paste0("Alias record ", i, " in ", key, " references unknown canonical term: ", canonical))
        }
        aliases <- clean_values(item[names(item) != "canonical"])
        if (length(aliases) == 0L) errors <- c(errors, paste0("Alias record ", i, " in ", key, " has no aliases."))
      }
    }
  }

  list(path = agent_norm_path(path), taxonomy = taxonomy, errors = unique(errors), warnings = unique(warnings))
}

valid_doi <- function(x) grepl("^10\\.[0-9]{4,9}/\\S+$", x, perl = TRUE)
valid_url <- function(x) grepl("^https?://[^[:space:]]+$", x, perl = TRUE)

valid_iso_date <- function(x) {
  if (!grepl("^\\d{4}-\\d{2}-\\d{2}$", x)) return(FALSE)
  parsed <- suppressWarnings(as.Date(x, format = "%Y-%m-%d"))
  !is.na(parsed) && identical(format(parsed, "%Y-%m-%d"), x)
}

validate_sources <- function(path, taxonomy) {
  x <- read_csv_if_exists(path)
  warnings <- character(0)
  errors <- character(0)

  missing_cols <- setdiff(required_source_cols, names(x))
  if (length(missing_cols) > 0L) {
    errors <- c(errors, paste0("sources.csv missing columns: ", paste(missing_cols, collapse = ", ")))
    return(list(path = agent_norm_path(path), n_sources = nrow(x), table = x, errors = errors, warnings = warnings))
  }

  blank_ids <- which(is.na(x$doc_id) | !nzchar(trimws(x$doc_id)))
  if (length(blank_ids) > 0L) errors <- c(errors, paste0("Blank doc_id rows: ", paste(blank_ids, collapse = ", ")))
  dup_ids <- unique(x$doc_id[duplicated(x$doc_id) & !is.na(x$doc_id) & nzchar(x$doc_id)])
  if (length(dup_ids) > 0L) errors <- c(errors, paste0("Duplicate doc_id values: ", paste(dup_ids, collapse = ", ")))

  valid_source_types <- clean_values(taxonomy$source_types)
  if (length(valid_source_types) == 0L) valid_source_types <- fallback_source_types
  source_types <- clean_values(x$source_type)
  bad_types <- setdiff(source_types, valid_source_types)
  if (length(bad_types) > 0L) errors <- c(errors, paste0("Invalid source_type: ", paste(bad_types, collapse = ", ")))

  valid_quality_levels <- clean_values(taxonomy$quality_levels)
  if (length(valid_quality_levels) == 0L) valid_quality_levels <- fallback_quality_levels
  quality_levels <- clean_values(x$quality_level)
  bad_quality <- setdiff(quality_levels, valid_quality_levels)
  if (length(bad_quality) > 0L) errors <- c(errors, paste0("Invalid quality_level: ", paste(bad_quality, collapse = ", ")))

  for (field in c("topic_tags", "soil_indicators", "method_tags")) {
    allowed <- clean_values(taxonomy[[field]])
    if (length(allowed) == 0L) next
    used <- unique(unlist(lapply(x[[field]], split_tags), use.names = FALSE))
    unknown <- setdiff(used, allowed)
    if (length(unknown) > 0L) {
      errors <- c(errors, paste0("sources.csv ", field, " contains terms absent from taxonomy: ", paste(unknown, collapse = ", ")))
    }
  }

  dois <- ifelse(is.na(x$doi), "", trimws(x$doi))
  bad_doi_rows <- which(nzchar(dois) & !vapply(dois, valid_doi, logical(1)))
  if (length(bad_doi_rows) > 0L) errors <- c(errors, paste0("Malformed DOI at source rows: ", paste(bad_doi_rows, collapse = ", ")))
  normalized_doi <- tolower(sub("^https?://(dx\\.)?doi\\.org/", "", dois, ignore.case = TRUE))
  duplicate_doi <- unique(normalized_doi[duplicated(normalized_doi) & nzchar(normalized_doi)])
  if (length(duplicate_doi) > 0L) errors <- c(errors, paste0("Duplicate DOI values: ", paste(duplicate_doi, collapse = ", ")))

  urls <- ifelse(is.na(x$url), "", trimws(x$url))
  bad_url_rows <- which(nzchar(urls) & !vapply(urls, valid_url, logical(1)))
  if (length(bad_url_rows) > 0L) errors <- c(errors, paste0("Malformed URL at source rows: ", paste(bad_url_rows, collapse = ", ")))
  no_locator_rows <- which(!nzchar(dois) & !nzchar(urls))
  if (length(no_locator_rows) > 0L) errors <- c(errors, paste0("Sources without DOI or URL at rows: ", paste(no_locator_rows, collapse = ", ")))

  dates <- ifelse(is.na(x$access_date), "", as.character(x$access_date))
  bad_date_rows <- which(!nzchar(dates) | !vapply(dates, valid_iso_date, logical(1)))
  if (length(bad_date_rows) > 0L) errors <- c(errors, paste0("Missing or invalid ISO access_date at source rows: ", paste(bad_date_rows, collapse = ", ")))
  valid_date_rows <- setdiff(seq_along(dates), bad_date_rows)
  if (length(valid_date_rows) > 0L) {
    future <- valid_date_rows[as.Date(dates[valid_date_rows]) > Sys.Date()]
    if (length(future) > 0L) errors <- c(errors, paste0("Future access_date at source rows: ", paste(future, collapse = ", ")))
  }

  years <- suppressWarnings(as.integer(x$year))
  bad_year_rows <- which(is.na(years) | years < 1800L | years > as.integer(format(Sys.Date(), "%Y")))
  if (length(bad_year_rows) > 0L) errors <- c(errors, paste0("Missing or implausible publication year at source rows: ", paste(bad_year_rows, collapse = ", ")))

  if (nrow(x) == 0L) warnings <- c(warnings, "sources.csv has only headers; add verified sources before scientific retrieval.")
  list(path = agent_norm_path(path), n_sources = nrow(x), table = x, errors = unique(errors), warnings = unique(warnings))
}

validate_evidence_cards <- function(dir, source_table) {
  files <- sort(list.files(dir, pattern = "\\.json$", full.names = TRUE))
  files <- files[!grepl("template", basename(files), ignore.case = TRUE)]
  errors <- character(0)
  warnings <- character(0)
  cards <- list()
  required <- c(
    "claim_id", "claim", "applies_to", "evidence_sources", "strength",
    "conditions", "limitations", "recommended_action", "not_allowed_action"
  )

  source_ids <- if ("doc_id" %in% names(source_table)) clean_values(source_table$doc_id) else character(0)
  source_quality <- if (all(c("doc_id", "quality_level") %in% names(source_table))) {
    stats::setNames(as.character(source_table$quality_level), as.character(source_table$doc_id))
  } else character(0)

  for (file in files) {
    card <- try(agent_read_json(file), silent = TRUE)
    if (inherits(card, "try-error")) {
      errors <- c(errors, paste0("Cannot read evidence card: ", agent_norm_path(file)))
      next
    }
    missing <- setdiff(required, names(card))
    if (length(missing) > 0L) errors <- c(errors, paste0(agent_norm_path(file), " missing fields: ", paste(missing, collapse = ", ")))

    claim_id <- trimws(as.character(card$claim_id %||% ""))
    claim <- trimws(as.character(card$claim %||% ""))
    if (!nzchar(claim_id)) errors <- c(errors, paste0(agent_norm_path(file), " has blank claim_id."))
    if (!nzchar(claim)) errors <- c(errors, paste0(agent_norm_path(file), " has blank claim."))
    strength <- as.character(card$strength %||% "")
    if (!(strength %in% valid_strengths)) errors <- c(errors, paste0(agent_norm_path(file), " invalid strength: ", strength))

    evidence_sources <- clean_values(card$evidence_sources)
    if (length(evidence_sources) == 0L) errors <- c(errors, paste0(agent_norm_path(file), " has no evidence sources."))
    unknown_sources <- setdiff(evidence_sources, source_ids)
    if (length(unknown_sources) > 0L) {
      errors <- c(errors, paste0(agent_norm_path(file), " references unknown source doc_id(s): ", paste(unknown_sources, collapse = ", ")))
    }
    known_sources <- intersect(evidence_sources, source_ids)
    excluded_sources <- known_sources[tolower(source_quality[known_sources]) == "exclude"]
    if (length(excluded_sources) > 0L) {
      errors <- c(errors, paste0(agent_norm_path(file), " cites excluded source(s): ", paste(excluded_sources, collapse = ", ")))
    }
    usable_sources <- setdiff(known_sources, excluded_sources)
    if (identical(strength, "strong") && length(unique(usable_sources)) < 2L) {
      errors <- c(errors, paste0(agent_norm_path(file), " is strong but has fewer than two usable curated sources."))
    }

    cards[[length(cards) + 1L]] <- list(
      file = agent_norm_path(file),
      claim_id = claim_id,
      normalized_claim = tolower(gsub("\\s+", " ", trimws(claim))),
      strength = strength,
      n_evidence_sources = length(evidence_sources)
    )
  }

  claim_ids <- vapply(cards, function(x) x$claim_id, character(1))
  duplicate_ids <- unique(claim_ids[duplicated(claim_ids) & nzchar(claim_ids)])
  if (length(duplicate_ids) > 0L) errors <- c(errors, paste0("Duplicate evidence claim_id values: ", paste(duplicate_ids, collapse = ", ")))
  normalized_claims <- vapply(cards, function(x) x$normalized_claim, character(1))
  duplicate_claims <- unique(normalized_claims[duplicated(normalized_claims) & nzchar(normalized_claims)])
  if (length(duplicate_claims) > 0L) errors <- c(errors, paste0("Duplicate evidence claim text found (normalized): ", paste(duplicate_claims, collapse = " | ")))

  if (length(files) == 0L) warnings <- c(warnings, "No curated evidence cards found.")
  list(
    directory = agent_norm_path(dir), n_cards = length(files), cards = cards,
    errors = unique(errors), warnings = unique(warnings)
  )
}

args <- commandArgs(trailingOnly = TRUE)
output <- if (length(args) > 0L) args[[1L]] else "agent/responses/rag_smoke_test.json"

taxonomy_result <- validate_taxonomy()
source_result <- validate_sources("knowledge/metadata/sources.csv", taxonomy_result$taxonomy)
evidence_result <- validate_evidence_cards("knowledge/notes/evidence_cards", source_result$table)
source_result$table <- NULL

result <- list(
  status = "completed",
  taxonomy = taxonomy_result[names(taxonomy_result) != "taxonomy"],
  sources = source_result,
  evidence_cards = evidence_result,
  prompts = list(
    rag_system_prompt = file.exists("knowledge/prompts/rag_system_prompt.md"),
    rag_query_prompt = file.exists("knowledge/prompts/rag_query_prompt.md"),
    evidence_check_prompt = file.exists("knowledge/prompts/evidence_check_prompt.md"),
    report_citation_prompt = file.exists("knowledge/prompts/report_citation_prompt.md")
  )
)

all_errors <- unique(c(result$taxonomy$errors, result$sources$errors, result$evidence_cards$errors))
result$valid <- length(all_errors) == 0L
result$errors <- all_errors
result$warnings <- unique(c(result$taxonomy$warnings, result$sources$warnings, result$evidence_cards$warnings))

agent_write_json(result, output)
cat("[INFO] RAG metadata validation JSON: ", agent_norm_path(output), "\n", sep = "")
cat("[INFO] Sources: ", result$sources$n_sources, "; evidence cards: ", result$evidence_cards$n_cards, "\n", sep = "")
if (length(result$warnings) > 0L) cat("[WARN] ", paste(result$warnings, collapse = "\n[WARN] "), "\n", sep = "")
if (!result$valid) stop(paste(result$errors, collapse = "; "), call. = FALSE)
