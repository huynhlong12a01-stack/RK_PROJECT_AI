Dưới đây là kết quả nhiều lần chạy Regression Kriging cho cùng một chỉ tiêu.

Hãy chọn phương án đáng tin nhất, không nhất thiết là phương án có RMSE thấp nhất.

Ưu tiên:

1. R²_pred dương.
2. ME gần 0.
3. RK cải thiện so với regression-only và OK/IDW.
4. Nugget/Sill không quá cao.
5. Range không chạm giới hạn và không quá dài so với ROI/cutoff.
6. Cảnh báo ít hơn.
7. Class accuracy tốt nếu chỉ tiêu có phân cấp.
8. Uncertainty hợp lý.

Input:
{{RUN_HISTORY_JSON}}

Output:

```json
{
  "selected_run_id": "...",
  "decision": "FINAL_ACCEPT | MANUAL_REVIEW | REJECT",
  "reason": "...",
  "why_not_lowest_rmse": "...",
  "final_notes": "...",
  "human_review_required": true
}
```