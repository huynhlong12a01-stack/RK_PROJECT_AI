# Covariates, PCA và Soil Type

## Dòng dữ liệu hiện tại

| Biến | Nguồn chính | Độ phân giải gốc gần đúng | Ý nghĩa đúng |
|---|---|---:|---|
| NDVI | Sentinel-2 SR Harmonized, B4/B8 | 10 m | Chỉ báo quang học về thảm thực vật, không đo trực tiếp dinh dưỡng đất |
| DEM, Slope | USGS SRTMGL1 003 | khoảng 30 m | Địa hình và đạo hàm địa hình |
| TWI proxy | MERIT Hydro upg + slope SRTM | 92,77 m và 30 m | Chỉ báo ẩm địa hình xấp xỉ, không phải độ ẩm quan trắc |
| CHIRPS | UCSB-CHG CHIRPS Daily | 0,05°, khoảng 5.566 m | Mưa lưới quy mô khí hậu |
| Soil Type | polygon người dùng | phụ thuộc bản đồ nguồn | Predictor phân loại |

Xuất tất cả lên lưới tính toán 10 m không tạo thêm thông tin cho dữ liệu 30–5.566 m. Báo cáo phải tách grid resolution khỏi native/effective resolution.

Nguồn catalog chính thức: google_s2_sr_harmonized_catalog, google_srtmgl1_catalog, google_merit_hydro_catalog, google_chirps_daily_catalog, google_cloud_score_plus_catalog.

## Provenance bắt buộc

Với mỗi lần tải phải lưu asset/collection ID và phiên bản; ngày bắt đầu/kết thúc; band và công thức; reducer theo thời gian; quy tắc cloud mask; CRS, scale xuất, resampling; vùng thiếu dữ liệu và ngày tải.

NDVI hiện là composite theo cửa sổ thời gian sau lọc Cloud Score+. CHIRPS là tổng hoặc thống kê theo cùng cấu hình thời gian. Hai biến này không được gọi chung chung nếu thiếu provenance.

## PCA

PCA phải được fit một lần trên population/candidate covariates của workflow 1. Center, scale, thứ tự biến và loading matrix được đóng băng. Mẫu thực tế và raster dự báo ở workflow 2 chỉ được project qua reference đó.

Hiện năm covariates tạo PC1–PC5 và giữ cả năm thành phần. Đây là chuẩn hóa cộng phép quay trực giao toàn hạng, không phải giảm chiều. PCA không dùng target và không bảo đảm thành phần có phương sai lớn là thành phần dự báo dinh dưỡng tốt nhất.

Nguồn: jolliffe_cadima_2016_pca, DOI [10.1098/rsta.2015.0202](https://doi.org/10.1098/rsta.2015.0202).

## Soil Type

Soil Type là biến phân loại. Mã như Xa, Fa hoặc mã số lớp phải được one-hot/dummy encode, không được đưa trực tiếp như số liên tục có thứ tự.

Nhóm Other của ứng dụng là nhãn kỹ thuật cho điểm ngoài hoặc thiếu coverage của polygon. Nó có thể rất dị thể và không phải một đơn vị đất học mới. Luôn báo số mẫu theo lớp và so sánh PC_ONLY với PC_PLUS_SOIL bằng nested spatial CV.
