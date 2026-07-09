# Evidence Check Prompt

Bạn đang kiểm tra một luận điểm khoa học trước khi đưa vào RAG evidence card.

Hãy kiểm tra:

```text
1. Luận điểm có rõ ràng và kiểm chứng được không.
2. Nguồn có trong knowledge/metadata/sources.csv không.
3. Nguồn có đủ mạnh cho luận điểm này không.
4. Điều kiện áp dụng là gì.
5. Giới hạn của luận điểm là gì.
6. Có nguy cơ áp dụng sai ngữ cảnh không.
7. Có tạo citation giả hoặc suy diễn quá mức không.
```

Output:

```json
{
  "valid_evidence_card": true,
  "claim_strength": "strong | moderate | weak",
  "problems": [],
  "required_fixes": [],
  "safe_to_use_in_report": true
}
```