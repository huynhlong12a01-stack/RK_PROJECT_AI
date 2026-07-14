# Hướng dẫn Quy trình 2 — Nội suy và tạo bản đồ

## Chuẩn bị

Kết quả lab chỉ được cập nhật trong `01_DAU_VAO/sample_actual.csv`:

- `code`: mã duy nhất;
- `lat`, `lon`: GPS thực tế WGS84 dạng số thập phân;
- các cột còn lại: kết quả lab dạng số, để trống khi chưa có.

Mỗi mẫu là một dòng kết quả trung bình; ứng dụng không tách tầng đất. Tọa độ được phép khác điểm cLHS và được phép ngoài ROI, nhưng phải có covariates/PCA hợp lệ.

Trước khi chạy một chỉ tiêu, mở `01_DAU_VAO/indicator_metadata.yml`, đối chiếu phương pháp/đơn vị với phiếu lab và đổi `confirmed: true`. File này không chứa kết quả phân tích. Giữ `classification.approved: false` khi chưa có bộ ngưỡng được phê duyệt; ứng dụng không tạo khuyến cáo liều phân bón.

## Chạy

Sau khi ít nhất một chỉ tiêu có giá trị số, nhấp `CHAY_NOI_SUY_BAN_DO.bat`. Ứng dụng sẽ:

1. kiểm tra mẫu trong/ngoài ROI, target population, covariate support và metadata chỉ tiêu;
2. tái sử dụng PC1–PC5 và PCA reference của Quy trình 1;
3. tải vùng hỗ trợ Earth Engine nếu điểm thiếu covariates;
4. mã hóa Soil Type dạng phân loại, gộp nhóm hiếm/không khớp vào `Other`;
5. chạy `PC_ONLY` và `PC_PLUS_SOIL` khi có lớp đất;
6. xuất bản đồ cuối đã mask về `ROI_field_area` cùng báo cáo QA.

Nếu có điểm ngoài ROI, lần kiểm tra đầu sẽ tạo `01_DAU_VAO/outside_sample_review.csv`. Chỉ điền bảng này cho các điểm ngoài ROI; workflow giữ câu trả lời theo `code` khi chạy lại.

Điểm ngoài `ROI_field_area` có thể tham gia phát triển mô hình nếu đủ support và phù hợp target population/AOA; chúng không tự động là tập kiểm định độc lập. Không mặc định mô hình có Soil Type tốt hơn; chọn theo outer held-out spatial cross-validation và cảnh báo, không theo độ mượt của bản đồ. `RK_uncertainty_STD` chỉ là độ lệch chuẩn residual kriging, không phải total predictive uncertainty.

Xem kết quả tại `02_KET_QUA/maps`, `reports`, `tables` và hướng dẫn đầy đủ tại `D:\RK_R_Project\docs\04_NOI_SUY_VA_TAO_BAN_DO.md`.
