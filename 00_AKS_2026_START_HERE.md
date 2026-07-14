# Bắt đầu với AKS_2026

1. Nhấp `projects/AKS_2026/0_KIEM_TRA_DU_AN.bat` để xem trạng thái.
2. Xác lập vùng mía:
   - AKS_2026 đã có ranh giới tin cậy; đặt/giữ bản đã duyệt là `00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson`, rồi nhấp `CHAY_XAC_LAP_VUNG_MIA.bat`.
   - Nếu một dự án khác chưa có ranh giới, dùng `roi_search.geojson` cùng `sugarcane_labels.csv` có cả mía và không-mía chắc chắn. ROI ứng viên phải được review rồi lưu lại thành `roi_field_area.geojson`.
3. Thiết kế mẫu: kiểm tra `sampling.yml`, thêm `soil_type.geojson` nếu có, rồi nhấp `01_THIET_KE_LAY_MAU/CHAY_THIET_KE_LAY_MAU.bat`.
4. Chọn FULL hoặc REDUCED để đi thực địa và lưu GPS thật. REDUCED là phương án ít nguồn lực hơn, không được bảo đảm tương đương FULL.
5. Nội suy: dán tọa độ thực tế và kết quả lab vào `02_NOI_SUY_BAN_DO/01_DAU_VAO/sample_actual.csv`; xác nhận phương pháp/đơn vị trong `indicator_metadata.yml`, rồi nhấp `CHAY_NOI_SUY_BAN_DO.bat`.

`sample_actual.csv` là nơi duy nhất nhập vị trí thực tế và kết quả phân tích. Mỗi dòng là một giá trị trung bình của mẫu; không tạo file tầng đất hoặc file kết quả lab riêng.

ROI hiện có của AKS chỉ tạo thư viện tham chiếu dương tính. Nó không phải mô hình phân loại mía/không-mía đã được kiểm định để chuyển thẳng sang địa phương khác.

Hướng dẫn đầy đủ: [docs/00_MUC_LUC.md](docs/00_MUC_LUC.md).
