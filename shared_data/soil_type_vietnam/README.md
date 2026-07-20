# Soil Type Việt Nam

Tệp dùng chung cục bộ: `shared_data/soil_type_vietnam/raw/VN_soil_type.geojson`. Ứng dụng đọc trường `Ma1` như biến phân loại danh nghĩa; mã số không mang ý nghĩa thứ bậc. Ô không được polygon phủ phải được ghi nhận bằng một mức thiếu riêng, không bị loại khỏi miền mẫu.

Tệp gốc có dung lượng lớn nên không đưa lên GitHub. Mã SHA-256 và trạng thái nguồn được lưu tại `provenance.yml`.

## Trạng thái nguồn

Người dùng đã cung cấp tệp nhưng hiện chưa có tên tổ chức phát hành, tên bộ dữ liệu, phiên bản, ngày truy cập và giấy phép. Vì vậy ứng dụng được phép xử lý cục bộ, nhưng không được tuyên bố đây là nguồn chính thức hoặc phát hành sản phẩm ra ngoài cho đến khi bổ sung đủ metadata nguồn và giấy phép.

Không chỉnh sửa trực tiếp tệp gốc. Khi thay dữ liệu, phải cập nhật `provenance.yml`, tính lại SHA-256 và chạy lại Workflow 1; Workflow 2 sẽ từ chối Soil Type không còn khớp lineage.
