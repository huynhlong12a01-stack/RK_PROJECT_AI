# Knowledge Library For Regression Kriging And Digital Soil Mapping

Thư mục này là lớp nền cho RAG/file-based knowledge library của dự án. Mục tiêu là lưu metadata, taxonomy, evidence cards và prompt để AI agent có thể giải thích kết quả Regression Kriging dựa trên nguồn khoa học có kiểm soát.

RAG trong dự án này không thay thế chuyên gia địa thống kê và không được dùng để làm đẹp kết quả. RAG chỉ hỗ trợ:

- Giải thích cảnh báo từ `run_result.json`.
- Đề xuất hướng kiểm tra hoặc rerun có căn cứ.
- Viết report có trích dẫn nguồn.
- Phân biệt bằng chứng mạnh, trung bình, yếu.
- Nói rõ khi thiếu nguồn để kết luận.

## Cấu trúc

```text
knowledge/
  metadata/
    sources.csv
    sources_template.json
    topic_taxonomy.json
  notes/
    evidence_cards/
      evidence_card_template.json
      README.md
  prompts/
    rag_system_prompt.md
    rag_query_prompt.md
    evidence_check_prompt.md
    report_citation_prompt.md
  schemas/
    source_metadata.schema.json
    evidence_card.schema.json
  index/
    chunks_manifest.json
```

`knowledge/library/` được ignore trong Git để tránh commit PDF/raw tài liệu có bản quyền. Chỉ commit metadata, summary tự viết, evidence cards và prompt.

## Quy trình thêm tài liệu

1. Kiểm tra nguồn: tác giả, năm, DOI/URL, publisher/journal.
2. Ghi metadata vào `knowledge/metadata/sources.csv`.
3. Gắn tag theo `knowledge/metadata/topic_taxonomy.json`.
4. Nếu rút ra một luận điểm khoa học quan trọng, tạo evidence card trong `knowledge/notes/evidence_cards/`.
5. Chạy kiểm tra metadata:

```powershell
.\run_rag_smoke_test.ps1
```

## Quy tắc nguồn

Ưu tiên sách/giáo trình địa thống kê kinh điển, peer-reviewed paper, guideline/report từ FAO, ISRIC, USDA/NRCS, JRC hoặc tổ chức khoa học uy tín.

Không dùng làm bằng chứng mạnh: blog không rõ tác giả, slide không rõ nguồn, nội dung quảng cáo phần mềm, paper không liên quan trực tiếp, citation không kiểm chứng được.

## Liên kết với workflow RK

RAG nên đọc:

```text
agent/responses/<run_id>_run_result.json
output/agent_runs/<run_id>/06_report/json/evaluation_<target>.json
output/agent_runs/<run_id>/06_report/tables/neighbor_tuning_<target>.csv
```

RAG có thể xuất:

```text
agent/responses/rag_assessment_<run_id>.json
```

RAG không được bypass validator, không được sửa raw data, không được tắt cross-validation.
## Local copyrighted / licensed library

N?u b?n c� quy?n truy c?p h?p ph�p qua tru?ng/vi?n ho?c t? t?i du?c t�i li?u, d?t file v�o:

```text
knowledge/library/
```

Thu m?c n�y b? Git ignore. Sau d� ch?y:

```powershell
.\run_rag_inventory.ps1
```

N?u mu?n t?o chunks local d? truy v?n n?i b?:

```powershell
.\run_rag_build_local_index.ps1
```

PDF extraction c?n package R `pdftools`. N?u chua c�, script s? b�o r�. Kh�ng commit chunks/PDF v�o Git.

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
