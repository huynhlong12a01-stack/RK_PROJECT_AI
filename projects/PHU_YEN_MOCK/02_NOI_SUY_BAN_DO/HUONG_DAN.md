# PHU_YEN_MOCK — Quy trình 2 an toàn

Đây là bước kiểm thử nội suy bằng chỉ tiêu lab tổng hợp. **Không dán kết quả lab thật và không chạy riêng script/BAT nội suy.** Từ thư mục gốc dự án, chỉ chạy:

`00_CHAY_MOCK_AN_TOAN.bat`

## Dữ liệu và cấu hình

- `..\THONG_SO_DU_AN.yml` là nguồn duy nhất cho CRS, GEE project, lưới 30 m, `covariate_support_buffer_m` và ngày covariates.
- Orchestrator tự tạo `sample_actual.csv` tổng hợp và metadata tương ứng; các giá trị này không phải kết quả phòng thí nghiệm.
- PC1–PC5/PCA reference và Soil Type được tái sử dụng từ Quy trình 1.

Quy trình ưu tiên tái sử dụng hoặc tái tạo PCA cục bộ từ raw covariates Quy trình 1 đã kiểm chứng; `sample_actual` không được gửi ra ngoài. Chỉ khi raw thật sự thiếu, GEE mới là phương án dự phòng với bounding envelope ROI cộng `covariate_support_buffer_m`; miền tải này không phải prediction domain và phải qua privacy/hash gate.

Quy trình 2 kiểm lại raw provenance và PCA lineage của Quy trình 1 trước khi đọc kết quả lab. Trạng thái STALE/UNVERIFIED sẽ chặn nội suy; hãy chạy lại Quy trình 1, không chép hoặc sửa file trong `_NOI_BO` để vượt cổng.

- Mọi điểm và chỉ tiêu của mock bị cấm dùng cho train, calibration, outer test, knowledge hoặc sản xuất.

## Nội dung được kiểm thử

Orchestrator kiểm tra support/AOA, chạy các nhánh `PC_ONLY` và `PC_PLUS_SOIL`, kiểm tra hard failures và chuyển toàn bộ sản phẩm vào:

`02_KET_QUA/MOCK_SYNTHETIC_NOT_FOR_USE`

`maps_accepted` luôn phải là `false`. Nested spatial CV chỉ là kiểm định nội bộ; residual kriging standard deviation không phải total predictive uncertainty; bản đồ hàm lượng tổng hợp không phải bản đồ khuyến cáo phân bón.

Đọc `MOCK_RUN_MANIFEST.json` và `MOCK_QA_GATE.json` trong vùng cách ly để kiểm trạng thái. Không sao chép bất kỳ raster, bảng hoặc mô hình nào ra các thư mục `maps`, `reports`, `tables` thông thường.

Hướng dẫn cho dữ liệu thật: `D:\RK_R_Project\docs\04_NOI_SUY_VA_TAO_BAN_DO.md`.

- Trước preflight, ứng dụng kiểm `soil_lineage_ready`; `Unmapped` (ngoài coverage) luôn tách khỏi `Other` (lớp đã map nhưng thiếu mẫu).
