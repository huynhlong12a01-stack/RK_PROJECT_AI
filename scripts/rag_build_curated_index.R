# ============================================================
# Build a compact, auditable RAG index from curated metadata.
#
# Inputs:
#   - knowledge/metadata/sources.csv
#   - knowledge/notes/evidence_cards/*.json (templates excluded)
#
# No paper full text is copied. Every indexed sentence is assembled from
# fields already present in the curated source registry or evidence cards.
# ============================================================

source("scripts/agent_utils.R")

parse_args <- function(args) {
  out <- list(
    sources = "knowledge/metadata/sources.csv",
    evidence_dir = "knowledge/notes/evidence_cards",
    output = "knowledge/index/curated"
  )
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

clean_scalar <- function(x) {
  if (is.null(x) || length(x) == 0L || all(is.na(x))) return("")
  x <- as.character(x[[1L]])
  if (is.na(x)) "" else trimws(enc2utf8(x))
}

clean_vector <- function(x) {
  if (is.null(x) || length(x) == 0L) return(character(0))
  vals <- trimws(enc2utf8(as.character(unlist(x, use.names = FALSE))))
  unique(vals[!is.na(vals) & nzchar(vals)])
}

labeled_text <- function(label, value) {
  value <- clean_scalar(value)
  if (!nzchar(value)) return(character(0))
  paste0(label, ": ", value, ".")
}

source_citation <- function(row) {
  list(
    doc_id = clean_scalar(row$doc_id),
    title = clean_scalar(row$title),
    authors = clean_scalar(row$authors),
    year = suppressWarnings(as.integer(clean_scalar(row$year))),
    journal_or_publisher = clean_scalar(row$journal_or_publisher),
    doi = clean_scalar(row$doi),
    url = clean_scalar(row$url)
  )
}

make_source_chunk <- function(row) {
  doc_id <- clean_scalar(row$doc_id)
  quality <- clean_scalar(row$quality_level)
  fields <- c(
    labeled_text("Title", row$title),
    labeled_text("Authors", row$authors),
    labeled_text("Year", row$year),
    labeled_text("Source type", row$source_type),
    labeled_text("Journal or publisher", row$journal_or_publisher),
    labeled_text("Topics", row$topic_tags),
    labeled_text("Soil indicators", row$soil_indicators),
    labeled_text("Geography", row$geography),
    labeled_text("Methods", row$method_tags),
    labeled_text("Quality level", row$quality_level),
    labeled_text("Access note", row$license_or_access_note),
    labeled_text("Curator notes", row$notes)
  )
  list(
    schema_version = "curated_chunk_v1",
    chunk_id = paste0("source::", doc_id),
    doc_id = doc_id,
    record_type = "source_metadata",
    quality_level = quality,
    text = paste(fields, collapse = " "),
    citation = source_citation(row),
    evidence_citations = list(),
    local_relative_path = agent_norm_path("knowledge/metadata/sources.csv")
  )
}

make_evidence_chunk <- function(card, file, source_lookup) {
  claim_id <- clean_scalar(card$claim_id)
  source_ids <- clean_vector(card$evidence_sources)
  citations <- unname(lapply(source_ids, function(id) {
    if (!is.null(source_lookup[[id]])) source_lookup[[id]] else list(doc_id = id)
  }))
  fields <- c(
    labeled_text("Claim", card$claim),
    labeled_text("Applies to", paste(clean_vector(card$applies_to), collapse = "; ")),
    labeled_text("Evidence strength", card$strength),
    labeled_text("Conditions", card$conditions),
    labeled_text("Limitations", card$limitations),
    labeled_text("Recommended action", card$recommended_action),
    labeled_text("Action not allowed", card$not_allowed_action),
    labeled_text("Evidence source identifiers", paste(source_ids, collapse = "; "))
  )
  list(
    schema_version = "curated_chunk_v1",
    chunk_id = paste0("evidence::", claim_id),
    doc_id = claim_id,
    record_type = "evidence_card",
    quality_level = clean_scalar(card$strength),
    text = paste(fields, collapse = " "),
    citation = list(claim_id = claim_id, evidence_sources = source_ids),
    evidence_citations = citations,
    local_relative_path = agent_norm_path(file)
  )
}

file_sha256 <- function(path) {
  if (!file.exists(path) || !requireNamespace("digest", quietly = TRUE)) return(NA_character_)
  unname(digest::digest(file = path, algo = "sha256", serialize = FALSE))
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
if (!file.exists(args$sources)) stop(paste0("Curated source registry not found: ", args$sources), call. = FALSE)
taxonomy_path <- "knowledge/metadata/topic_taxonomy.json"
if (!file.exists(taxonomy_path)) stop(paste0("Knowledge taxonomy not found: ", taxonomy_path), call. = FALSE)
if (!dir.exists(args$evidence_dir)) stop(paste0("Evidence-card directory not found: ", args$evidence_dir), call. = FALSE)

agent_require_package("readr")
sources <- as.data.frame(readr::read_csv(args$sources, show_col_types = FALSE, progress = FALSE))
names(sources) <- trimws(sub("^\ufeff", "", names(sources)))
if (!all(c("doc_id", "quality_level") %in% names(sources))) {
  stop("sources.csv must contain doc_id and quality_level columns.", call. = FALSE)
}

keep <- !is.na(sources$doc_id) & nzchar(trimws(sources$doc_id)) &
  (is.na(sources$quality_level) | tolower(trimws(sources$quality_level)) != "exclude")
sources_indexed <- sources[keep, , drop = FALSE]
source_chunks <- lapply(seq_len(nrow(sources_indexed)), function(i) make_source_chunk(sources_indexed[i, , drop = FALSE]))

source_lookup <- list()
for (chunk in source_chunks) source_lookup[[chunk$doc_id]] <- chunk$citation

evidence_files <- sort(list.files(args$evidence_dir, pattern = "\\.json$", full.names = TRUE))
evidence_files <- evidence_files[!grepl("template", basename(evidence_files), ignore.case = TRUE)]
evidence_chunks <- lapply(evidence_files, function(file) {
  card <- agent_read_json(file)
  make_evidence_chunk(card, file, source_lookup)
})

chunks <- c(source_chunks, evidence_chunks)
agent_ensure_dir(args$output)
chunks_path <- file.path(args$output, "chunks.jsonl")
json_lines <- vapply(chunks, function(chunk) {
  as.character(jsonlite::toJSON(agent_json_sanitize(chunk), auto_unbox = TRUE, null = "null", na = "null"))
}, character(1))
writeLines(json_lines, chunks_path, useBytes = TRUE)

input_files <- c(args$sources, taxonomy_path, evidence_files)
manifest <- list(
  schema_version = "curated_index_manifest_v1",
  generated_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  purpose = "Auditable lexical retrieval over curated bibliographic metadata and evidence cards; no copyrighted full text.",
  exclusions = c("sources with quality_level=exclude", "evidence-card templates", "paper full text"),
  output = list(
    chunks_file = agent_norm_path(chunks_path),
    sha256 = file_sha256(chunks_path),
    hash_available = requireNamespace("digest", quietly = TRUE)
  ),
  counts = list(
    source_rows_total = nrow(sources),
    source_chunks_indexed = length(source_chunks),
    source_rows_excluded = nrow(sources) - length(source_chunks),
    evidence_cards_indexed = length(evidence_chunks),
    total_chunks = length(chunks)
  ),
  inputs = lapply(input_files, function(path) list(
    path = agent_norm_path(path),
    sha256 = file_sha256(path)
  ))
)
manifest_path <- file.path(args$output, "manifest.json")
agent_write_json(manifest, manifest_path)

compatibility_manifest <- list(
  status = "completed",
  index_type = "curated_lexical_with_vietnamese_english_aliases",
  canonical_manifest = agent_norm_path(manifest_path),
  chunks_file = agent_norm_path(chunks_path),
  n_sources = length(source_chunks),
  n_evidence_cards = length(evidence_chunks),
  n_chunks = length(chunks),
  embedding_model = NULL,
  notes = "Curated retrieval is active; private local chunks remain optional."
)
agent_write_json(compatibility_manifest, "knowledge/index/chunks_manifest.json")

cat("[INFO] Curated chunks: ", length(chunks), "\n", sep = "")
cat("[INFO] Sources indexed: ", length(source_chunks), "\n", sep = "")
cat("[INFO] Evidence cards indexed: ", length(evidence_chunks), "\n", sep = "")
cat("[INFO] Chunks file: ", agent_norm_path(chunks_path), "\n", sep = "")
cat("[INFO] Manifest: ", agent_norm_path(manifest_path), "\n", sep = "")
