# PHU_YEN_MOCK — Quy trình 1 an toàn

Đây là bước kiểm thử phần mềm. **Không chạy riêng script hoặc BAT thiết kế mẫu.** Từ thư mục gốc dự án, chỉ chạy:

`00_CHAY_MOCK_AN_TOAN.bat`

## Cấu hình

- `..\THONG_SO_DU_AN.yml` là nguồn duy nhất cho CRS, GEE project, `resolution_m: 30`, `covariate_support_buffer_m` và ngày covariates.
- `01_DAU_VAO/sampling.yml` chỉ chứa số điểm, spacing và tham số `clhs_*`; không sửa lại cấu hình chung tại đây.
- Soil Type Việt Nam được đọc từ `shared_data/soil_type_vietnam/raw/VN_soil_type.geojson`.
- ROI lấy trực tiếp từ nguồn canonical của Bước 0.

## Nội dung được kiểm thử

Orchestrator tải/tái sử dụng CHIRPS, DEM, NDVI, Slope và TWI; tạo PC1–PC5/PCA reference; xử lý Soil Type; tạo REDUCED rồi bổ sung điểm không gian cho FULL.

Ứng dụng chỉ tái sử dụng PCA khi `pca_summary.json` v2 chứng minh đúng 5 raw covariates, sidecar tải, PCA reference và PC1–PC5 bằng SHA-256. Trạng thái STALE/UNVERIFIED sẽ làm mock dừng fail-closed thay vì dùng artefact cũ.


Khi backend CRAN chạy thành công:

- `clhs_core` là đầu ra trực tiếp của optimizer `clhs`;
- REDUCED là lõi này;
- FULL cộng `spatial_infill` và `short_lag`, nên là thiết kế lai;
- FULL và REDUCED không được tuyên bố có chất lượng tương đương.

Nếu QA ghi `python_clhs_like`/`lhs_core`, optimizer gốc đã không chạy và phải đọc `fallback_reason`.

Giữ đủ PC1–PC5 từ năm covariates là phép quay full-rank, không phải giảm chiều. Lưới 30 m của mock chỉ để căn chỉnh/xuất; không biến CHIRPS, SRTM hoặc MERIT Hydro thành dữ liệu thật 30 m.

Kết quả mock không được dùng để đi thực địa hoặc đưa vào dự án sản xuất. Xem [hướng dẫn Quy trình 1](../../../docs/02_THIET_KE_LAY_MAU.md) để áp dụng cho dự án thật.

- Workflow 1 khóa SHA-256 Soil Type, trường phân loại, code-map và raster nhóm đất; provenance nguồn quốc gia được ghi để audit nhưng giấy phép chưa rõ không tự chặn test cục bộ.
