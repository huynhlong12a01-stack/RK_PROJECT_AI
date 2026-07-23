# Regression Kriging và kiểm định mô hình

## Dạng mô hình

Regression Kriging (RK) gồm mô hình trend từ covariates, residual tại điểm mẫu, variogram residual, kriging residual và prediction bằng trend cộng residual kriged.

RK chỉ có ý nghĩa tăng thêm khi residual còn cấu trúc không gian có thể ước lượng. Pure nugget hoặc variogram không ổn định phải dẫn đến regression-only fallback hoặc manual review, không được mô tả là RK cải thiện.

Nguồn: hengl_2007_about_rk, DOI [10.1016/j.cageo.2007.05.001](https://doi.org/10.1016/j.cageo.2007.05.001).

## So sánh bắt buộc

Cho mỗi target, tối thiểu so mean/naive baseline, regression-only, Ordinary Kriging, RK PC_ONLY và RK PC_PLUS_SOIL nếu Soil Type đủ support.

Không mặc định Soil Type giúp mô hình. Chọn theo outer held-out nested spatial CV, bias, MAE/RMSE, R² dự báo, ổn định variogram, AOA và tính hợp lý bản đồ.

## Tuning không được rò rỉ

Transform, chọn biến, variogram và neighborhood phải được fit/tune bên trong training fold khi đánh giá mô hình. Outer test fold chỉ dùng để tính metric cuối của fold.

## Spatial CV khác independent validation

Nested spatial CV trả lời hiệu năng cho nhiệm vụ chuyển giao được định nghĩa bởi fold geometry. Nó không phải mẫu thực địa xác suất độc lập và không tự cho ước lượng map accuracy design-based không chệch.

Nguồn: wadoux_2021_spatial_cv_map_accuracy, DOI [10.1016/j.ecolmodel.2021.109692](https://doi.org/10.1016/j.ecolmodel.2021.109692); brus_kempen_heuvelink_2011_validation.

Dùng cụm “outer held-out nested spatial CV”. Chỉ gọi “independent validation” khi có bộ mẫu độc lập, được thiết kế và thu thập riêng, không tham gia bất kỳ bước fit/tuning nào.
