# Uncertainty, AOA và độ phân giải bản đồ

## Ba câu hỏi khác nhau

1. Mô hình dự báo sai trung bình bao nhiêu trong nhiệm vụ CV?
2. Vị trí nào giống không gian covariates đã được học?
3. Khoảng dự báo tại từng pixel có được hiệu chuẩn không?

Spatial CV, AOA và uncertainty map lần lượt hỗ trợ các câu hỏi trên; chúng không thay thế nhau.

## Area of Applicability

AOA đánh dấu vùng covariate mà sai số CV có cơ sở áp dụng. Một điểm nằm trong ROI vẫn có thể nằm ngoài AOA; một điểm ngoài ROI có thể gần feature space huấn luyện. Vì vậy 22 điểm ngoài ROI cần đánh giá bằng covariate dissimilarity, khoảng cách địa lý và sensitivity analysis.

Nguồn: meyer_pebesma_2021_aoa, DOI [10.1111/2041-210X.13650](https://doi.org/10.1111/2041-210X.13650).

## RK_STD

Residual kriging SD chỉ mô tả thành phần residual theo giả định variogram. Nó không tự chứa uncertainty của trend, tham số, biến đổi, covariates hay sai số lab. Không gắn nhãn 90%/95% prediction interval nếu chưa xây dựng và kiểm tra coverage/calibration.

Đánh giá uncertainty nên có coverage, độ sắc, bias hai phía và diagnostic calibration phù hợp; coverage đơn lẻ có thể che lệch một phía.

Nguồn: schmidinger_heuvelink_2023_uncertainty, DOI [10.1016/j.geoderma.2023.116585](https://doi.org/10.1016/j.geoderma.2023.116585); globalsoilmap_2015_specs.

## Support và lưới

Một kết quả trung bình cho mỗi mẫu, điểm GPS, raster covariate và cell dự báo có support khác nhau. Lưới tính toán/xuất kết quả không có nghĩa giá trị đất được quan trắc tại từng ô hoặc mọi covariate có cùng độ chi tiết.

Report phải ghi cách đại diện một kết quả trung bình cho mỗi mẫu, kích thước lưới xuất, native resolution từng covariate, intended use scale, vùng AOA/extrapolation, uncertainty type và cách kiểm định.
