# Quy trình 1 — Thiết kế lấy mẫu

## Mục tiêu

Quy trình 1 dùng `ROI_field_area` đã được Bước 0 phê duyệt, năm covariates liên tục và Soil Type nếu có để tạo hai phương án lấy mẫu lồng nhau. Đây là kế hoạch trước thực địa.

## Đầu vào

| File | Bắt buộc | Vị trí và yêu cầu |
|---|---:|---|
| `roi_field_area.geojson` | Có | Bước 0; polygon/multipolygon đã review |
| `soil_type.geojson` | Không | `01_THIET_KE_LAY_MAU/01_DAU_VAO`; có trường `soil_group_field` |
| `sampling.yml` | Có | `01_THIET_KE_LAY_MAU/01_DAU_VAO`; CRS, GEE và tham số thiết kế |

Không đặt `sample_actual.csv` trong Quy trình 1. File `roi.geojson` bên trong luồng kỹ thuật chỉ là bản tương thích được tạo từ `ROI_field_area`, không phải một ROI người dùng cần quản lý song song.

## Các bước tự động

1. Kiểm tra ROI và coverage covariates.
2. Tải hoặc tái sử dụng CHIRPS, DEM, NDVI, Slope và TWI.
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

Với năm covariates và đủ PC1–PC5, PCA là phép chuẩn hóa/quay toàn hạng, không phải giảm chiều. Quy trình 2 phải dùng đúng PCA reference đã đóng băng.

Lưới xuất 10 m chỉ là lưới tính toán/căn chỉnh. NDVI Sentinel-2 có quy mô danh nghĩa khoảng 10 m; SRTM/Slope khoảng 30 m; TWI bị giới hạn bởi nguồn địa hình–thủy văn; CHIRPS ở mức vài kilômét. Resampling không tạo chi tiết mới.

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
