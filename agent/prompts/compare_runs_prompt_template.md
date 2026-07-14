Dưới đây là kết quả nhiều lần chạy Regression Kriging cho cùng một chỉ tiêu.

Hãy chọn phương án đáng tin nhất, không nhất thiết là phương án có RMSE thấp nhất.

Ưu tiên:

1. Có outer held-out spatial CV hợp lệ (không phải independent field validation), không có hard failure và R²_pred dương.
2. ME gần 0.
3. RK cải thiện so với regression-only và OK/IDW.
4. Nugget/Sill không quá cao.
5. Range không chạm giới hạn và không quá dài so với extent/cutoff.
6. Variogram không singular/pure nugget; AOA và clipping trong giới hạn. Run dùng regression_only_pure_nugget_fallback không được xem là RK thành công chỉ vì RMSE tốt.
7. Class accuracy tốt nếu chỉ tiêu có phân cấp.
8. Uncertainty chỉ được tính lợi thế nếu total predictive intervals đã calibrated.

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
