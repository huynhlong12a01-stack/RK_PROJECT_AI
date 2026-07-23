# Xử lý lỗi thường gặp

Trước tiên, nhấp `0_KIEM_TRA_DU_AN.bat` trong thư mục dự án. Đọc dòng cuối cùng của cửa sổ chạy; thông báo thường chỉ rõ file hoặc bước đang thiếu.

## Bước 0

### Báo thiếu vùng đầu vào

- Nếu đã có ranh giới mía, file phải là `00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson`.
- Nếu chưa có, phải có cả `roi_search.geojson` và `sugarcane_labels.csv`.
- Kiểm tra đuôi thật của file; ROI phải là polygon/multipolygon, không phải danh sách điểm.
- ROI duy nhất nằm tại 00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson; nếu thiếu, quay lại Bước 0 để cung cấp hoặc phê duyệt ROI.

### Báo nhãn không đủ hai lớp

- `sugarcane_labels.csv` phải có cả `label=1` và `label=0` đã kiểm chứng tại địa phương.
- Không thay nhãn âm bằng điểm ngẫu nhiên.
- Mỗi lớp phải có đủ nhóm không gian; các điểm cùng lô nên cùng `group_id`.

### Báo chưa xác nhận phenology

- Chỉ dùng `feature_end_date_exclusive` ở đầu một quý đã hoàn tất.
- Xác nhận `phenology_alignment_confirmed: true` sau khi ghi `crop_calendar_source` và `crop_calendar_note`.
- Không vượt gate bằng cách chọn ảnh/quý tương lai hoặc chưa hoàn tất.

### Có ROI ứng viên nhưng Quy trình 1 vẫn bị chặn

Đây là hành vi đúng. Review `roi_field_area_candidate`, sửa ranh giới và lưu bản đã duyệt thành `roi_field_area.geojson`; sau đó chạy lại Bước 0.

## Quy trình 1

### Báo thiếu ROI đã duyệt

Chạy Bước 0 trước. Không đổi tên ROI ứng viên thành ROI chính thức nếu chưa review.

### Báo thiếu `THONG_SO_DU_AN.yml`, `sampling.yml` hoặc cấu hình không hợp lệ

- Không đổi tên file.
- Kiểm tra `crs_mode`, `crs_epsg`, `resolution_m`, `covariate_support_buffer_m`, `gee_project_id`, `sampling_start_date` và `sampling_end_date` trong `THONG_SO_DU_AN.yml`.
- Chỉ sửa các thông số chung này tại `THONG_SO_DU_AN.yml`; `sampling.yml` chỉ dùng cho số mẫu, spacing và tham số cLHS.
- Ngày dùng định dạng `YYYY-MM-DD` và ngày kết thúc phải sau ngày bắt đầu.
- Dùng khoảng trắng, không dùng tab trong YAML.

### Soil Type không được nhận

- File phải tên `soil_type.geojson` và nằm tại `01_THIET_KE_LAY_MAU/01_DAU_VAO`; ROI vẫn nằm riêng ở Bước 0.
- Cột khai báo tại `soil_group_field` phải tồn tại đúng chính tả/hoa thường.
- Geometry phải là polygon hợp lệ và có hệ tọa độ được khai báo.
- Nếu không có Soil Type, có thể bỏ file; workflow vẫn chạy với PC covariates.

### Không tải được Earth Engine

- Xác nhận tài khoản đã đăng nhập và có quyền đối với `gee_project_id` khai báo trong `THONG_SO_DU_AN.yml`.
- Kiểm tra kết nối mạng và quota/tác vụ đang chạy trên Earth Engine.
- Kiểm tra khoảng ngày có dữ liệu.
- Không chạy đồng thời nhiều bản sao của cùng dự án.
- Sau khi sửa nguyên nhân, chạy lại file BAT; các covariates hoàn tất có thể được tái sử dụng.

### Báo không tìm thấy Python hoặc Rscript

Ứng dụng chỉ dùng môi trường riêng `D:\RK_R_Project\.venv`; nếu chưa có, hãy chạy `D:\RK_R_Project\CAI_DAT_UNG_DUNG.bat`. Ứng dụng không còn tự mượn môi trường của dự án cũ; `Rscript` vẫn phải có trong `PATH`.

### Kết quả FULL/REDUCED không như mong đợi

- Đọc `sampling_QA.json`, không chỉ đếm file CSV.
- Kiểm tra số `reduced_core_samples`, khoảng cách tối thiểu, buffer trong và diện tích tối thiểu.
- Ràng buộc quá chặt so với hình học ROI có thể làm giảm khả năng chọn đủ điểm.
- REDUCED phải là tập con FULL; nếu không, không dùng kế hoạch và báo lỗi kỹ thuật.
- Nếu QA ghi `python_clhs_like`, đọc `fallback_reason`; kiểm tra R, gói CRAN `clhs` và kết nối cài đặt. Không sửa nhãn method để giả rằng optimizer gốc đã chạy.
- Nếu số `short_lag_actual` thấp hơn yêu cầu, hình học/khoảng cách có thể không cho phép; không tuyên bố FULL đạt đúng cấu hình chỉ dựa trên tổng file.

## Quy trình 2

### Báo chưa có PCA từ Quy trình 1

Nếu trạng thái hiển thị `raw provenance STALE/UNVERIFIED` hoặc `PCA lineage STALE/UNVERIFIED`, không chép file để vượt cổng. Chạy lại `CHAY_THIET_KE_LAY_MAU.bat` đến khi có đủ năm raw covariates, PC1–PC5, PCA reference và chuỗi hash/sidecar hợp lệ.

Nếu Quy trình 1 đã được xác minh nhưng một điểm thực tế nằm ngoài mask PC, hãy chạy Quy trình 2: ứng dụng sẽ dùng raw covariates Quy trình 1 để tạo lại PCA cục bộ tại ô mẫu. Đây không phải lỗi và không cần GEE khi raw vẫn đầy đủ.

### `sample_actual.csv` có dòng nhưng `Indicators ready = 0`

Đây là trạng thái bình thường khi đang chờ lab. Hãy chạy Quy trình 2 một lần để chuẩn bị predictor; trạng thái mong đợi là `Actual PCA: provenance VERIFIED` và `WAITING_LAB`, tiến trình thành công nhưng không có bản đồ mới. Với đường cục bộ, privacy gate báo không cần truyền dữ liệu ra ngoài; chỉ nhánh GEE dự phòng mới phải báo `VERIFIED`. Khi lab trả kết quả, dán ít nhất một cột số rồi chạy lại. Để ô chưa có kết quả trống; không nhập chữ hoặc đơn vị.

### Báo lỗi mã hoặc tọa độ

- `code` không được trống/trùng.
- `lat`, `lon` phải là số WGS84 thập phân.
- Kiểm tra không đảo hai cột và không dùng tọa độ UTM trong cột lat/lon.
- Lưu CSV với dấu phẩy phân cột; số thập phân dùng dấu chấm.

### Điểm ngoài ROI thiếu covariates

Ứng dụng xử lý theo thứ tự:

1. kiểm chứng năm raw covariates và sidecar của Quy trình 1;
2. nếu raw còn đủ tại ô mẫu, tạo mask phân tích bằng mask PC Quy trình 1 cộng các ô chứa `sample_actual`, rồi tạo lại PCA cục bộ bằng frozen reference, không kết nối ngoài;
3. chỉ khi raw thật sự thiếu mới tải bổ sung từ GEE bằng bounding envelope ROI cộng fixed buffer.

Nếu vẫn lỗi:

- kiểm tra tọa độ có đúng nơi lấy mẫu;
- kiểm tra điểm có quá xa miền dự án hay không;
- kiểm tra GEE và khoảng thời gian dữ liệu;
- xem `preflight_summary.json` và các file `pca_support_*` để biết điểm nào thiếu;
- không điền PC bằng tay và không nội suy covariates từ một dự án khác.


### Privacy gate chặn vùng support

Đây là cổng an toàn chỉ áp dụng cho nhánh GEE dự phòng và chạy **trước** kết nối GEE. Vùng support hợp lệ phải là đúng một polygon/multipolygon tạo từ bounding envelope của `ROI_field_area` cộng vùng đệm cố định; chỉ có ba thuộc tính `support_geometry_policy`, `support_buffer_m`, `contains_sample_attributes`. Đây là miền tải, không phải prediction domain.

- Không thêm `code`, `lat`, `lon`, `sample_id`, `x/y` hoặc bất kỳ trường nhận dạng mẫu nào vào lớp support.
- Không tự sửa file `_NOI_BO/work/interpolation/covariate_support_buffers.gpkg`.
- Nếu điểm thật nằm ngoài buffer nhưng đã được duyệt giữ lại, tăng `covariate_support_buffer_m` tại `THONG_SO_DU_AN.yml`, rồi chạy lại Quy trình 2 để ứng dụng tái tạo hình học và provenance.
- Kiểm `support_geometry_privacy.json` và `gee_support_download_summary.json`: hash ROI, hash file support, hash privacy sidecar, schema tối thiểu, source identity, output grid và hash năm raw covariates phải nối đúng; mọi cờ gửi/dùng tọa độ hoặc mã mẫu phải là `false`.
- Chỉ tiếp tục khi `0_KIEM_TRA_DU_AN.bat` hiển thị `Privacy gate: VERIFIED - NO SAMPLE LOCATION SENT`.

### Soil Type tạo nhiều điểm `Other`

- Kiểm tra độ phủ và geometry của `soil_type.geojson`.
- Kiểm tra trường phân loại đúng cột.
- Nhóm hiếm dưới ngưỡng số mẫu được gộp `Other` có chủ ý.
- Xem `soil_predictor_summary.json` và `soil_predictor_point_groups.csv` trước khi dùng `PC_PLUS_SOIL`.

### Không có bản đồ dù workflow đã chuẩn bị xong predictor

Nếu trạng thái là `WAITING_LAB` và tất cả chỉ tiêu còn trống thì đây là kết quả thành công: ứng dụng chủ ý không tạo bản đồ. Khi đã có số liệu mà vẫn không có bản đồ, kiểm tra:

- cột có chứa số thuần hay bị Excel lưu thành chuỗi;
- số mẫu có giá trị của từng chỉ tiêu có đủ để chia spatial folds;
- cửa sổ chạy có dừng ở lỗi schema, variogram hoặc mô hình hay không;
- output nằm theo từng chỉ tiêu/nhánh trong `02_KET_QUA`.

### Mô hình chuyển thành regression-only/pure nugget

Đây là fallback an toàn khi residual không có cấu trúc không gian đáng tin. Không ép variogram thủ công chỉ để tạo một bản đồ RK. Đọc so sánh baseline và spatial CV; bản đồ regression-only vẫn có thể là kết quả phù hợp hơn.

### Bản đồ có vùng giá trị bất thường hoặc bị cắt nhiều

- So sánh `RK_final` và `RK_final_unclamped`.
- Xem clipping mask, AOA và dissimilarity.
- Kiểm tra outlier lab, đơn vị và phương pháp phân tích.
- Không chỉnh raster bằng tay để làm bản đồ “đẹp hơn”.

## Khi đã thay ROI, thời gian ảnh hoặc CRS sau lần chạy đầu

Workflow có cơ chế tái sử dụng covariates và PCA đã có. Vì vậy không nên chỉ ghi đè các đầu vào nền rồi bấm chạy lại. Cách an toàn nhất là tạo dự án mới với cấu hình mới. Nếu bắt buộc giữ cùng dự án, nhờ người quản trị thực hiện chạy lại có kiểm soát và lưu phiên bản cũ; người dùng không tự xóa cache trong `_NOI_BO`.

## Thông tin cần gửi khi nhờ hỗ trợ

- tên dự án;
- bước đang chạy;
- dòng lỗi đầy đủ hoặc ảnh cửa sổ;
- `THONG_SO_DU_AN.yml` và `sampling.yml`;
- tệp QA liên quan;
- số dòng mẫu và tên chỉ tiêu đang chạy;
- những file đầu vào vừa thay đổi.

Không gửi mật khẩu hoặc token Earth Engine.
