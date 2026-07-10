Dưới đây là kết quả một lần chạy Regression Kriging và ngữ cảnh RAG cục bộ nếu có.

Hãy đánh giá kết quả và quyết định:

- ACCEPT nếu kết quả đủ tốt.
- RERUN nếu nên chạy lại với thông số khác.
- MANUAL_REVIEW nếu cần chuyên gia xem variogram/bản đồ/dữ liệu.
- REJECT nếu kết quả không đủ tin cậy.

Không được chọn mô hình chỉ vì RMSE thấp nhất.

Cần cân bằng:

- R²_pred, RMSE, MAE, ME trên đơn vị gốc.
- Regression-only / Ordinary Kriging / Regression Kriging baseline.
- Transform đã dùng, bias correction nếu có.
- Nugget/Sill, range, range_hit_max, practical range/cutoff.
- Class accuracy và severe misclassification nếu chỉ tiêu có phân cấp.
- Uncertainty/residual kriging STD nếu có.
- Cảnh báo dữ liệu, outlier, sampling, CRS/raster/covariate.
- Evidence cards/RAG context nội bộ nếu được cung cấp.

Nếu transform = log1p, hãy nhớ: Regression-only, OK và RK đều phải được so sánh bằng metric trên đơn vị gốc sau back-transform. OK baseline có thể được fit trên log1p(target), không phải nhất thiết trên giá trị gốc.

Input run_result JSON:
{{RUN_RESULT_JSON}}

RAG context JSON:
{{RAG_CONTEXT_JSON}}

Evidence summaries:
{{EVIDENCE_SUMMARIES}}

Whitelist parameters:
{{WHITELIST_PARAMETERS}}

Safety limits:
{{SAFETY_LIMITS}}

Output bắt buộc theo schema, không viết văn bản ngoài JSON:

```json
{
  "decision": "ACCEPT | RERUN | MANUAL_REVIEW | REJECT",
  "confidence": "low | medium | high",
  "reason": "...",
  "next_parameters": {},
  "must_keep": {},
  "stop_condition": {},
  "human_review_required": true
}
```