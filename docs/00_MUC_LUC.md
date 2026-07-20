# Tài liệu sử dụng RK_R_Project

Dự án đi theo đúng trình tự thực tế: xác lập vùng canh tác mía, thiết kế mẫu, lấy mẫu/nhận kết quả lab, rồi nội suy.

## Ba giai đoạn không được trộn lẫn

```text
Có ROI_field_area? ---- có ----> kiểm tra/phê duyệt ROI
        |
       chưa
        v
ROI_search + nhãn mía/không-mía đã kiểm chứng
        |
        v
BƯỚC 0: chuỗi thời gian vệ tinh -> mô hình -> ROI ứng viên
        |                              |
        |                         review thủ công
        +------------------------------+
                        |
                        v
                 ROI_field_area
                        |
                        v
QUY TRÌNH 1: covariates -> PCA -> lõi cLHS -> bổ sung không gian
                        |
              +---------+---------+
              v                   v
 sample_cLHS_REDUCED      sample_cLHS_FULL
              ___________  ___________/
                          /
                   đi thực địa
                          |
                          v
       sample_actual.csv + kết quả lab
                          |
                          v
QUY TRÌNH 2: nội suy -> QA -> bản đồ trong ROI_field_area
```

- ROI ứng viên ở Bước 0 chưa phải ROI chính thức. Chỉ `roi_field_area.geojson` đã review mới đi tiếp.
- `sample_cLHS_*` là đề xuất trước thực địa; không dán kết quả lab vào đó.
- `sample_actual.csv` chứa GPS đã lấy thật và kết quả trung bình của mẫu; ứng dụng không tách tầng đất.
- Thư viện AKS `positive_reference_only` không thay thế nhãn dương và âm tại địa phương.

## Bắt đầu nhanh

1. Nhấp `CREATE_NEW_PROJECT.bat` và mở dự án vừa tạo.
2. Kiểm tra `THONG_SO_DU_AN.yml` ở thư mục gốc dự án: đây là nguồn duy nhất cho CRS, GEE project, `resolution_m`, `covariate_support_buffer_m` và ngày tải covariates.
3. Nhấp `0_KIEM_TRA_DU_AN.bat`.
4. Ở Bước 0, cung cấp một trong hai bộ đầu vào:
   - `roi_field_area.geojson` đã được xác nhận; hoặc
   - `roi_search.geojson` + bản sao của `sugarcane_labels_template.csv` đã đổi tên thành `sugarcane_labels.csv` và có cả hai lớp.
5. Nếu phải giải đoán, xác nhận lịch thời vụ trong `interpretation.yml`, chạy Bước 0, review ứng viên và chạy lại với `roi_field_area.geojson` đã duyệt.
6. Thêm Soil Type nếu có, kiểm tra các tham số cLHS trong `sampling.yml` và chạy Quy trình 1.
7. Chọn FULL hoặc REDUCED để đi thực địa.
8. Cập nhật `sample_actual.csv` và `indicator_metadata.yml`, rồi chạy Quy trình 2.

`THONG_SO_DU_AN.yml` không thay thế các tệp đầu vào chuyên môn; người dùng vẫn phải cung cấp ROI/nhãn, Soil Type nếu có, tham số thiết kế, phenology và kết quả lab đúng giai đoạn.

## Nơi người dùng được thao tác

```text
projects/TEN_DU_AN/
  THONG_SO_DU_AN.yml  <- nguồn duy nhất cho CRS, GEE, lưới, buffer support và ngày covariates
  00_XAC_LAP_VUNG_MIA/
    01_DAU_VAO/       <- ROI field/search, nhãn và interpretation.yml
    02_KET_QUA/       <- ứng viên và QA; không dùng trực tiếp nếu chưa review
  01_THIET_KE_LAY_MAU/
    01_DAU_VAO/       <- Soil Type tùy chọn và sampling.yml cho tham số cLHS
    02_KET_QUA/       <- FULL, REDUCED và QA
  02_NOI_SUY_BAN_DO/
    01_DAU_VAO/       <- sample_actual.csv + indicator_metadata.yml
    02_KET_QUA/       <- maps, reports, tables
  _NOI_BO/            <- không chỉnh sửa thủ công
```

## Danh mục hướng dẫn

1. [Tạo dự án mới](01_TAO_DU_AN_MOI.md)
2. [Bước 0 — Xác lập vùng mía](templates/WORKFLOW0_GUIDE.md)
3. [Thiết kế lấy mẫu](02_THIET_KE_LAY_MAU.md)
4. [Chuẩn bị sample_actual](03_CHUAN_BI_SAMPLE_ACTUAL.md)
5. [Nội suy và tạo bản đồ](04_NOI_SUY_VA_TAO_BAN_DO.md)
6. [Đọc kết quả và kiểm tra QA](05_DOC_KET_QUA_VA_QA.md)
7. [Xử lý lỗi thường gặp](06_XU_LY_LOI.md)
8. [Cơ sở khoa học và thư viện chuyên ngành](07_CO_SO_KHOA_HOC.md)

Hướng dẫn Bước 0 nằm trong [template WORKFLOW0](templates/WORKFLOW0_GUIDE.md). Cơ sở kiểm định kỹ thuật nằm tại [SCIENTIFIC_VALIDATION.md](SCIENTIFIC_VALIDATION.md).
