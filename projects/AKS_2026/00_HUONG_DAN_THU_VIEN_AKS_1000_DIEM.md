# Thư viện tham chiếu AKS — tối đa 1.000 điểm

Chỉ sử dụng một tệp:

`00_TAO_THU_VIEN_AKS_1000_DIEM_AN_TOAN.bat`

Trước khi Earth Engine nhận dữ liệu, ứng dụng kiểm tra trong cùng một tiến trình:

- đúng dự án nguồn `AKS_2026` và GEE project `rkapp-492504`;
- tối đa 1.000 điểm, nhãn dương mía duy nhất và không đủ điều kiện kiểm định;
- số điểm, mã SHA-256 và nguồn gốc chọn điểm khớp model card;
- dữ liệu không phải mock, giả lập hoặc sản phẩm vận hành bị cấm;
- đúng 75 predictor, đúng thứ tự band, tám quý hoàn chỉnh từ `2024-07-01` đến trước `2026-07-01`;
- đúng collection, công thức, reducer, ngưỡng mây, đơn vị Sentinel-1 dB và không log thêm;
- đúng mã nguồn temporal engine đã đóng băng.

Chính bảng điểm đã vượt kiểm tra được giữ trong bộ nhớ và chuyển cho GEE. Lõi trích xuất sẽ từ chối chạy nếu bị gọi trực tiếp hoặc thiếu giấy phép trong bộ nhớ này. Ứng dụng chỉ dùng chính 1.000 điểm làm vùng hỗ trợ trích xuất, không gửi lại toàn bộ polygon ROI mía.

Sau khi GEE trả kết quả, bước thứ hai:

- đối chiếu lại schema, band, kỳ thời gian, công thức, đơn vị, số dòng, hash và thống kê từng predictor;
- loại `lon`, `lat` và không sao chép hình học;
- thay toàn bộ mã dòng nguồn bằng mã ngẫu nhiên không có bảng ánh xạ;
- kiểm tra đệ quy tên trường và giá trị có dấu hiệu tọa độ/WKT;
- tạo prototype và miền hỗ trợ đa biến của riêng lớp dương;
- tạo gói mới theo kiểu atomic; nếu thư mục cũ có tệp lạ, quy trình dừng để người dùng kiểm tra.

Kết quả cục bộ nằm tại:

`knowledge-private/sugarcane/AKS_2026/positive_reference_v1`

Gói này là `positive_reference_only`, không phải mô hình phân loại mía toàn Việt Nam. Ở tỉnh khác, AKS chỉ được bổ sung vào phần TRAIN sau khi có cả nhãn mía và không-mía địa phương, xác nhận lịch mùa vụ, vượt kiểm tra miền dữ liệu và kiểm định không gian riêng. Không dùng AKS cho calibration, test, dự đoán trực tiếp hoặc tự động nâng kết quả thành `roi_field_area`.
