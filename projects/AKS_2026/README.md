# AKS_2026

Dự án có ba giai đoạn nối tiếp. Người dùng thao tác trong các thư mục `00`, `01`, `02`; không chỉnh `_NOI_BO`.

## 0. Xác lập vùng mía

AKS đã được cung cấp ranh giới vùng mía đáng tin cậy. Chạy `00_XAC_LAP_VUNG_MIA/CHAY_XAC_LAP_VUNG_MIA.bat` để kiểm tra, ghi provenance và chuẩn hóa thành `ROI_field_area` cho hai quy trình sau.

Ranh giới AKS chỉ tạo gói `positive_reference_only`: có bằng chứng dương tính nhưng không có lớp không-mía đã kiểm chứng. Đây không phải mô hình nhị phân tiền huấn luyện để áp trực tiếp sang huyện/tỉnh khác.

Với dự án chưa có ROI, cần `roi_search.geojson`, nhãn địa phương có cả `label=1`/`label=0`, xác nhận lịch thời vụ và review thủ công `roi_field_area_candidate`.

## 1. Thiết kế lấy mẫu

Trong `01_THIET_KE_LAY_MAU/01_DAU_VAO`, kiểm tra `sampling.yml` và thêm `soil_type.geojson` nếu có. ROI được lấy từ Bước 0.

Nhấp `CHAY_THIET_KE_LAY_MAU.bat`:

- REDUCED là lõi `clhs_core` khi gói CRAN `clhs` chạy thành công;
- FULL là REDUCED cộng `spatial_infill` và `short_lag`;
- toàn bộ FULL là thiết kế lai, không phải cLHS thuần;
- nếu fallback, QA ghi `python_clhs_like` và `lhs_core`.

REDUCED là tập con của FULL nhưng không được bảo đảm chất lượng tương đương. Lưới 10 m không nâng độ phân giải gốc của CHIRPS/DEM/TWI.

## 2. Nội suy và tạo bản đồ

Cập nhật `02_NOI_SUY_BAN_DO/01_DAU_VAO/sample_actual.csv` bằng GPS thực tế và kết quả lab dạng số. Mỗi dòng là kết quả trung bình của mẫu; không tách tầng đất. Xác nhận phương pháp/đơn vị tại `indicator_metadata.yml`.

Điểm ngoài ROI được đánh giá target population, support, dissimilarity/AOA và sensitivity; chúng không tự bị loại và không tự động là validation set. Nhấp `CHAY_NOI_SUY_BAN_DO.bat`; bản đồ cuối mask theo `ROI_field_area`.

## Kiểm tra trạng thái

Nhấp `0_KIEM_TRA_DU_AN.bat` để biết đang chờ Bước 0, thiết kế, GPS/lab hay nội suy. Tài liệu đầy đủ: [docs/00_MUC_LUC.md](../../docs/00_MUC_LUC.md).
