# Evidence Cards

Evidence card là đơn vị tri thức nhỏ dùng cho RAG. Mỗi card ghi một luận điểm khoa học, nguồn chứng cứ, điều kiện áp dụng, giới hạn và hành động khuyến nghị.

Không tạo evidence card nếu chưa có nguồn đủ rõ trong `knowledge/metadata/sources.csv`.

Tên file đề xuất:

```text
<topic>_<short_claim_id>.json
```