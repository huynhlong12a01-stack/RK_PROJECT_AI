# ============================================================
# Query a JSONL RAG index with transparent lexical scoring.
#
# The curated index is the default. A different --chunks file can still be
# supplied, including the legacy local-PDF chunks file.
# ============================================================

source("_UNG_DUNG/engine/scripts/agent_utils.R")

parse_args <- function(args) {
  out <- list(
    query = NULL,
    chunks = "knowledge/index/curated/chunks.jsonl",
    taxonomy = "knowledge/metadata/topic_taxonomy.json",
    output = "_UNG_DUNG/runtime/rag_query_result.json",
    top_k = 8L
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
  out$top_k <- suppressWarnings(as.integer(out$top_k))
  out
}

strip_accents <- function(x) {
  x <- enc2utf8(as.character(x))
  if (requireNamespace("stringi", quietly = TRUE)) {
    return(stringi::stri_trans_general(x, "NFD; [:Nonspacing Mark:] Remove; NFC; Latin-ASCII"))
  }
  converted <- suppressWarnings(iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT"))
  converted[is.na(converted)] <- x[is.na(converted)]
  converted
}

normalize_text <- function(x) {
  x <- tolower(strip_accents(x))
  x <- gsub("_", " ", x, fixed = TRUE)
  x <- gsub("[^a-z0-9]+", " ", x)
  gsub("\\s+", " ", trimws(x))
}

tokenize <- function(x) {
  toks <- unlist(strsplit(normalize_text(x), "\\s+"), use.names = FALSE)
  unique(toks[nchar(toks) >= 2L])
}

flatten_strings <- function(x) {
  if (is.null(x)) return(character(0))
  vals <- unlist(x, recursive = TRUE, use.names = FALSE)
  vals <- trimws(enc2utf8(as.character(vals)))
  unique(vals[!is.na(vals) & nzchar(vals)])
}

read_alias_groups <- function(path) {
  if (!file.exists(path)) return(list())
  taxonomy <- try(agent_read_json(path), silent = TRUE)
  if (inherits(taxonomy, "try-error") || !is.list(taxonomy)) return(list())
  alias_keys <- names(taxonomy)[grepl("alias|synonym|bilingual", names(taxonomy), ignore.case = TRUE)]
  groups <- list()
  for (key in alias_keys) {
    container <- taxonomy[[key]]
    if (!is.list(container)) next
    if (!is.null(names(container)) && any(nzchar(names(container)))) {
      for (nm in names(container)) {
        values <- unique(c(nm, flatten_strings(container[[nm]])))
        values <- values[nzchar(normalize_text(values))]
        if (length(values) >= 2L) groups[[length(groups) + 1L]] <- values
      }
    } else {
      for (item in container) {
        values <- flatten_strings(item)
        values <- values[nzchar(normalize_text(values))]
        if (length(values) >= 2L) groups[[length(groups) + 1L]] <- values
      }
    }
  }
  groups
}

expand_query <- function(query, alias_groups) {
  query_norm <- normalize_text(query)
  query_padded <- paste0(" ", query_norm, " ")
  matched_groups <- list()
  phrases <- character(0)
  for (group in alias_groups) {
    group_norm <- unique(normalize_text(group))
    group_norm <- group_norm[nzchar(group_norm)]
    hit <- any(vapply(group_norm, function(term) grepl(paste0(" ", term, " "), query_padded, fixed = TRUE), logical(1)))
    if (hit) {
      phrases <- unique(c(phrases, group))
      matched_groups[[length(matched_groups) + 1L]] <- group
    }
  }
  original_tokens <- tokenize(query)
  expanded_tokens <- unique(c(original_tokens, tokenize(phrases)))
  list(original_tokens = original_tokens, tokens = expanded_tokens, groups = matched_groups)
}

read_jsonl <- function(path) {
  if (!file.exists(path)) {
    stop(paste0(
      "Chunks file not found: ", path,
      ". Run .\\run_rag_build_curated_index.ps1 (default) or provide --chunks for another index."
    ), call. = FALSE)
  }
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- lines[nzchar(trimws(lines))]
  if (length(lines) == 0L) return(list())
  lapply(lines, function(line) jsonlite::fromJSON(line, simplifyVector = FALSE))
}

score_chunk <- function(query_tokens, text) {
  if (length(query_tokens) == 0L) return(0)
  text_tokens <- tokenize(text)
  if (length(text_tokens) == 0L) return(0)
  counts <- table(text_tokens)
  sum(vapply(query_tokens, function(tok) {
    if (tok %in% names(counts)) 1 + log1p(unname(counts[[tok]])) else 0
  }, numeric(1)))
}

make_snippet <- function(text, query_tokens, max_chars = 700L) {
  text <- gsub("\\s+", " ", trimws(enc2utf8(as.character(text))))
  if (!nzchar(text)) return("")
  normalized <- normalize_text(text)
  positions <- vapply(query_tokens, function(tok) {
    pos <- regexpr(tok, normalized, fixed = TRUE)[[1L]]
    if (pos < 1L) Inf else pos
  }, numeric(1))
  pos <- suppressWarnings(min(positions, na.rm = TRUE))
  if (!is.finite(pos)) pos <- 1L
  # Normalization can change character offsets, so use a conservative window.
  start <- max(1L, min(nchar(text), as.integer(pos)) - 120L)
  snippet <- substr(text, start, min(nchar(text), start + max_chars - 1L))
  if (start > 1L) snippet <- paste0("...", snippet)
  if (nchar(text) > start + max_chars - 1L) snippet <- paste0(snippet, "...")
  snippet
}

compact_citation <- function(citation) {
  if (is.null(citation) || length(citation) == 0L) return(NULL)
  keep <- c("doc_id", "title", "authors", "year", "journal_or_publisher", "doi", "url")
  out <- citation[intersect(keep, names(citation))]
  out <- out[!vapply(out, function(x) {
    is.null(x) || length(x) == 0L || all(is.na(x)) || !nzchar(trimws(as.character(x[[1L]])))
  }, logical(1))]
  if (length(out) == 0L) NULL else out
}

chunk_citations <- function(rec) {
  evidence <- rec$evidence_citations %||% list()
  if (!is.list(evidence)) evidence <- list(evidence)
  citations <- Filter(Negate(is.null), lapply(evidence, compact_citation))
  if (length(citations) == 0L) {
    direct <- compact_citation(rec$citation %||% NULL)
    if (!is.null(direct)) citations <- list(direct)
  }
  citations
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
if (is.null(args$query) || !nzchar(trimws(args$query))) {
  stop("Missing --query. Example: Rscript _UNG_DUNG/engine/scripts/rag_query_local_index.R --query \"spatial cross-validation\"", call. = FALSE)
}
if (!is.finite(args$top_k) || args$top_k < 1L) args$top_k <- 8L

chunks <- read_jsonl(args$chunks)
aliases <- read_alias_groups(args$taxonomy)
expanded <- expand_query(args$query, aliases)

if (length(chunks) == 0L) {
  matches <- list()
} else {
  scores <- vapply(chunks, function(rec) score_chunk(expanded$tokens, rec$text %||% ""), numeric(1))
  keep <- which(scores > 0)
  if (length(keep) > 0L) {
    quality_bonus <- vapply(chunks[keep], function(rec) {
      q <- tolower(as.character(rec$quality_level %||% ""))
      if (q %in% c("core", "strong")) 0.25 else if (q %in% c("supporting", "moderate")) 0.10 else 0
    }, numeric(1))
    ranked_scores <- scores[keep] + quality_bonus
    keep <- keep[order(ranked_scores, decreasing = TRUE)]
  }
  keep <- head(keep, args$top_k)
  matches <- lapply(keep, function(idx) {
    rec <- chunks[[idx]]
    citations <- chunk_citations(rec)
    links <- unique(unlist(lapply(citations, function(cit) {
      c(cit$doi %||% character(0), cit$url %||% character(0))
    }), use.names = FALSE))
    links <- links[nzchar(links)]
    list(
      score = unname(scores[[idx]]),
      chunk_id = rec$chunk_id %||% NA_character_,
      doc_id = rec$doc_id %||% NA_character_,
      record_type = rec$record_type %||% "local_document_chunk",
      quality_level = rec$quality_level %||% NA_character_,
      local_relative_path = rec$local_relative_path %||% NA_character_,
      chunk_index = rec$chunk_index %||% NA_integer_,
      snippet = make_snippet(rec$text %||% "", expanded$tokens),
      citations = citations,
      citation_links = links
    )
  })
}

result <- list(
  query = args$query,
  normalized_query = normalize_text(args$query),
  original_terms = expanded$original_tokens,
  expanded_terms = expanded$tokens,
  alias_groups_matched = expanded$groups,
  taxonomy_file = if (file.exists(args$taxonomy)) agent_norm_path(args$taxonomy) else NA_character_,
  chunks_file = agent_norm_path(args$chunks),
  top_k = args$top_k,
  n_chunks_scanned = length(chunks),
  n_matches = length(matches),
  method = "accent_normalized_lexical_term_frequency_with_taxonomy_aliases",
  limitations = "This retriever ranks curated evidence candidates. It does not establish causality, replace source reading, or make final scientific judgments.",
  matches = matches
)
agent_write_json(result, args$output)
cat("[INFO] Query: ", args$query, "\n", sep = "")
cat("[INFO] Expanded terms: ", paste(expanded$tokens, collapse = ", "), "\n", sep = "")
cat("[INFO] Chunks scanned: ", length(chunks), "\n", sep = "")
cat("[INFO] Matches: ", length(matches), "\n", sep = "")
cat("[INFO] Output: ", agent_norm_path(args$output), "\n", sep = "")
