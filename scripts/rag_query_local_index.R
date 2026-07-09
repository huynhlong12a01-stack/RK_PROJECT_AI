# ============================================================
# Query local-only RAG chunks with a transparent lexical score.
# This is not an LLM and does not call any external API.
# ============================================================

source("scripts/agent_utils.R")

parse_args <- function(args) {
  out <- list(query = NULL, chunks = "knowledge/index/local_chunks/chunks.jsonl", output = "agent/responses/rag_query_result.json", top_k = 8)
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
  out$top_k <- as.integer(out$top_k)
  out
}

normalize_text <- function(x) {
  x <- tolower(enc2utf8(as.character(x)))
  x <- gsub("[^[:alnum:]_]+", " ", x)
  gsub("\\s+", " ", trimws(x))
}

tokenize <- function(x) {
  toks <- unlist(strsplit(normalize_text(x), "\\s+"), use.names = FALSE)
  toks[nchar(toks) >= 3]
}

read_jsonl <- function(path) {
  if (!file.exists(path)) stop(paste0("Chunks file not found: ", path, ". Run .\\run_rag_inventory.ps1 and .\\run_rag_build_local_index.ps1 first."))
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- lines[nzchar(trimws(lines))]
  if (length(lines) == 0) return(list())
  lapply(lines, function(line) {
    jsonlite::fromJSON(line, simplifyVector = FALSE)
  })
}

score_chunk <- function(query_tokens, text) {
  if (length(query_tokens) == 0) return(0)
  text_norm <- normalize_text(text)
  sum(vapply(query_tokens, function(tok) {
    m <- gregexpr(paste0("\\b", tok, "\\b"), text_norm, perl = TRUE)[[1]]
    if (identical(m, -1L)) 0 else length(m)
  }, numeric(1)))
}

make_snippet <- function(text, query_tokens, max_chars = 700L) {
  text <- gsub("\\s+", " ", trimws(enc2utf8(text)))
  if (!nzchar(text)) return("")
  pos <- Inf
  low <- tolower(text)
  for (tok in query_tokens) {
    p <- regexpr(tok, low, fixed = TRUE)[[1]]
    if (p > 0 && p < pos) pos <- p
  }
  if (!is.finite(pos)) pos <- 1L
  start <- max(1L, pos - 120L)
  snippet <- substr(text, start, min(nchar(text), start + max_chars - 1L))
  if (start > 1L) snippet <- paste0("...", snippet)
  if (nchar(text) > start + max_chars - 1L) snippet <- paste0(snippet, "...")
  snippet
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
if (is.null(args$query) || !nzchar(trimws(args$query))) stop("Missing --query. Example: Rscript scripts/rag_query_local_index.R --query \"spatial cross-validation\"")
if (!is.finite(args$top_k) || args$top_k < 1L) args$top_k <- 8L

chunks <- read_jsonl(args$chunks)
query_tokens <- unique(tokenize(args$query))

if (length(chunks) == 0) {
  matches <- list()
} else {
  scores <- vapply(chunks, function(rec) score_chunk(query_tokens, rec$text %||% ""), numeric(1))
  keep <- which(scores > 0)
  keep <- keep[order(scores[keep], decreasing = TRUE)]
  keep <- head(keep, args$top_k)
  matches <- lapply(keep, function(idx) {
    rec <- chunks[[idx]]
    list(
      score = unname(scores[[idx]]),
      chunk_id = rec$chunk_id %||% NA_character_,
      doc_id = rec$doc_id %||% NA_character_,
      local_relative_path = rec$local_relative_path %||% NA_character_,
      chunk_index = rec$chunk_index %||% NA_integer_,
      snippet = make_snippet(rec$text %||% "", query_tokens)
    )
  })
}

result <- list(
  query = args$query,
  chunks_file = agent_norm_path(args$chunks),
  top_k = args$top_k,
  n_chunks_scanned = length(chunks),
  n_matches = length(matches),
  method = "lexical_term_frequency",
  limitations = "This local retriever is transparent keyword scoring. Use it to gather evidence candidates, not as final scientific judgment.",
  matches = matches
)
agent_write_json(result, args$output)
cat("[INFO] Query: ", args$query, "\n", sep = "")
cat("[INFO] Chunks scanned: ", length(chunks), "\n", sep = "")
cat("[INFO] Matches: ", length(matches), "\n", sep = "")
cat("[INFO] Output: ", agent_norm_path(args$output), "\n", sep = "")
