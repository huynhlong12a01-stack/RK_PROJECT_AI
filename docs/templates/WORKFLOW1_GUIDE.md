# Hướng dẫn Quy trình 1 — Thiết kế lấy mẫu

## Chuẩn bị

- Hoàn tất Bước 0 để có `ROI_field_area` đã duyệt.
- Đặt `soil_type.geojson` trong `01_DAU_VAO` nếu có.
- Kiểm tra `sampling.yml`: CRS, GEE project, ngày covariates, số điểm và tham số `clhs_*`.
- Không đặt `sample_actual.csv` tại đây.

## Chạy

Nhấp `CHAY_THIET_KE_LAY_MAU.bat`. Ứng dụng tải/tái sử dụng CHIRPS, DEM, NDVI, Slope và TWI; tạo PC1–PC5/PCA reference; xử lý Soil Type; tạo lõi REDUCED; rồi bổ sung điểm không gian cho FULL.

Với backend CRAN:

- `clhs_core` là đầu ra trực tiếp của optimizer `clhs`;
- REDUCED là lõi này;
- FULL cộng `spatial_infill` và `short_lag`, nên là thiết kế lai;
- QA phải ghi `is_original_clhs_optimizer_core=true` và `is_pure_original_clhs_design=false`.

Nếu QA ghi `python_clhs_like`/`lhs_core`, optimizer gốc đã không chạy; đọc `fallback_reason`. cLHS là tối ưu ngẫu nhiên, không chứng minh nghiệm toàn cục và không tự giải quyết khả năng tiếp cận.

Giữ đủ PC1–PC5 từ năm covariates là phép quay full-rank, không phải giảm chiều. Lưới 10 m chỉ để căn chỉnh/xuất; không biến CHIRPS, SRTM hoặc MERIT Hydro thành dữ liệu thật 10 m.

## Kết quả

- `sample_cLHS_REDUCED`: lõi, `priority=1`.
- `sample_cLHS_FULL`: REDUCED cộng bổ sung không gian, `priority=2` cho phần thêm.
- `sampling_QA.json`: backend, method flags, candidate population, coverage, PCA và nesting.
- QA FULL/REDUCED: đọc riêng; không dùng để tuyên bố hai phương án tương đương.
- `covariate_provenance.json`: nguồn, thời gian, native/effective resolution.

Nếu đổi vị trí khi đi thực địa, ghi GPS thật vào `sample_actual.csv`; không sửa file kế hoạch.

Xem [hướng dẫn đầy đủ](../../docs/02_THIET_KE_LAY_MAU.md).

## Nguồn phương pháp

- [CRAN clhs manual](https://cran.r-project.org/web/packages/clhs/clhs.pdf)
- Minasny & McBratney (2006): [DOI 10.1016/j.cageo.2005.12.009](https://doi.org/10.1016/j.cageo.2005.12.009)
