# Local Research Library Workflow

Thu m?c `knowledge/library/` d�nh cho t�i li?u b?n c� quy?n s? d?ng h?p ph�p: PDF t? thu vi?n tru?ng, t�i li?u open-access, guideline c�ng khai, ho?c t�i li?u do b?n t? t?o.

Thu m?c n�y b? Git ignore. Kh�ng commit PDF/raw full text v�o repository.

## Quy tr�nh d? xu?t

1. B?n t? t?i t�i li?u b?ng quy?n truy c?p h?p ph�p c?a m�nh.
2. �?t file v�o `knowledge/library/`, c� th? chia thu m?c theo ch? d?:

```text
knowledge/library/geostatistics/
knowledge/library/regression_kriging/
knowledge/library/digital_soil_mapping/
knowledge/library/spatial_cv/
knowledge/library/soil_nutrients/
knowledge/library/uncertainty/
```

3. Ch?y ki?m k�:

```powershell
.\run_rag_inventory.ps1
```

4. M? file draft metadata v� b? sung DOI, t�c gi?, nam, tag:

```text
knowledge/metadata/local_source_metadata_draft.csv
```

5. N?u m�y c� package R `pdftools`, t?o local chunks:

```powershell
.\run_rag_build_local_index.ps1
```

6. Ch?y smoke test:

```powershell
.\run_rag_smoke_test.ps1
```

## Nguy�n t?c b?n quy?n

- Kh�ng commit PDF/raw text/chunks v�o Git.
- Kh�ng chia s? l?i full text.
- Kh�ng tr�ch d?n ngu?n n?u metadata chua ki?m ch?ng.
- Kh�ng t?o citation gi?.
- Ch? d�ng n?i b? cho nghi�n c?u/h?c thu?t theo quy?n truy c?p c?a b?n.

## Khi b�o c�o

RAG c� th? d�ng n?i dung local d? h? tr? hi?u t�i li?u, nhung report n�n tr�ch d?n b?ng DOI/URL/doc_id d� ki?m ch?ng trong metadata.
## Truy v?n kho RAG c?c b?

Sau khi d� ch?y inventory v� build local chunks, c� th? truy v?n nhanh b?ng keyword scoring minh b?ch:

```powershell
.\run_rag_query.ps1 -Query "spatial cross-validation variogram range" -TopK 8
```

Output:

```text
agent/responses/rag_query_result.json
```

C�ng c? n�y kh�ng g?i LLM v� kh�ng g?i t�i li?u ra ngo�i. N� ch? t�m do?n li�n quan trong `knowledge/index/local_chunks/chunks.jsonl`. K?t qu? l� evidence candidates d? agent d?c ti?p, kh�ng ph?i k?t lu?n khoa h?c cu?i c�ng.
