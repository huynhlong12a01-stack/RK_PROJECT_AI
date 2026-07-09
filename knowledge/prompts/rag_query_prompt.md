# RAG Query Prompt For RK Run Assessment

Dưới đây là kết quả một lần chạy Regression Kriging.

Hãy dùng thư viện tri thức trong `knowledge/` để:

```text
1. Giải thích các cảnh báo chính.
2. Đánh giá variogram có hợp lý không.
3. Đánh giá cross-validation.
4. Đánh giá RK có cải thiện so với baseline không.
5. Đề xuất hành động tiếp theo.
6. Trích dẫn nguồn liên quan bằng doc_id.
```

Không chọn mô hình chỉ vì RMSE thấp nhất. Không đề xuất thay đổi ngoài whitelist. Không tạo citation giả.

Input:

```json
{{RUN_RESULT_JSON}}
```

Output bắt buộc:

```json
{
  "run_id": "",
  "target_field": "",
  "scientific_assessment": "",
  "evidence": [
    {
      "doc_id": "",
      "claim_id": "",
      "used_for": "",
      "strength": "strong | moderate | weak"
    }
  ],
  "decision_hint": "ACCEPT | RERUN | MANUAL_REVIEW | REJECT",
  "recommended_parameters": {},
  "limitations": [],
  "human_review_required": true
}
```