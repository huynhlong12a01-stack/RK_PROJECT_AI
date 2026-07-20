# PHU_YEN_MOCK — Bước 0 an toàn

Đây là dự án kiểm thử bằng dữ liệu tổng hợp, không phải dự án giải đoán mía sản xuất. **Không chạy riêng script hoặc BAT của từng giai đoạn.** Từ thư mục gốc dự án, chỉ chạy:

`00_CHAY_MOCK_AN_TOAN.bat`

## Cấu hình và ROI

`..\THONG_SO_DU_AN.yml` là nguồn duy nhất của mock cho CRS, GEE project, lưới 30 m, `covariate_support_buffer_m` và ngày covariates. Không sửa các bản sao của các giá trị này trong `interpretation.yml`, `sampling.yml` hoặc `_NOI_BO`.

Orchestrator an toàn chuẩn bị và kiểm tra nguồn canonical:

`01_DAU_VAO/roi_field_area.geojson`

Quy trình thiết kế mẫu và nội suy đọc trực tiếp ROI canonical này. Không có `roi.geojson` tương thích và không sao chép ROI sang giai đoạn khác.

## Phạm vi kiểm thử

Bước 0 của mock chỉ kiểm luồng hình học đi vào thiết kế mẫu và nội suy. Nó không đánh giá độ chính xác phân loại mía từ Sentinel-1/2, không tạo bằng chứng rằng vùng tổng hợp là mía và không được dùng làm tập tham chiếu.

`APPROVED_FOR_SAMPLE_DESIGN` trong mock chỉ là cổng kỹ thuật. Với dự án thật chưa có ROI, phải dùng `roi_search.geojson`, sao chép template thành `sugarcane_labels.csv` có cả nhãn dương/âm tại địa phương, xác nhận phenology và review ROI ứng viên.

Lưới 30 m là lưới tính toán/xuất của mock. Nó không biến CHIRPS, SRTM hoặc TWI thành dữ liệu có support thực 30 m.

## Kết quả

Mọi kết quả của mock chỉ được giữ trong vùng cách ly do `00_CHAY_MOCK_AN_TOAN.bat` quản lý. Không đưa ROI, nhãn hoặc đặc trưng tổng hợp của mock vào knowledge, train, calibration, outer test hoặc dự án sản xuất.

Hướng dẫn cho dự án thật: [Bước 0 — xác lập vùng mía](../../../docs/templates/WORKFLOW0_GUIDE.md).
