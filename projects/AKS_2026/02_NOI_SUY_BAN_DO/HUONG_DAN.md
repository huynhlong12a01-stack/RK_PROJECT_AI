# Hướng dẫn Quy trình 2 — Nội suy và tạo bản đồ

## Chuẩn bị

Kết quả lab chỉ được cập nhật trong `01_DAU_VAO/sample_actual.csv`:

- `code`: mã duy nhất;
- `lat`, `lon`: GPS thực tế WGS84 dạng số thập phân;
- các cột còn lại: kết quả lab dạng số, để trống khi chưa có.

Mỗi mẫu là một dòng kết quả trung bình; ứng dụng không tách tầng đất. Tọa độ được phép khác điểm cLHS và được phép ngoài ROI, nhưng phải có covariates/PCA hợp lệ.

Trước khi chạy một chỉ tiêu, mở `01_DAU_VAO/indicator_metadata.yml`, đối chiếu phương pháp/đơn vị với phiếu lab và đổi `confirmed: true`. File này không chứa kết quả phân tích. Giữ `classification.approved: false` khi chưa có bộ ngưỡng được phê duyệt; ứng dụng không tạo khuyến cáo liều phân bón.

## Chạy

Ngay khi có `code`, `lat`, `lon`, có thể nhấp `CHAY_NOI_SUY_BAN_DO.bat` để chuẩn bị predictor dù lab còn trống. Ứng dụng sẽ:

1. kiểm tra mẫu trong/ngoài ROI, target population, covariate support và metadata chỉ tiêu;
2. kiểm chứng raw covariates, PC1–PC5, lưới, sidecar và frozen PCA reference của Quy trình 1;
3. tạo mask phân tích cục bộ bằng mask PC Quy trình 1 cộng đúng các ô chứa `sample_actual`, rồi tạo lại PC1–PC5 từ raw đã kiểm chứng; đường chính này không truyền dữ liệu ra ngoài;

Quy trình 2 kiểm lại raw provenance và PCA lineage của Quy trình 1 trước khi đọc kết quả lab. Trạng thái STALE/UNVERIFIED sẽ chặn nội suy; hãy chạy lại Quy trình 1, không chép hoặc sửa file trong `_NOI_BO` để vượt cổng.

4. chỉ khi raw thật sự thiếu, tải bổ sung từ GEE bằng bounding envelope ROI cộng `covariate_support_buffer_m`;
5. mã hóa Soil Type dạng nominal, tách `Unmapped` khỏi `Other` (chỉ gộp lớp đã map nhưng thiếu mẫu);
6. nếu lab còn trống, kết thúc thành công ở `WAITING_LAB` và không tạo bản đồ;
7. khi có kết quả số, chạy `PC_ONLY` và `PC_PLUS_SOIL` nếu có lớp đất, rồi xuất bản đồ cuối đã mask về `ROI_field_area`.

Nếu có điểm ngoài ROI, lần kiểm tra đầu sẽ tạo `01_DAU_VAO/outside_sample_review.csv`. Chỉ điền bảng này cho các điểm ngoài ROI; workflow giữ câu trả lời theo `code` khi chạy lại.

Đường chính dùng raw covariates Quy trình 1 ngay trên máy. Khi thật sự cần tải bổ sung, GEE chỉ nhận bounding envelope của ROI đã duyệt cộng buffer cấu hình tại `THONG_SO_DU_AN.yml` (hiện là 300 m); ứng dụng không gửi mã, tọa độ hoặc hình học mẫu thực tế. Hình học tải không phải prediction domain và phải qua chuỗi kiểm chứng hash/sidecar trước khi kết nối. Chỉ sửa `covariate_support_buffer_m` trong `THONG_SO_DU_AN.yml`, không sửa `_NOI_BO`.

Điểm ngoài `ROI_field_area` có thể tham gia phát triển mô hình nếu đủ support và phù hợp target population/AOA; chúng không tự động là tập kiểm định độc lập. Không mặc định mô hình có Soil Type tốt hơn; chọn theo outer held-out spatial cross-validation và cảnh báo, không theo độ mượt của bản đồ. `RK_uncertainty_STD` chỉ là độ lệch chuẩn residual kriging, không phải total predictive uncertainty.

Xem kết quả tại `02_KET_QUA/maps`, `reports`, `tables` và hướng dẫn đầy đủ tại `D:\RK_R_Project\docs\04_NOI_SUY_VA_TAO_BAN_DO.md`.

- Trước preflight, ứng dụng kiểm `soil_lineage_ready`. `Unmapped` là thiếu coverage polygon; `Other` chỉ gộp lớp đã map nhưng thiếu mẫu. Xem `soil_predictor_summary.json` và các hash output trước khi dùng PC_PLUS_SOIL.
