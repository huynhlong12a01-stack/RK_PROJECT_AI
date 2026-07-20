# Tạo một dự án mới

## Cách tạo

Lần đầu trên một máy, chạy D:\RK_R_Project\CAI_DAT_UNG_DUNG.bat. Bộ cài tạo môi trường Python riêng trong .venv, cài gói R/Python và không yêu cầu sửa thư mục _UNG_DUNG.

1. Mở `D:\RK_R_Project`.
2. Nhấp đúp `CREATE_NEW_PROJECT.bat`.
3. Nhập tên dự án rồi nhấn Enter.
4. Mở `D:\RK_R_Project\projects\TEN_DU_AN`.

Nếu tên sau chuẩn hóa đã tồn tại, chương trình dừng để không ghi đè dữ liệu.

## Dự án mới có gì

```text
TEN_DU_AN/
  README.md
  THONG_SO_DU_AN.yml
  0_KIEM_TRA_DU_AN.bat
  00_XAC_LAP_VUNG_MIA/
    HUONG_DAN.md
    CHAY_XAC_LAP_VUNG_MIA.bat
    01_DAU_VAO/
      interpretation.yml
      sugarcane_labels_template.csv
    02_KET_QUA/
  01_THIET_KE_LAY_MAU/
    HUONG_DAN.md
    CHAY_THIET_KE_LAY_MAU.bat
    01_DAU_VAO/
      sampling.yml
    02_KET_QUA/
  02_NOI_SUY_BAN_DO/
    HUONG_DAN.md
    CHAY_NOI_SUY_BAN_DO.bat
    01_DAU_VAO/
      sample_actual.csv
      indicator_metadata.yml
    02_KET_QUA/
      maps/
      reports/
      tables/
  _NOI_BO/
```

## Cấu hình chung của dự án

Mở `THONG_SO_DU_AN.yml` ở thư mục gốc dự án và kiểm tra:

- `crs_mode`/`crs_epsg`;
- `resolution_m`;
- `covariate_support_buffer_m` (chỉ dùng khi phải tải covariates bổ sung cho điểm ngoài coverage);
- `gee_project_id`;
- `sampling_start_date` và `sampling_end_date`.

Đây là nguồn duy nhất cho các giá trị dùng chung trên; workflow tự đồng bộ chúng sang cấu hình kỹ thuật của Bước 0, Quy trình 1 và Quy trình 2. Không sửa các bản sao của cùng giá trị trong `interpretation.yml`, `sampling.yml` hoặc `_NOI_BO/config/project.yml` để tạo cấu hình khác nhau.

`THONG_SO_DU_AN.yml` không phải tệp duy nhất cần sửa. `interpretation.yml` vẫn chứa phenology/cổng phân loại; `sampling.yml` vẫn chứa số mẫu, spacing và tham số cLHS; các tệp ROI, nhãn, Soil Type, `sample_actual.csv` và `indicator_metadata.yml` vẫn được cập nhật theo đúng giai đoạn.

## Chọn đầu vào cho Bước 0

Chỉ chọn một đường đi:

### Đã có ranh giới mía

Đặt polygon/multipolygon đã kiểm tra vào:

`00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson`

### Chưa có ranh giới mía

Đặt:

- `roi_search.geojson`: ranh giới tìm kiếm, thường là huyện/tỉnh;
- sao chép `sugarcane_labels_template.csv` thành `sugarcane_labels.csv`, rồi điền các điểm đã kiểm chứng có cả `label=1` và `label=0`;
- `interpretation.yml`: phenology, lịch thời vụ và các cổng phân loại. GEE/CRS/`resolution_m` lấy từ `THONG_SO_DU_AN.yml`.

Không tạo nhãn âm bằng điểm ngẫu nhiên. Nhãn dương AKS có thể hỗ trợ tập huấn luyện sau khi qua kiểm tra tương thích, nhưng không thay thế nhãn dương/âm địa phương và không được đưa vào fold hiệu chỉnh ngưỡng hoặc outer test.

Sau khi chạy giải đoán, review `roi_field_area_candidate` trên ảnh phù hợp và bằng kiến thức thực địa. Chỉ bản đã duyệt mới được lưu thành `roi_field_area.geojson`.

## Chuẩn bị Quy trình 1

Trong `01_THIET_KE_LAY_MAU/01_DAU_VAO`:

- `soil_type.geojson` — tùy chọn, polygon có trường phân loại;
- `sampling.yml` — số mẫu, spacing và tham số cLHS. CRS, GEE project, `resolution_m`, `covariate_support_buffer_m` và ngày covariates lấy từ `THONG_SO_DU_AN.yml`.

ROI_field_area được Bước 0 kiểm tra và giữ tại một vị trí duy nhất. Quy trình 1 và Quy trình 2 đọc trực tiếp tệp canonical này; không tự chép ROI từ dự án khác.

Cấu hình mặc định `clhs_backend: auto` ưu tiên lõi từ gói CRAN `clhs`; nếu phải fallback, QA ghi rõ `python_clhs_like`. Toàn bộ FULL vẫn là thiết kế lai vì có spatial infill và short-lag.

## Nguyên tắc quản lý

- Mỗi khu vực, mùa/năm ảnh hoặc cấu hình khác nhau nên có dự án riêng.
- Xác nhận CRS phù hợp địa phương; EPSG 32649 không phải mặc định đúng cho mọi nơi.
- Nếu đổi ROI, CRS, thời gian ảnh hoặc định nghĩa Soil Type sau khi đã tạo covariates/PCA, nên tạo phiên bản dự án mới.
- Không sửa `_NOI_BO`, không sao chép PCA hoặc `sample_cLHS` giữa dự án.
- Nhấp `0_KIEM_TRA_DU_AN.bat` để biết dự án đang thiếu file nào.
