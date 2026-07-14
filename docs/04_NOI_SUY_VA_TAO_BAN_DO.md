# Quy trình 2 — Nội suy và tạo bản đồ

## Điều kiện để bắt đầu

Quy trình 2 sử dụng lại sản phẩm của Quy trình 1. Trước khi chạy cần có:

- Bước 0 đã phê duyệt `ROI_field_area` và bản tương thích kỹ thuật của ROI còn hợp lệ;
- `sampling.yml` hợp lệ;
- PC1–PC5 của Quy trình 1;
- `pca_model_reference.json` được tạo từ cùng covariates của Quy trình 1;
- `sample_actual.csv` có mã, tọa độ và ít nhất một chỉ tiêu chứa kết quả số.
- `indicator_metadata.yml` có đúng phương pháp, đơn vị và `confirmed: true` cho chỉ tiêu cần chạy. Nếu chưa xác nhận, engine chỉ cho phép sản phẩm trạng thái nháp và khóa phân hạng/khuyến cáo.

Không cần ép vị trí thực tế trùng với `sample_cLHS`. Không cần xóa 22 điểm ngoài ROI của AKS_2026 chỉ vì chúng ở ngoài vùng; chúng được kiểm tra coverage và được ghi nhận trong QA.

## Cách chạy

Nhấp đúp `02_NOI_SUY_BAN_DO/CHAY_NOI_SUY_BAN_DO.bat`. Ứng dụng chạy lần lượt:

1. Chuẩn hóa `sample_actual.csv`, kiểm tra tọa độ, chỉ tiêu và trạng thái trong/ngoài ROI.
2. Kiểm tra PC1–PC5 tại từng mẫu.
3. Nếu điểm thiếu coverage, tạo vùng hỗ trợ, tải covariates Earth Engine bổ sung và chiếu chúng bằng **PCA reference đã đóng băng** từ Quy trình 1.
4. Nếu có Soil Type, xây biến phân loại; nhóm hiếm/không khớp được gom vào `Other`.
5. Kiểm tra schema giữa điểm và raster predictor.
6. Chạy riêng từng chỉ tiêu có kết quả.
7. Xuất bản đồ và báo cáo, sau đó mask toàn bộ GeoTIFF cuối về `ROI_field_area` đã duyệt.

## Hai nhánh mô hình

### `PC_ONLY`

Sử dụng PC1–PC5 làm covariates xu thế. Nhánh này luôn được chạy và là mốc so sánh khi đánh giá việc bổ sung Soil Type.

### `PC_PLUS_SOIL`

Chỉ chạy khi có `soil_type.geojson`. Mô hình dùng PC1–PC5 cùng các biến giả Soil Type. Mã nhóm đất không được đưa vào hồi quy như biến số liên tục.

Không mặc định `PC_PLUS_SOIL` tốt hơn. Chọn nhánh có bằng chứng tốt hơn qua spatial cross-validation, độ ổn định, cảnh báo ngoại suy và chẩn đoán residual/variogram.

## Vai trò của các điểm ngoài ROI

- Điểm có predictor đầy đủ có thể tham gia tập phát triển mô hình và các fold outer held-out. Chúng không tự động trở thành tập kiểm định thực địa độc lập.
- Mỗi điểm ngoài ROI phải được ghi rõ quan hệ với target population, trạng thái covariate support và kết quả AOA; không tự loại chỉ vì ngoài ROI, cũng không tự chấp nhận chỉ vì có đủ PC.
- Điểm thiếu coverage được bổ sung covariates trong vùng hỗ trợ nếu Earth Engine và miền dữ liệu cho phép.
- PCA không được fit lại cho riêng nhóm ngoài ROI.
- Các điểm này mở rộng tập hiệu chuẩn nhưng cũng có thể làm tăng khác biệt miền; cần xem QA và area of applicability.
- Mọi raster giao cho người dùng trong `02_KET_QUA/maps` được mask về `ROI_field_area`. Vùng hỗ trợ ngoài ROI không xuất hiện như vùng bản đồ dinh dưỡng cuối.

## Regression Kriging trong ứng dụng

Với mỗi chỉ tiêu và mỗi nhánh predictor, engine:

1. mô hình hóa thành phần xu thế từ covariates;
2. phân tích phần dư theo không gian;
3. chọn/kiểm tra variogram và tham số lân cận trong nested spatial cross-validation; các dự báo outer held-out là đánh giá ngoài-fold của quá trình phát triển mô hình, không phải kiểm định thực địa độc lập;
4. kriging phần dư nếu có cấu trúc hợp lệ;
5. cộng xu thế và phần dư để tạo dự báo cuối.

Nếu residual variogram chỉ thể hiện pure nugget, engine chuyển sang regression-only thay vì ép một cấu trúc không gian giả. Đây là cơ chế bảo vệ, không phải lỗi chạy.

## Kết quả ở đâu

```text
02_NOI_SUY_BAN_DO/02_KET_QUA/
  maps/
    TEN_CHI_TIEU/
      PC_ONLY/
      PC_PLUS_SOIL/       <- chỉ có khi dùng Soil Type
  reports/
    TEN_CHI_TIEU/
      PC_ONLY/
      PC_PLUS_SOIL/
  tables/
```

Trong mỗi thư mục bản đồ có thể có dự báo đã/không clamp, clipping mask, area of applicability, dissimilarity và residual kriging standard deviation tùy kết quả mô hình. `final_roi_mask_summary.json` xác nhận chính sách mask ROI và liệt kê các file được xuất.

## Không nên làm

- Không chạy Quy trình 2 bằng file `sample_cLHS` thay cho tọa độ thực tế.
- Không thay PCA reference sau khi đã tạo kế hoạch và dữ liệu hỗ trợ.
- Không chọn bản đồ chỉ vì nhìn mượt hơn.
- Không xem residual kriging standard deviation là toàn bộ độ bất định dự báo.
- Không diễn giải lớp dinh dưỡng theo ngưỡng nông học khi chưa xác nhận phương pháp lab, đơn vị, cây trồng và nguồn ngưỡng địa phương.
