# Xử lý lỗi thường gặp

Trước tiên, nhấp `0_KIEM_TRA_DU_AN.bat` trong thư mục dự án. Đọc dòng cuối cùng của cửa sổ chạy; thông báo thường chỉ rõ file hoặc bước đang thiếu.

## Bước 0

### Báo thiếu vùng đầu vào

- Nếu đã có ranh giới mía, file phải là `00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson`.
- Nếu chưa có, phải có cả `roi_search.geojson` và `sugarcane_labels.csv`.
- Kiểm tra đuôi thật của file; ROI phải là polygon/multipolygon, không phải danh sách điểm.
- `roi.geojson` trong Quy trình 1 là lớp tương thích do workflow quản lý, không phải nơi chính để dự án mới nạp ROI.

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

### Báo thiếu `sampling.yml` hoặc cấu hình không hợp lệ

- Không đổi tên file.
- Kiểm tra `crs_epsg`, `resolution_m`, `gee_project_id`, ngày bắt đầu/kết thúc.
- Ngày dùng định dạng `YYYY-MM-DD` và ngày kết thúc phải sau ngày bắt đầu.
- Dùng khoảng trắng, không dùng tab trong YAML.

### Soil Type không được nhận

- File phải tên `soil_type.geojson` và nằm cùng ROI.
- Cột khai báo tại `soil_group_field` phải tồn tại đúng chính tả/hoa thường.
- Geometry phải là polygon hợp lệ và có hệ tọa độ được khai báo.
- Nếu không có Soil Type, có thể bỏ file; workflow vẫn chạy với PC covariates.

### Không tải được Earth Engine

- Xác nhận tài khoản đã đăng nhập và có quyền đối với `gee_project_id`.
- Kiểm tra kết nối mạng và quota/tác vụ đang chạy trên Earth Engine.
- Kiểm tra khoảng ngày có dữ liệu.
- Không chạy đồng thời nhiều bản sao của cùng dự án.
- Sau khi sửa nguyên nhân, chạy lại file BAT; các covariates hoàn tất có thể được tái sử dụng.

### Báo không tìm thấy Python hoặc Rscript

Ứng dụng ưu tiên môi trường Python của `D:\apps\POINT_PLANNING_APP\.venv` rồi mới tìm Python hệ thống; Rscript phải có trong PATH. Đây là lỗi môi trường, không phải lỗi dữ liệu. Ghi lại toàn bộ thông báo và nhờ người quản trị cài/khôi phục môi trường trước khi tiếp tục.

### Kết quả FULL/REDUCED không như mong đợi

- Đọc `sampling_QA.json`, không chỉ đếm file CSV.
- Kiểm tra số `reduced_core_samples`, khoảng cách tối thiểu, buffer trong và diện tích tối thiểu.
- Ràng buộc quá chặt so với hình học ROI có thể làm giảm khả năng chọn đủ điểm.
- REDUCED phải là tập con FULL; nếu không, không dùng kế hoạch và báo lỗi kỹ thuật.
- Nếu QA ghi `python_clhs_like`, đọc `fallback_reason`; kiểm tra R, gói CRAN `clhs` và kết nối cài đặt. Không sửa nhãn method để giả rằng optimizer gốc đã chạy.
- Nếu số `short_lag_actual` thấp hơn yêu cầu, hình học/khoảng cách có thể không cho phép; không tuyên bố FULL đạt đúng cấu hình chỉ dựa trên tổng file.

## Quy trình 2

### Báo chưa có PCA từ Quy trình 1

Chạy `CHAY_THIET_KE_LAY_MAU.bat` đến khi có đủ PC1–PC5 và PCA reference. Không chép PCA từ dự án khác để vượt qua kiểm tra.

### `sample_actual.csv` có dòng nhưng `Indicators ready = 0`

Đây là trạng thái bình thường khi đang chờ lab. Dán ít nhất một cột kết quả số. Để ô chưa có kết quả trống; không nhập chữ hoặc đơn vị.

### Báo lỗi mã hoặc tọa độ

- `code` không được trống/trùng.
- `lat`, `lon` phải là số WGS84 thập phân.
- Kiểm tra không đảo hai cột và không dùng tọa độ UTM trong cột lat/lon.
- Lưu CSV với dấu phẩy phân cột; số thập phân dùng dấu chấm.

### Điểm ngoài ROI thiếu covariates

Ứng dụng sẽ cố tải vùng hỗ trợ từ Earth Engine. Nếu vẫn lỗi:

- kiểm tra tọa độ có đúng nơi lấy mẫu;
- kiểm tra điểm có quá xa miền dự án hay không;
- kiểm tra GEE và khoảng thời gian dữ liệu;
- xem `preflight_summary.json` và các file `pca_support_*` để biết điểm nào thiếu;
- không điền PC bằng tay và không nội suy covariates từ một dự án khác.

### Soil Type tạo nhiều điểm `Other`

- Kiểm tra độ phủ và geometry của `soil_type.geojson`.
- Kiểm tra trường phân loại đúng cột.
- Nhóm hiếm dưới ngưỡng số mẫu được gộp `Other` có chủ ý.
- Xem `soil_predictor_summary.json` và `soil_predictor_point_groups.csv` trước khi dùng `PC_PLUS_SOIL`.

### Không có bản đồ dù workflow đã chuẩn bị xong predictor

Nguyên nhân thường gặp nhất là tất cả chỉ tiêu lab vẫn trống. Cũng cần kiểm tra:

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
- `sampling.yml`;
- tệp QA liên quan;
- số dòng mẫu và tên chỉ tiêu đang chạy;
- những file đầu vào vừa thay đổi.

Không gửi mật khẩu hoặc token Earth Engine.
