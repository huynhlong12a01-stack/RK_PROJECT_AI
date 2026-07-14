# Quy tắc quyết định cho dự án

## Quy trình 1 — Thiết kế mẫu

- ROI bắt buộc; Soil Type tùy chọn nhưng phải có field hợp lệ.
- Gọi thuật toán hiện tại là cLHS-like/spatially constrained LHS.
- REDUCED phải là tập con của FULL.
- Không công bố “đảm bảo chất lượng” cho REDUCED.
- PCA reference phải được lưu và đóng băng.
- Không phát hành phương án nếu QA cho thấy điểm ngoài ROI, trùng tọa độ, sai khoảng cách hoặc thiếu covariate.

## Quy trình 2 — Nội suy

- sample_actual.csv là vị trí thực tế và kết quả trung bình; không thay bằng điểm kế hoạch.
- Điểm ngoài ROI được giữ để đánh giá, không tự loại và cũng không tự chấp nhận.
- Thiếu covariate phải được bổ sung cùng pipeline/provenance của workflow 1.
- Soil Type là categorical; Other phải được báo.
- So sánh PC_ONLY và PC_PLUS_SOIL, không ưu tiên mô hình Soil theo mặc định.
- Map cuối mask ROI; AOA/extrapolation và uncertainty phải là lớp QA riêng.

## Cổng khoa học trước khi phát hành

Không phát hành như bản đồ sử dụng chính thức khi target không có đơn vị/phương pháp lab rõ; outer R² dự báo không dương hoặc kém baseline rõ; variogram residual singular/pure nugget/range bị ép mà không có fallback minh bạch; AOA thấp nhưng report không cảnh báo; residual SD bị gọi là prediction interval; hoặc bản đồ hàm lượng bị chuyển thẳng thành liều phân không có hiệu chuẩn địa phương.

## Mức nhãn đề xuất

- DRAFT / INTERNAL QA: pipeline chạy xong nhưng chưa có kiểm định hoặc metadata đầy đủ.
- MODEL-CHECKED: qua nested spatial CV và QA kỹ thuật.
- VALIDATED FOR STATED TASK: có bộ validation phù hợp nhiệm vụ, phạm vi và support đã công bố.
- AGRONOMIC DECISION SUPPORT: chỉ khi có ngưỡng/hiệu chuẩn cây trồng địa phương và chuyên gia chịu trách nhiệm.
