# RK_R_Project

Ứng dụng hỗ trợ ba giai đoạn nối tiếp: xác lập vùng mía, thiết kế vị trí lấy mẫu và nội suy bản đồ dinh dưỡng từ vị trí thực tế/kết quả lab.

## Bắt đầu dự án mới

Lần đầu dùng trên một máy, nhấp `CAI_DAT_UNG_DUNG.bat` để tạo môi trường riêng `D:\RK_R_Project\.venv` và kiểm tra các gói R/Python. Các lần sau chỉ cần tạo hoặc mở dự án.

Trong mỗi dự án, `THONG_SO_DU_AN.yml` là nguồn duy nhất cho CRS, Earth Engine project, độ phân giải lưới và khoảng ngày tải covariates. Đây không phải tệp duy nhất người dùng cần sửa: ROI/nhãn, Soil Type, tham số cLHS, phenology và kết quả lab vẫn nằm ở các tệp chuyên trách.

1. Nhấp CREATE_NEW_PROJECT.bat.
2. Nhập tên dự án.
3. Mở projects/TEN_DU_AN/README.md.
4. Nhấp 0_KIEM_TRA_DU_AN.bat để biết chính xác tệp còn thiếu.

Người dùng chỉ cần thao tác trong:

- projects/TEN_DU_AN/: đầu vào, nút chạy và kết quả của từng dự án.
- shared_data/: dữ liệu nền lớn dùng chung, ví dụ Soil Type Việt Nam.
- docs/ và knowledge/: hướng dẫn và cơ sở khoa học để đọc.

Không sửa _UNG_DUNG/, _NOI_BO/ hoặc knowledge-private/ bằng tay.

## Cấu trúc một dự án

    TEN_DU_AN/
      THONG_SO_DU_AN.yml   cấu hình chung: CRS, GEE, lưới, ngày covariates
      0_KIEM_TRA_DU_AN.bat
      00_XAC_LAP_VUNG_MIA/
        01_DAU_VAO/      roi_field_area.geojson
                         hoặc roi_search.geojson + sugarcane_labels.csv
        02_KET_QUA/      ROI ứng viên, QA và provenance
      01_THIET_KE_LAY_MAU/
        01_DAU_VAO/      soil_type.geojson tùy chọn, sampling.yml cho tham số cLHS
        02_KET_QUA/      sample_cLHS_FULL/REDUCED và QA
      02_NOI_SUY_BAN_DO/
        01_DAU_VAO/      sample_actual.csv + indicator_metadata.yml
        02_KET_QUA/      maps, reports, tables
      _NOI_BO/           lõi riêng của dự án; không chỉnh sửa

## Ba luồng thực tế

- Bước 0: nếu đã có roi_field_area.geojson, ứng dụng kiểm tra và dùng ROI này. Nếu chưa có, cung cấp roi_search.geojson cùng nhãn mía/không-mía tại địa phương; ROI ứng viên phải được review trước khi phê duyệt.
- Quy trình 1: tải CHIRPS, DEM, NDVI, Slope và TWI; chuẩn hóa covariates; tạo PCA; dùng lõi tối ưu CRAN clhs; xuất hai phương án FULL và REDUCED. FULL là thiết kế lai có bổ sung không gian, không phải cLHS thuần.
- Quy trình 2: dùng sample_actual.csv chứa tọa độ thực tế và kết quả phân tích trung bình; tái sử dụng covariates/PCA của Quy trình 1; dùng Soil Type như biến phân loại; nội suy và mask bản đồ theo ROI đã duyệt.

sample_cLHS_* chỉ là kế hoạch trước thực địa. Không dán kết quả lab vào các tệp đó.

## Dữ liệu dùng chung

Soil Type Việt Nam nằm tại:

    shared_data/soil_type_vietnam/raw/VN_soil_type.geojson

Tệp lớn và dữ liệu riêng tư chỉ lưu cục bộ, không được đẩy lên GitHub.

## Tài liệu

- [Mục lục hướng dẫn](docs/00_MUC_LUC.md)
- [Cơ sở kiểm định khoa học](docs/SCIENTIFIC_VALIDATION.md)
- [Knowledge và nguồn khoa học](knowledge/README.md)

## Giới hạn khoa học cần giữ

Gói AKS chỉ là `positive_reference_only`, không phải mô hình phân loại mía có thể áp thẳng cho tỉnh khác. Dự án mới vẫn cần nhãn dương và âm đã kiểm chứng tại địa phương, đồng bộ mùa vụ, calibration/test cục bộ và outer spatial CV. FULL và REDUCED là hai mức nguồn lực, không được tuyên bố có chất lượng tương đương. PC1–PC5 từ năm covariates không phải giảm chiều. `resolution_m` chỉ đặt lưới tính toán/xuất; nó không làm tăng độ phân giải thực của CHIRPS, SRTM hoặc MERIT Hydro. Sai số chuẩn phần dư RK không phải toàn bộ bất định dự báo, và bản đồ hàm lượng dinh dưỡng không tự động là bản đồ khuyến cáo liều phân.
