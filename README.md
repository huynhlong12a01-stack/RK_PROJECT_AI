# RK_R_Project

Ứng dụng có ba giai đoạn nối tiếp: xác lập vùng mía, thiết kế vị trí lấy mẫu và nội suy bản đồ dinh dưỡng từ vị trí thực tế/kết quả lab.

## Bắt đầu

1. Nhấp `CREATE_NEW_PROJECT.bat`.
2. Nhập tên dự án.
3. Mở `projects/TEN_DU_AN/README.md` và làm theo trạng thái của dự án.

Dự án hiện tại: `projects/AKS_2026`.

## Cấu trúc một dự án

```text
TEN_DU_AN/
  0_KIEM_TRA_DU_AN.bat
  00_XAC_LAP_VUNG_MIA/
    01_DAU_VAO/          roi_field_area.geojson
                         hoặc roi_search.geojson + sugarcane_labels.csv
    02_KET_QUA/          ROI ứng viên, QA và provenance
  01_THIET_KE_LAY_MAU/
    01_DAU_VAO/          soil_type.geojson tùy chọn, sampling.yml
    02_KET_QUA/          sample_cLHS_FULL/REDUCED và QA
  02_NOI_SUY_BAN_DO/
    01_DAU_VAO/          sample_actual.csv + indicator_metadata.yml
    02_KET_QUA/          maps, reports, tables
  _NOI_BO/               ứng dụng quản lý; người dùng không chỉnh
```

- Bước 0 dùng `ROI_field_area` có sẵn, hoặc giải đoán trong `ROI_search` bằng nhãn mía/không-mía đã kiểm chứng. Bản đồ ứng viên phải được người dùng review trước khi dùng.
- Quy trình 1 tải CHIRPS, DEM, NDVI, Slope và TWI; tạo PCA reference; dùng lõi tối ưu từ gói CRAN `clhs` khi khả dụng; sau đó bổ sung điểm không gian cho phương án FULL. Toàn bộ FULL là thiết kế lai, không phải đầu ra cLHS thuần.
- Quy trình 2 dùng `sample_actual.csv`, tái sử dụng PCA/covariates của Quy trình 1, xử lý Soil Type dạng phân loại và tạo bản đồ đã mask theo `ROI_field_area`.

## Tài liệu

- Hướng dẫn người dùng: [docs/00_MUC_LUC.md](docs/00_MUC_LUC.md)
- Cơ sở kiểm định: [docs/SCIENTIFIC_VALIDATION.md](docs/SCIENTIFIC_VALIDATION.md)
- Knowledge và nguồn khoa học: [knowledge/README.md](knowledge/README.md)

## Lưu ý khoa học

Gói tham chiếu AKS chỉ là `positive_reference_only`, không phải mô hình nhị phân tiền huấn luyện. Dự án giải đoán mới vẫn cần nhãn dương và âm đã kiểm chứng tại địa phương, xác nhận lịch thời vụ và review thủ công ROI ứng viên. FULL và REDUCED là hai mức nguồn lực, không được xem là có chất lượng tương đương. PC1–PC5 từ năm covariates không phải giảm chiều. Lưới 10 m là lưới tính toán; nó không nâng độ phân giải thực của CHIRPS, SRTM hoặc MERIT Hydro.
