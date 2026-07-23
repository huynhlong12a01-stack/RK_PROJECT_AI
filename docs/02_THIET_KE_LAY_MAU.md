# Quy trình 1 — Thiết kế lấy mẫu

## Mục tiêu

Quy trình 1 dùng `ROI_field_area` đã được Bước 0 phê duyệt, năm covariates liên tục và Soil Type nếu có để tạo hai phương án lấy mẫu lồng nhau. Đây là kế hoạch trước thực địa.

## Đầu vào

| File | Bắt buộc | Vị trí và yêu cầu |
|---|---:|---|
| `THONG_SO_DU_AN.yml` | Có | Gốc dự án; nguồn duy nhất cho CRS, GEE, `resolution_m`, `covariate_support_buffer_m` và ngày covariates |
| `roi_field_area.geojson` | Có | Bước 0; polygon/multipolygon đã review |
| `soil_type.geojson` | Không | `01_THIET_KE_LAY_MAU/01_DAU_VAO`; có trường `soil_group_field` |
| `sampling.yml` | Có | `01_THIET_KE_LAY_MAU/01_DAU_VAO`; số mẫu, spacing và tham số cLHS |

Không đặt sample_actual.csv trong Quy trình 1. Quy trình này đọc trực tiếp nguồn duy nhất 00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson; không tạo hoặc quản lý thêm bản sao ROI.

## Các bước tự động

1. Kiểm tra ROI và coverage covariates.
2. Tải hoặc tái sử dụng CHIRPS, DEM, NDVI, Slope và TWI.

Chỉ tái sử dụng covariates của chính dự án khi `raw_covariate_provenance.json` khớp `project_id`, GEE project, hash ROI, CRS, độ phân giải, khoảng ngày và hash năm raster. Thiếu hoặc lệch bất kỳ mục nào sẽ tạo lại grid từ ROI/cấu hình hiện tại và tải mới; ứng dụng không nhập covariates từ dự án cũ hoặc dự án khác.
3. Căn chỉnh, chuẩn hóa và tạo PC1–PC5; lưu PCA reference.
4. Xử lý Soil Type như biến phân loại.
5. Tạo quần thể ứng viên hợp lệ trong ROI và buffer trong.
6. Với backend CRAN, dùng `clhs` để tối ưu lõi REDUCED theo phân bố các PC, tỷ lệ Soil Type và cấu trúc tương quan; chạy nhiều lần khởi tạo theo cấu hình.
7. Bổ sung `spatial_infill` và `short_lag` vào FULL.
8. Xuất kế hoạch và QA.

## Cách gọi đúng phương pháp

Khi `backend_used=r_clhs_cran`:

- chỉ các điểm `clhs_core` là đầu ra trực tiếp của optimizer cLHS gốc;
- REDUCED là lõi cLHS;
- FULL là **thiết kế lai**: lõi cLHS + bổ sung không gian;
- `is_original_clhs_optimizer_core=true`, nhưng `is_pure_original_clhs_design=false`.

Nếu backend gốc không khả dụng và chế độ `auto` fallback:

- lõi có vai trò `lhs_core`;
- `backend_used=python_clhs_like`;
- không được mô tả là cLHS optimizer gốc;
- đọc `fallback_reason` trong provenance trước khi dùng.

cLHS dùng tối ưu ngẫu nhiên nên không chứng minh nghiệm tối ưu toàn cục. Tọa độ không nằm trong objective cLHS của gói: workflow dùng tọa độ để tạo quần thể ứng viên hợp lệ, ưu tiên restart đáp ứng spacing và bổ sung không gian sau tối ưu. Vì vậy cLHS không tự bảo đảm đường đi, khoảng cách, độ chính xác bản đồ hoặc một variogram tốt; các kiểm soát không gian và thực địa vẫn cần thiết.

## PCA và độ phân giải

`pca_summary.json` schema 2.0.0 khóa toàn bộ chuỗi dữ liệu bằng SHA-256: đúng 5 raster thô, sidecar provenance, file PCA reference và đúng PC1–PC5. Quy trình 2 chỉ chạy khi các hash này còn khớp ROI/cấu hình hiện tại; sửa hoặc thay một raster/reference sẽ buộc chạy lại Quy trình 1.

Khi phải fit PCA reference mới, workflow dùng `random_seed` trong `sampling.yml` và ghi số pixel fit cùng phiên bản R/terra. Seed hỗ trợ lặp lại trong cùng môi trường phần mềm; không tuyên bố đồng nhất từng bit giữa các phiên bản R/terra khác nhau.

Với năm covariates và đủ PC1–PC5, PCA là phép chuẩn hóa/quay toàn hạng, không phải giảm chiều. Quy trình 2 phải dùng đúng PCA reference đã đóng băng.

Lưới do `resolution_m` trong `THONG_SO_DU_AN.yml` quy định chỉ là lưới tính toán/căn chỉnh. Ví dụ, chọn 10 m không làm thay đổi support gốc: NDVI Sentinel-2 có quy mô danh nghĩa khoảng 10 m; SRTM/Slope khoảng 30 m; TWI bị giới hạn bởi nguồn địa hình–thủy văn; CHIRPS ở mức vài kilômét. Resampling không tạo chi tiết mới.

## Hai phương án

### REDUCED

- Chỉ gồm lõi `clhs_core` hoặc `lhs_core` nếu fallback.
- Có `included_in_REDUCED=True`, `priority=1`.
- Là tập con của FULL.
- Là phương án ít nguồn lực hơn, không được bảo đảm chất lượng tương đương FULL.

### FULL

- Gồm toàn bộ REDUCED.
- Thêm `spatial_infill` để cải thiện độ phủ địa lý.
- Thêm `short_lag` để hỗ trợ khoảng cách ngắn cho phân tích variogram.
- Phần bổ sung có `priority=2` và không phải đầu ra trực tiếp của CRAN `clhs`.

Số điểm thực tế phải đọc từ QA của lần chạy; không coi 79/105 là mặc định cho mọi dự án.

## File kết quả và QA

Trong `01_THIET_KE_LAY_MAU/02_KET_QUA`:

- `sample_cLHS_FULL.csv/.geojson`;
- `sample_cLHS_REDUCED.csv/.geojson`;
- `sampling_QA.json`;
- `sampling_QA_FULL.json`, `sampling_QA_REDUCED.json`;
- `covariate_provenance.json`.

Trước thực địa, kiểm:

- `reduced_is_subset_of_full=true`;
- backend/method flags đúng với vai trò điểm;
- số điểm yêu cầu và số điểm thực tế, đặc biệt `short_lag_actual`;
- minimum spacing, ROI containment, Soil Type và feature-space coverage;
- CRS và khả năng tiếp cận.

Nếu phải đổi chỗ, ghi GPS thật vào `sample_actual.csv`; không sửa kế hoạch để che chênh lệch.

## Khóa lineage Soil Type

Khi kết thúc Quy trình 1, `_NOI_BO/work/design/qa/soil_group_summary.json` schema 3.0.0 khóa bằng SHA-256: chính file `soil_type.geojson`, trường `soil_group_field`, khai báo mã hóa nominal, bảng ánh xạ code–label và raster `Soil_Group_Code.tif`. `Unmapped` là mức kỹ thuật cho ô trong miền PC nhưng ngoài coverage polygon; `Other` không được dùng trong thiết kế cLHS. Ứng dụng cũng đếm ô bị nhiều polygon phủ tại tâm pixel trên toàn miền PC và dừng nếu phát hiện mơ hồ. Kiểm tra này có giới hạn theo độ phân giải lưới, nên không chứng minh không có overlap nhỏ hơn một pixel.

Nếu thêm, xóa, thay nội dung Soil Type hoặc đổi `soil_group_field` sau Quy trình 1, Quy trình 2 sẽ dừng và yêu cầu chạy lại Quy trình 1. Metadata nguồn/giấy phép trong `shared_data/soil_type_vietnam/provenance.yml` được ghi để audit nhưng trạng thái giấy phép chưa rõ không tự chặn xử lý cục bộ; hash của file dự án vẫn là định danh thực thi bắt buộc.