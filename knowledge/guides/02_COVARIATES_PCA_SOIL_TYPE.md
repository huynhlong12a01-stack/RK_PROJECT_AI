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

`pca_summary.json` schema 2.0.0 khóa toàn bộ chuỗi dữ liệu bằng SHA-256: đúng 5 raster thô, sidecar provenance, file PCA reference và đúng PC1–PC5. Quy trình 2 chỉ chạy khi các hash này còn khớp ROI/cấu hình hiện tại; sửa hoặc thay một raster/reference sẽ buộc chạy lại Quy trình 1.

Khi phải fit PCA reference mới, workflow dùng `random_seed` trong `sampling.yml` và ghi số pixel fit cùng phiên bản R/terra. Seed hỗ trợ lặp lại trong cùng môi trường phần mềm; không tuyên bố đồng nhất từng bit giữa các phiên bản R/terra khác nhau.

PCA phải được fit một lần trên population/candidate covariates của workflow 1. Center, scale, thứ tự biến và loading matrix được đóng băng. Mẫu thực tế và raster dự báo ở workflow 2 chỉ được project qua reference đó.

Hiện năm covariates tạo PC1–PC5 và giữ cả năm thành phần. Đây là chuẩn hóa cộng phép quay trực giao toàn hạng, không phải giảm chiều. PCA không dùng target và không bảo đảm thành phần có phương sai lớn là thành phần dự báo dinh dưỡng tốt nhất.

Trong Workflow 2, đường chính là tạo lại PCA **cục bộ** từ năm raw covariates Workflow 1 đã kiểm chứng. Mask phân tích là hợp của mask PC Workflow 1 và đúng các ô raster chứa `sample_actual`; tọa độ mẫu chỉ được dùng để xác định ô trên máy. Các PC cũ được ưu tiên tại nơi mask Workflow 1 đã có, còn frozen center/scale/loading được dùng để điền các ô mẫu có raw hợp lệ. Quy trình này không fit PCA mới và không truyền dữ liệu mẫu ra ngoài.

Nguồn: jolliffe_cadima_2016_pca, DOI [10.1098/rsta.2015.0202](https://doi.org/10.1098/rsta.2015.0202).

## Soil Type

Soil Type là biến phân loại. Mã như Xa, Fa hoặc mã số lớp phải được one-hot/dummy encode, không được đưa trực tiếp như số liên tục có thứ tự.

`Unmapped` là nhãn kỹ thuật cho điểm/ô ngoài coverage polygon. `Other` chỉ gộp các lớp nguồn đã map nhưng thiếu mẫu. Cả hai có thể dị thể và không phải đơn vị đất học mới. Luôn báo số mẫu theo lớp và so sánh PC_ONLY với PC_PLUS_SOIL bằng nested spatial CV.

## Lineage và ngữ nghĩa thiếu coverage

GEE chỉ là fallback khi ít nhất một raw covariate Workflow 1 thật sự thiếu tại ô mẫu. Miền gửi tới GEE là bounding envelope của ROI đã duyệt cộng fixed metric buffer từ `THONG_SO_DU_AN.yml`; nó không mang mã, tọa độ hoặc hình học điểm thực tế và không phải prediction domain. Miền phân tích vẫn là mask PC Workflow 1 cộng các ô mẫu tạo cục bộ; bản đồ cuối vẫn mask về ROI.

Trước `ee.Initialize`, privacy gate kiểm `support_geometry_privacy.json` bằng SHA-256: đúng ROI, file support, buffer, CRS, một feature và schema thuộc tính tối thiểu. `gee_support_download_summary.json` phải nối tới privacy sidecar, source identity, output grid và hash năm raw covariates; `pca_current_provenance.json` tiếp tục nối tới các sidecar/hash này cùng frozen PCA reference. Không dùng một cờ so khớp hình học đơn lẻ thay cho chuỗi provenance. `covariate_support_buffer_m` chỉ được sửa trong `THONG_SO_DU_AN.yml`.

Khi predictor và lineage đã sẵn sàng nhưng các cột phân tích còn trống, Workflow 2 kết thúc thành công ở `WAITING_LAB` và không tạo bản đồ. Đây là trạng thái dữ liệu, không phải lỗi mô hình hay lỗi GEE.

Workflow 1 phải khóa SHA-256 của Soil Type nguồn, tên trường phân loại, encoding nominal, code-map và raster nhóm đất. Workflow 2 kiểm lại toàn bộ chuỗi này và fail-closed nếu file/trường/ánh xạ đã đổi. Kiểm tra overlap toàn miền dùng số polygon phủ tại tâm pixel trên lưới PC; vì vậy nó bắt được mơ hồ ở support mô hình nhưng không thay thế topology QA ở độ phân giải vector.

`Unmapped` và `Other` không đồng nghĩa: `Unmapped` là ngoài coverage polygon, còn `Other` chỉ gộp các lớp đã map nhưng thiếu mẫu. Không lớp nào là một đơn vị đất học mới. Nếu một mức có trên miền dự báo nhưng không có mẫu để ước lượng, raster audit vẫn giữ nhãn nhưng mô hình không được tạo hệ số giả; QA phải cảnh báo việc dùng hiệu ứng tham chiếu và việc chọn `PC_PLUS_SOIL` phải dựa trên nested spatial CV/support thay vì mặc định tốt hơn `PC_ONLY`.
