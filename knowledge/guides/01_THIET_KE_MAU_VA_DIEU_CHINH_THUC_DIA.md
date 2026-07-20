# Thiết kế mẫu và điều chỉnh vị trí ngoài thực địa

## Phạm vi

Tài liệu này nối cơ sở khoa học với quy trình 01_THIET_KE_LAY_MAU. Nó không thay thế cấu hình dự án và không khẳng định một số lượng mẫu cố định phù hợp cho mọi chỉ tiêu.

## Gọi đúng thuật toán hiện tại

cLHS theo Minasny & McBratney (2006) là một bài toán tối ưu nhằm khớp phân bố biên của biến liên tục, tỷ lệ lớp phân loại và cấu trúc phụ thuộc của dữ liệu phụ trợ.

Engine hiện ưu tiên lõi tối ưu chính thức từ gói CRAN clhs. REDUCED chỉ gồm các điểm clhs_core do optimizer chọn trực tiếp, không snapping hoặc thay điểm hậu xử lý. Thuật toán simulated annealing là nghiệm tối ưu ngẫu nhiên, không phải bằng chứng đạt tối ưu toàn cục. FULL là thiết kế lai: lõi CRAN cLHS cộng spatial infill và short-lag support; vì vậy không được gọi toàn bộ FULL là đầu ra cLHS thuần.

Nếu backend chính thức không khả dụng và cấu hình cho phép fallback, QA phải ghi backend_used=python_clhs_like, fallback_reason và design_role=lhs_core. Fallback khi đó mới được gọi là cLHS-like hoặc spatially constrained soil-stratified LHS; không được mô tả như optimizer gốc.

Nguồn: minasny_mcbratney_2006_clhs, DOI [10.1016/j.cageo.2005.12.009](https://doi.org/10.1016/j.cageo.2005.12.009); brus_2019_sampling_dsm, DOI [10.1016/j.geoderma.2018.07.036](https://doi.org/10.1016/j.geoderma.2018.07.036).

## FULL và REDUCED

REDUCED là lõi bao phủ không gian covariates. FULL là tập lồng nhau, bổ sung điểm tăng cường khoảng trống địa lý và khoảng cách ngắn để hỗ trợ mô hình variogram. Cấu trúc lồng nhau giúp triển khai theo hai giai đoạn, nhưng không chứng minh REDUCED có chất lượng bản đồ tương đương FULL.

Mỗi phương án cần QA riêng:

- tỷ lệ mẫu theo Soil Type;
- bao phủ quantile của từng covariate/PC;
- sai lệch tương quan so với population candidates;
- khoảng trống địa lý lớn nhất;
- nearest-neighbour và phân bố khoảng cách cặp;
- số cặp ở các lag ngắn dự kiến dùng cho variogram.

## Khi phải di chuyển điểm

Giữ tọa độ thực tế; không sửa nó quay lại vị trí kế hoạch. Nếu có thể, lưu thêm bảng nhật ký gồm mã điểm kế hoạch, mã mẫu thực tế, khoảng cách di chuyển và lý do.

Một điểm ngoài ROI có thể tham gia hiệu chỉnh nếu vẫn thuộc cùng quần thể mục tiêu, cùng support lấy mẫu và nằm trong vùng covariate mà mô hình đã học. Ranh giới địa lý không đủ để quyết định; cần kiểm tra AOA/dissimilarity và chạy sensitivity analysis có/không có điểm đáng ngờ.

22 điểm hiện tại được chọn thuận tiện vì khó tiếp cận không phải là mẫu kiểm định xác suất độc lập. Chúng là dữ liệu huấn luyện đã bị điều chỉnh thực địa.

Nguồn: meyer_pebesma_2021_aoa, DOI [10.1111/2041-210X.13650](https://doi.org/10.1111/2041-210X.13650); brus_kempen_heuvelink_2011_validation, DOI [10.1111/j.1365-2389.2011.01364.x](https://doi.org/10.1111/j.1365-2389.2011.01364.x).
