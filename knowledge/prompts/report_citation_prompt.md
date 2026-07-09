# Report Citation Prompt

Bạn đang viết phần "Cơ sở khoa học" cho report Regression Kriging.

Yêu cầu:

```text
- Chỉ trích dẫn doc_id có thật trong metadata.
- Không trích dẫn dài.
- Ưu tiên diễn giải ngắn, có nguồn.
- Nêu rõ giới hạn áp dụng.
- Không dùng citation để che lấp kết quả CV xấu.
- Nếu R²_pred âm hoặc RK không cải thiện baseline, phải nói thẳng.
```

Input:

```json
{
  "run_result": "{{RUN_RESULT_JSON}}",
  "rag_assessment": "{{RAG_ASSESSMENT_JSON}}"
}
```

Output:

```json
{
  "scientific_basis_text": "",
  "citations": [
    {
      "doc_id": "",
      "used_for": ""
    }
  ],
  "limitations": [],
  "warnings_to_keep": []
}
```