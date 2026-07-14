# {{PROJECT_ID}}

Dự án có ba giai đoạn nối tiếp. Người dùng chỉ thao tác trong các thư mục `00`, `01`, `02`; không chỉnh `_NOI_BO`.

## Bước 0 — Xác lập ROI_field_area

Chọn một trong hai cách:

- Đã có ranh giới mía: đặt `00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson`.
- Chưa có ranh giới: đặt `roi_search.geojson`, tạo `sugarcane_labels.csv` có cả `label=1` và `label=0` đã kiểm chứng, rồi hoàn thiện `interpretation.yml`.

Khi giải đoán, phải xác nhận lịch thời vụ địa phương và chỉ dùng các kỳ ảnh đã hoàn tất. Kết quả `roi_field_area_candidate` là vùng ứng viên; review thủ công trên ảnh và bằng kiến thức thực địa, sau đó lưu bản đã duyệt thành `roi_field_area.geojson` và chạy lại Bước 0.

Thư viện AKS chỉ là `positive_reference_only`, không phải mô hình nhị phân tiền huấn luyện. Nó không thay thế nhãn dương/âm địa phương và không được dùng trong fold chọn ngưỡng hoặc outer test.

## Quy trình 1 — Thiết kế lấy mẫu

Đặt `soil_type.geojson` nếu có và kiểm tra `sampling.yml` trong `01_THIET_KE_LAY_MAU/01_DAU_VAO`. Bước 0 cung cấp ROI đã duyệt.

Với `clhs_backend: auto`, ứng dụng ưu tiên gói CRAN `clhs`:

- REDUCED là lõi `clhs_core` nếu backend gốc chạy thành công;
- FULL là REDUCED cộng `spatial_infill` và `short_lag`;
- toàn bộ FULL là thiết kế lai, không phải cLHS thuần;
- nếu fallback, QA ghi `python_clhs_like` và lõi `lhs_core`.

FULL và REDUCED không được xem là có chất lượng tương đương. Lưới 10 m không nâng độ phân giải gốc của covariates.

## Quy trình 2 — Nội suy

Sau thực địa, cập nhật `02_NOI_SUY_BAN_DO/01_DAU_VAO/sample_actual.csv`:

- mỗi mẫu một dòng;
- `code`, `lat`, `lon` là GPS thực tế;
- các cột sau là kết quả lab dạng số và để trống khi chưa có;
- mọi kết quả được xem là giá trị trung bình của mẫu, không tách tầng.

Xác nhận phương pháp/đơn vị trong `indicator_metadata.yml`, rồi chạy `CHAY_NOI_SUY_BAN_DO.bat`. Điểm ngoài ROI chỉ được dùng sau kiểm tra target population, support và AOA; chúng không tự động là validation set. Bản đồ cuối mask theo `ROI_field_area`.

## Kiểm tra trạng thái

Nhấp `0_KIEM_TRA_DU_AN.bat`. Dòng trạng thái cho biết đang chờ ROI/nhãn, chờ review vùng ứng viên, chờ thiết kế mẫu, chờ lab hay sẵn sàng nội suy.

Nếu đổi ROI, CRS, thời gian ảnh hoặc lịch thời vụ sau khi đã tạo sản phẩm trung gian, hãy tạo phiên bản dự án mới hoặc chạy lại có kiểm soát.
