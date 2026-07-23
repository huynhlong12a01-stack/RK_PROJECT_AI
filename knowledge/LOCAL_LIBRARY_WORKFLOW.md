# Workflow thư viện tài liệu local

Phần này chỉ dành cho PDF/TXT/MD/HTML mà người dùng có quyền sử dụng. Không tải hoặc chia sẻ tài liệu có bản quyền trái phép.

## Hai corpus tách biệt

- Curated: metadata, tóm tắt tự viết và evidence cards trong repository. Dùng run_rag_build_curated_index.ps1.
- Local/private: tài liệu trong knowledge/library, bị Git ignore. Dùng inventory và local index khi thật sự cần đọc toàn văn.

Curated corpus là mặc định vì có DOI/URL và giới hạn sử dụng rõ. Local corpus không tự trở thành nguồn core.

## Quy trình local

1. Đặt tài liệu hợp pháp vào knowledge/library theo thư mục chủ đề.
2. Chạy:

       .\_UNG_DUNG\tools\run_rag_inventory.ps1

3. Mở knowledge/metadata/local_library_inventory.csv và kiểm tra title, tác giả, năm, DOI/URL, quyền sử dụng. needs_review không được xem là bằng chứng đã xác minh.
4. Tạo private chunks:

       .\_UNG_DUNG\tools\run_rag_build_local_index.ps1

5. Tra cứu file local cụ thể bằng cách truyền đường dẫn chunks nếu cần:

       .\_UNG_DUNG\tools\run_rag_query.ps1 -Query "variogram residual" -Chunks "knowledge/index/local_chunks/chunks.jsonl"

## Giới hạn

- PDF cần package pdftools trong R.
- DOCX có thể xuất hiện trong inventory nhưng builder chỉ hỗ trợ loại file mà log xác nhận đã đọc.
- Chunk local theo ký tự không thay page/heading citation.
- Kết quả lexical chỉ là danh sách ứng viên để kiểm tra.
- Không commit knowledge/library hoặc knowledge/index/local_chunks.
- Không trích dài toàn văn; luôn quay về DOI/URL và điều khoản nguồn.

## Khi nào cập nhật curated knowledge

Chỉ tạo evidence card sau khi metadata đã được xác minh và luận điểm có phạm vi/giới hạn rõ. Dùng run_rag_smoke_test.ps1 để kiểm tra source id, taxonomy và schema trước khi build lại curated index.
