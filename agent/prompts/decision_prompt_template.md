Dưới đây là kết quả một lần chạy Regression Kriging và ngữ cảnh RAG cục bộ nếu có.

Hãy đánh giá kết quả và quyết định:

- ACCEPT nếu kết quả đủ tốt.
- RERUN nếu nên chạy lại với thông số khác.
- MANUAL_REVIEW nếu cần chuyên gia xem variogram/bản đồ/dữ liệu.
- REJECT nếu kết quả không đủ tin cậy.

Không được chọn mô hình chỉ vì RMSE thấp nhất.

Cần cân bằng:

- Outer spatial CV R²_pred, RMSE, MAE, ME trên đơn vị gốc và phân phối qua repeats.
- Regression-only / Ordinary Kriging / Regression Kriging baseline.
- Transform đã dùng, bias correction nếu có.
- Nugget/Sill, range, range_hit_max, practical range/cutoff.
- Class accuracy và severe misclassification nếu chỉ tiêu có phân cấp.
- AOA, clipping; uncertainty chỉ được đánh giá nếu calibrated total predictive intervals. Residual STD chỉ là thông tin.
- Cảnh báo dữ liệu, outlier, sampling, CRS/raster/covariate.
- Evidence cards/RAG context nội bộ nếu được cung cấp.
- hard_failures, strict_outer_cv và leakage_guard.
- variogram singular, directional anisotropy, range_hit_max và pure nugget.
- prediction_method; nếu là regression_only_pure_nugget_fallback thì không được diễn giải output như RK có cải thiện không gian.
- Tên/profile chỉ tiêu có mơ hồ về phương pháp hoặc đơn vị hay không.


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
