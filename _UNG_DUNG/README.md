# Khu vực nội bộ của ứng dụng

Người dùng không cần sửa các tệp trong thư mục này.

- engine/: lõi R dùng chung, cấu hình đánh giá và các script tạo dự án.
- tools/: công cụ kiểm tra phụ thuộc và thư viện tài liệu/knowledge.
- runtime/: báo cáo tạm của các công cụ; Git chỉ giữ tệp đánh dấu thư mục.

Các thao tác thông thường phải bắt đầu từ CREATE_NEW_PROJECT.bat hoặc các tệp BAT bên trong từng dự án. Dữ liệu đầu vào và kết quả của người dùng nằm trong projects/, còn dữ liệu nền dùng chung nằm trong shared_data/.
