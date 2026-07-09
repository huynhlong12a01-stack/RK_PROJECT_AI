# PROMPT KẾ HOẠCH XÂY DỰNG RAG CHO DỰ ÁN REGRESSION KRIGING / DIGITAL SOIL MAPPING

Bạn là AI coding agent kiêm chuyên gia địa thống kê, Digital Soil Mapping, GIS, R, quản trị tri thức khoa học và thiết kế RAG.

Nhiệm vụ của bạn lần này **không phải chạy Regression Kriging**, cũng **không phải tích hợp LLM thật ngay lập tức**. Nhiệm vụ là khảo sát dự án hiện tại và lập kế hoạch triển khai một hệ thống RAG/file-based knowledge library phục vụ đánh giá khoa học cho workflow Regression Kriging.

Dự án hiện tại chạy bằng:

```text
R
Rscript
PowerShell
File-based JSON API
Git local repository
```

Không chuyển dự án sang Python server, Flask, FastAPI, Shiny hoặc React nếu người dùng chưa yêu cầu. Không làm hỏng workflow RK hiện có. Không sửa dữ liệu gốc.

---

## 1. Mục tiêu RAG

Thiết kế một thư viện tri thức khoa học giúp AI agent:

```text
1. Tra cứu cơ sở khoa học về Regression Kriging, Ordinary Kriging, Universal Kriging, Co-kriging, variogram và cross-validation.
2. Tra cứu nghiên cứu về Digital Soil Mapping và bản đồ dinh dưỡng đất.
3. Tra cứu tiêu chuẩn/khuyến nghị về đánh giá độ chính xác bản đồ đất.
4. Diễn giải kết quả RK dựa trên nguồn khoa học đã kiểm chứng.
5. Đề xuất tham số variogram/neighbor/CV có căn cứ, không dựa vào cảm tính.
6. Viết report có trích dẫn nguồn rõ ràng.
7. Cảnh báo khi dữ liệu/kết quả không đủ tin cậy.
```

RAG không được dùng để “làm đẹp” kết quả. RAG chỉ hỗ trợ lập luận khoa học, kiểm định và giải thích.

---

## 2. Nguyên tắc quan trọng

Trước khi thiết kế hoặc tạo file:

```text
1. Đọc README.md.
2. Đọc AGENT_README.md.
3. Đọc docs/EXECUTING_PROMPT.md.
4. Đọc scripts/00_config.R.
5. Đọc rk_evaluation/evaluation.R.
6. Đọc scripts/agent_run.R, scripts/agent_batch_run.R, scripts/agent_validate_decision.R, scripts/agent_compare_runs.R.
7. Xác định RAG sẽ phục vụ bước nào trong workflow hiện tại.
8. Không thay đổi engine RK nếu chưa có lý do rõ.
9. Không tự ý tải dữ liệu/paper có bản quyền trái phép.
10. Không tạo citation giả.
```

Nếu cần tìm tài liệu khoa học mới, phải dùng nguồn chính thống và kiểm tra DOI/URL/publisher khi có thể.

---

## 3. Loại tài liệu nên đưa vào RAG

Ưu tiên tài liệu có độ tin cậy cao:

```text
1. Sách/giáo trình kinh điển về địa thống kê.
2. Paper peer-reviewed về kriging, regression kriging, variogram modeling.
3. Paper/review về Digital Soil Mapping.
4. Tài liệu FAO, ISRIC, USDA/NRCS, JRC, hoặc tổ chức khoa học đất uy tín.
5. Paper về đánh giá độ chính xác bản đồ đất: RMSE, MAE, ME, R²_pred, RPD, RPIQ, NSE, uncertainty, coverage.
6. Paper về spatial cross-validation, block CV, spatial k-fold, leave-location-out.
7. Paper về mapping dinh dưỡng đất: pH, OM/Humus, CEC, N, P, K, Ca, Mg, S, B, Zn, Cu, Mn, Fe, EC.
8. Tài liệu về class accuracy, confusion matrix, misclassification severity cho phân cấp độ phì/nông học.
9. Tài liệu về uncertainty map, kriging variance, prediction interval.
10. Tài liệu về covariates trong DSM: DEM, slope, NDVI, climate/rainfall, soil type, PCA covariates, remote sensing.
```

Không ưu tiên:

```text
- Blog không có nguồn.
- Slide không rõ tác giả.
- Nội dung quảng cáo phần mềm.
- Paper không liên quan trực tiếp.
- Tài liệu không kiểm tra được nguồn.
- Trích dẫn thứ cấp khi có thể dùng nguồn gốc.
```

---

## 4. Chủ đề khoa học bắt buộc phải có trong thư viện

RAG nên bao phủ tối thiểu các nhóm tri thức sau:

### 4.1. Nền tảng địa thống kê

```text
- Spatial autocorrelation.
- Stationarity.
- Isotropy/anisotropy.
- Experimental variogram.
- Theoretical variogram models: Spherical, Exponential, Gaussian, Matern nếu có.
- Nugget, partial sill, sill, range, practical range.
- Kriging variance và ý nghĩa giới hạn của nó.
- Ordinary Kriging, Universal Kriging, Regression Kriging, Co-kriging.
```

### 4.2. Regression Kriging

```text
- Quy trình đúng: regression trend -> residual -> variogram residual -> kriging residual -> trend + residual.
- Điều kiện phần dư cần kiểm tra.
- Không gian hóa sai số hồi quy.
- Sự khác nhau giữa RK và regression-only/OK/UK.
- Khi RK không nên dùng.
- Nguy cơ leakage khi fit variogram/CV sai cách.
```

### 4.3. Variogram modeling

```text
- Cách chọn cutoff, lag width.
- Số cặp điểm tối thiểu trong lag bin.
- Giới hạn range hợp lý so với extent/cutoff/mean nearest-neighbor distance.
- Cách phát hiện range bị fit ép.
- Cách đánh giá nugget/sill cao.
- Manual vs auto variogram fitting.
- Anisotropy và directional variogram.
- Outlier effect lên variogram.
```

### 4.4. Cross-validation

```text
- Random CV.
- Spatial/block CV.
- Spatial k-means CV.
- Leave-location-out.
- Khi random CV quá lạc quan.
- Khi spatial CV phù hợp cho bản đồ.
- Refit variogram inside CV fold để tránh leakage.
- Metrics: ME, RMSE, MAE, R²_pred, NRMSE, RPD, RPIQ, NSE.
- Prediction interval coverage nếu có uncertainty.
```

### 4.5. Digital Soil Mapping và biến phụ trợ

```text
- DEM, slope, aspect, curvature.
- NDVI/remote sensing.
- Climate/rainfall như CHIRPS.
- Soil type/geology/landform.
- PCA covariates PC1-PCn.
- Multicollinearity và dimension reduction.
- Random Forest, XGBoost, GAM, Linear Regression trong DSM.
- Khi covariates không giúp cải thiện RK.
```

### 4.6. Bản đồ dinh dưỡng đất

```text
- pH.
- Humus/Organic Matter/SOC.
- CEC.
- N tổng số.
- P dễ tiêu.
- K dễ tiêu/trao đổi.
- Ca, Mg, S.
- Vi lượng: B, Zn, Cu, Mn, Fe.
- EC/salinity.
- Phân cấp nông học và ngưỡng đánh giá.
- Rủi ro khi class accuracy thấp nhưng RMSE có vẻ ổn.
```

---

## 5. Metadata bắt buộc cho mỗi tài liệu

Mỗi tài liệu trong RAG phải có metadata dạng JSON/YAML/CSV, tối thiểu:

```json
{
  "doc_id": "unique_id",
  "title": "...",
  "authors": ["..."],
  "year": 2020,
  "source_type": "book | peer_reviewed_paper | guideline | report | thesis | documentation",
  "journal_or_publisher": "...",
  "doi": "...",
  "url": "...",
  "access_date": "YYYY-MM-DD",
  "language": "en | vi | other",
  "topic_tags": ["variogram", "regression_kriging", "spatial_cv"],
  "soil_indicators": ["pH", "P", "K"],
  "geography": "...",
  "method_tags": ["OK", "RK", "RF", "GAM"],
  "quality_level": "core | supporting | weak | exclude",
  "license_or_access_note": "...",
  "notes": "short summary"
}
```

Không đưa tài liệu vào nhóm `core` nếu:

```text
- Không rõ nguồn.
- Không có tác giả/năm.
- Không liên quan trực tiếp.
- Không kiểm tra được DOI/URL.
- Là nội dung quảng cáo hoặc blog không phản biện.
```

---

## 6. Cấu trúc thư mục đề xuất

Đề xuất nhưng có thể điều chỉnh theo dự án:

```text
knowledge/
  README.md
  metadata/
    sources.csv
    sources.json
    topic_taxonomy.json
  library/
    geostatistics/
    regression_kriging/
    digital_soil_mapping/
    variogram/
    cross_validation/
    uncertainty/
    soil_nutrients/
    covariates/
  notes/
    summaries/
    extracted_claims/
    evidence_cards/
  prompts/
    rag_system_prompt.md
    rag_query_prompt.md
    evidence_check_prompt.md
    report_citation_prompt.md
  index/
    chunks.jsonl
    embeddings_manifest.json
```

Nếu chưa tích hợp embedding thật, vẫn có thể tạo `metadata`, `summaries`, `evidence_cards` trước.

---

## 7. Evidence card cho từng claim

Mỗi luận điểm khoa học quan trọng nên được lưu thành evidence card:

```json
{
  "claim_id": "variogram_range_cutoff_001",
  "claim": "Practical range close to cutoff may indicate weak constraint or over-smoothing risk.",
  "applies_to": ["variogram", "regression_kriging"],
  "evidence_sources": ["doc_id_1", "doc_id_2"],
  "strength": "strong | moderate | weak",
  "conditions": "Only when experimental variogram does not reach sill clearly.",
  "limitations": "Thresholds depend on sampling design and soil process scale.",
  "recommended_action": "Review interactive variogram; compare constrained range; do not accept automatically.",
  "not_allowed_action": "Do not force grade good only because RMSE is low."
}
```

RAG nên trả về claim + nguồn + điều kiện áp dụng, không chỉ trả về đoạn văn rời rạc.

---

## 8. RAG phục vụ workflow hiện tại như thế nào

RAG nên được dùng ở các điểm:

```text
1. Trước khi chạy: kiểm tra data readiness và profile của chỉ tiêu.
2. Sau run_result.json: giải thích warnings/recommendations dựa trên nguồn.
3. Khi tạo ai_decision.json: đề xuất tham số có căn cứ.
4. Khi validator kiểm tra: đối chiếu đề xuất với safety rules.
5. Khi compare runs: giải thích vì sao không chọn RMSE thấp nhất.
6. Khi viết final report: trích dẫn nguồn cho các kết luận khoa học.
```

RAG không được:

```text
- Tự sửa POINT_FILE, raster, CRS.
- Xóa điểm mẫu.
- Tắt CV.
- Tạo uncertainty giả.
- Đưa ra threshold cứng nếu nguồn chỉ nói phụ thuộc ngữ cảnh.
- Trích dẫn nguồn không tồn tại.
```

---

## 9. Schema output của truy vấn RAG

Khi agent hỏi RAG, kết quả nên có dạng:

```json
{
  "query": "...",
  "answer": "...",
  "confidence": "low | medium | high",
  "evidence": [
    {
      "doc_id": "...",
      "title": "...",
      "year": 2020,
      "source_type": "peer_reviewed_paper",
      "relevance": "high",
      "used_for": "variogram range interpretation",
      "quote_or_paraphrase": "...",
      "doi_or_url": "..."
    }
  ],
  "limitations": ["..."],
  "recommended_actions": ["..."],
  "do_not_do": ["..."]
}
```

Nếu không có nguồn đủ mạnh, trả lời:

```json
{
  "confidence": "low",
  "answer": "Không đủ nguồn trong thư viện để kết luận chắc chắn.",
  "recommended_actions": ["Cần bổ sung tài liệu hoặc chuyên gia xem thủ công."]
}
```

---

## 10. Prompt system cho RAG tương lai

Tạo hoặc đề xuất file:

```text
knowledge/prompts/rag_system_prompt.md
```

Nội dung phải nhấn mạnh:

```text
Bạn là RAG assistant cho Regression Kriging và Digital Soil Mapping.
Bạn chỉ được trả lời dựa trên tài liệu trong thư viện hoặc nguồn được kiểm chứng.
Bạn không được tạo citation giả.
Bạn phải phân biệt rõ bằng chứng mạnh, trung bình, yếu.
Bạn phải nêu điều kiện áp dụng của mỗi khuyến nghị.
Bạn không được chọn mô hình chỉ vì RMSE thấp nhất.
Bạn không được đề xuất sửa dữ liệu gốc, CRS hoặc tắt cross-validation.
Nếu thiếu nguồn, hãy nói thiếu nguồn.
```

---

## 11. Prompt query cho đánh giá run_result

Tạo hoặc đề xuất file:

```text
knowledge/prompts/rag_query_prompt.md
```

Nội dung mẫu:

```text
Dưới đây là run_result.json của một lần chạy Regression Kriging.

Hãy dùng thư viện tri thức để:
1. Giải thích các cảnh báo chính.
2. Đánh giá variogram có hợp lý không.
3. Đánh giá cross-validation.
4. Đánh giá RK có cải thiện so với baseline không.
5. Đề xuất hành động tiếp theo.
6. Trích dẫn nguồn liên quan.

Không chọn mô hình chỉ vì RMSE thấp nhất.
Không đề xuất thay đổi ngoài whitelist.
Không tạo citation giả.

Input:
{{RUN_RESULT_JSON}}

Output JSON:
{
  "scientific_assessment": "...",
  "evidence": [],
  "decision_hint": "ACCEPT | RERUN | MANUAL_REVIEW | REJECT",
  "recommended_parameters": {},
  "limitations": [],
  "human_review_required": true
}
```

---

## 12. Kế hoạch triển khai theo giai đoạn

### Giai đoạn 1: Thiết kế thư viện tri thức

```text
- Tạo cấu trúc knowledge/.
- Tạo schema metadata.
- Tạo taxonomy chủ đề.
- Tạo prompt RAG.
- Chưa cần embedding.
```

### Giai đoạn 2: Thu thập tài liệu cốt lõi

```text
- Tìm sách/paper/guideline nền tảng.
- Kiểm tra DOI/URL/publisher.
- Lưu metadata.
- Tóm tắt ngắn từng tài liệu.
- Gắn tag chủ đề.
```

### Giai đoạn 3: Evidence cards

```text
- Tạo claim có điều kiện áp dụng.
- Liên kết claim với nguồn.
- Gắn claim vào evaluation rules hiện tại.
- Đánh dấu strength/limitations.
```

### Giai đoạn 4: Index và retrieval

```text
- Chunk tài liệu.
- Tạo chunks.jsonl.
- Nếu có embedding tool được phép, tạo embedding index.
- Nếu chưa có embedding, dùng metadata + keyword retrieval trước.
```

### Giai đoạn 5: Tích hợp file-based API

```text
- R engine xuất run_result.json như hiện tại.
- RAG đọc run_result.json.
- RAG xuất rag_assessment_<run_id>.json.
- AI decision đọc cả run_result và rag_assessment.
- Validator vẫn kiểm soát đề xuất.
```

### Giai đoạn 6: Report có trích dẫn

```text
- Final report thêm mục "Cơ sở khoa học".
- Mỗi khuyến nghị quan trọng có nguồn.
- Không trích dài quá mức.
- Không citation giả.
```

---

## 13. Tiêu chí hoàn thành giai đoạn lập kế hoạch

Công việc lập kế hoạch được xem là hoàn thành khi có:

```text
1. Đề xuất cấu trúc knowledge/.
2. Schema metadata cho nguồn tài liệu.
3. Taxonomy chủ đề.
4. Prompt system/query cho RAG.
5. Quy tắc chọn nguồn khoa học.
6. Quy tắc chống citation giả.
7. Quy tắc kết nối RAG với run_result.json.
8. Kế hoạch triển khai theo giai đoạn.
9. Rủi ro và giới hạn.
10. Danh sách việc không được làm.
```

---

## 14. Rủi ro cần cảnh báo

Khi thiết kế RAG, phải nêu rõ:

```text
- RAG không thay thế chuyên gia địa thống kê.
- Nguồn khoa học có thể phụ thuộc vùng đất, loại đất, cây trồng, khí hậu và phương pháp lấy mẫu.
- Threshold từ paper này không tự động áp dụng cho vùng khác.
- Paper về DSM có thể dùng ML/CV khác với workflow hiện tại.
- Citation sai nguy hiểm hơn không citation.
- RAG có thể làm agent tự tin quá mức nếu metadata/source quality kém.
```

---

## 15. Không được làm

Không được:

```text
- Tải hoặc lưu nội dung có bản quyền trái phép.
- Tạo citation giả.
- Dùng blog yếu làm bằng chứng mạnh.
- Trộn lẫn nguồn đã kiểm chứng và nguồn chưa kiểm chứng.
- Cho RAG quyền sửa raw data.
- Cho RAG quyền bypass validator.
- Cho RAG quyền tắt cross-validation.
- Cho RAG quyết định final map chỉ dựa trên một đoạn trích.
```

---

## 16. Output mong muốn của agent sau khi chạy prompt này

Trả lời bằng tiếng Việt có dấu, gồm:

```text
1. Có nên làm RAG không và vì sao.
2. RAG nên phục vụ bước nào trong workflow RK hiện tại.
3. Cấu trúc thư mục knowledge/ đề xuất.
4. Metadata schema.
5. Chủ đề tài liệu cần thu thập.
6. Prompt RAG cần tạo.
7. File-based API giữa run_result và RAG.
8. Các rủi ro khoa học.
9. Kế hoạch triển khai từng giai đoạn.
10. Những việc không làm ở giai đoạn đầu.
```

Nếu người dùng chỉ yêu cầu lập kế hoạch, không triển khai code hoặc tải tài liệu.
## 17. Quy tr�nh khi ngu?i d�ng c� quy?n truy c?p t�i li?u b?n quy?n

N?u ngu?i d�ng l� sinh vi�n/nh� nghi�n c?u c� quy?n t?i t�i li?u h?p ph�p, agent v?n kh�ng du?c bypass paywall ho?c t? c�o tr�i ph�p. Thay v�o d�:

```text
1. Hu?ng d?n ngu?i d�ng t? t?i t�i li?u b?ng quy?n truy c?p h?p ph�p.
2. Ngu?i d�ng d?t PDF/t?p v�o knowledge/library/.
3. Ch?y .\run_rag_inventory.ps1 d? t?o inventory v� draft metadata.
4. Ngu?i d�ng/agent ki?m ch?ng DOI, t�c gi?, nam, license note.
5. N?u du?c ph�p index n?i b?, ch?y .\run_rag_build_local_index.ps1.
6. Kh�ng commit PDF, raw text, chunks local ho?c vector index v�o Git.
7. Khi b�o c�o, ch? tr�ch d?n doc_id/DOI/URL d� ki?m ch?ng; kh�ng tr�ch d�i full text.
```

C�c file h? tr?:

```text
knowledge/LOCAL_LIBRARY_WORKFLOW.md
run_rag_inventory.ps1
run_rag_build_local_index.ps1
scripts/rag_inventory_library.R
scripts/rag_build_local_index.R
```
