Dưới đây là kết quả một lần chạy Regression Kriging.

Hãy đánh giá kết quả và quyết định:

- ACCEPT nếu kết quả đủ tốt.
- RERUN nếu nên chạy lại với thông số khác.
- MANUAL_REVIEW nếu cần chuyên gia xem variogram/bản đồ.
- REJECT nếu kết quả không đủ tin cậy.

Không được chọn mô hình chỉ vì RMSE thấp nhất.

Nếu range quá lớn, nugget/sill quá cao, R²_pred âm, hoặc RK không cải thiện so với baseline thì phải cảnh báo.

Input JSON:
{{RUN_RESULT_JSON}}

Whitelist parameters:
{{WHITELIST_PARAMETERS}}

Safety limits:
{{SAFETY_LIMITS}}

Output bắt buộc theo schema:

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