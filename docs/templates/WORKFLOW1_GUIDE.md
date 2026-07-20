# Hướng dẫn Quy trình 1 — Thiết kế lấy mẫu

## Chuẩn bị

- Hoàn tất Bước 0 để có `ROI_field_area` đã duyệt.
- Đặt `soil_type.geojson` trong `01_DAU_VAO` nếu có.
- Kiểm tra CRS, GEE, `resolution_m` và ngày covariates trong `THONG_SO_DU_AN.yml`.
- Kiểm tra `sampling.yml`: số điểm, spacing và tham số `clhs_*`; không sửa lại các thông số chung tại đây.
- Không đặt `sample_actual.csv` tại đây.

## Chạy

Nhấp `CHAY_THIET_KE_LAY_MAU.bat`. Ứng dụng tải/tái sử dụng CHIRPS, DEM, NDVI, Slope và TWI; tạo PC1–PC5/PCA reference; xử lý Soil Type; tạo lõi REDUCED; rồi bổ sung điểm không gian cho FULL.

Ứng dụng chỉ tái sử dụng PCA khi `pca_summary.json` v2 chứng minh đúng 5 raw covariates, sidecar tải, PCA reference và PC1–PC5 bằng SHA-256. Trạng thái STALE/UNVERIFIED sẽ tự chặn Quy trình 2 và yêu cầu chạy lại Quy trình 1.


Với backend CRAN:

- `clhs_core` là đầu ra trực tiếp của optimizer `clhs`;
- REDUCED là lõi này;
- FULL cộng `spatial_infill` và `short_lag`, nên là thiết kế lai;
- QA phải ghi `is_original_clhs_optimizer_core=true` và `is_pure_original_clhs_design=false`.

Nếu QA ghi `python_clhs_like`/`lhs_core`, optimizer gốc đã không chạy; đọc `fallback_reason`. cLHS là tối ưu ngẫu nhiên, không chứng minh nghiệm toàn cục và không tự giải quyết khả năng tiếp cận.

Giữ đủ PC1–PC5 từ năm covariates là phép quay full-rank, không phải giảm chiều. `resolution_m` chỉ đặt lưới căn chỉnh/xuất; không biến CHIRPS, SRTM hoặc MERIT Hydro thành dữ liệu thật ở độ phân giải đó.

## Kết quả

- `sample_cLHS_REDUCED`: lõi, `priority=1`.
- `sample_cLHS_FULL`: REDUCED cộng bổ sung không gian, `priority=2` cho phần thêm.
- `sampling_QA.json`: backend, method flags, candidate population, coverage, PCA và nesting.
- QA FULL/REDUCED: đọc riêng; không dùng để tuyên bố hai phương án tương đương.
- `covariate_provenance.json`: nguồn, thời gian, native/effective resolution.

Nếu đổi vị trí khi đi thực địa, ghi GPS thật vào `sample_actual.csv`; không sửa file kế hoạch.

Xem [hướng dẫn đầy đủ](../../../docs/02_THIET_KE_LAY_MAU.md).

## Nguồn phương pháp

- [CRAN clhs manual](https://cran.r-project.org/web/packages/clhs/clhs.pdf)
- Minasny & McBratney (2006): [DOI 10.1016/j.cageo.2005.12.009](https://doi.org/10.1016/j.cageo.2005.12.009)

Workflow 1 ghi `soil_group_summary.json` schema 3.0.0 để khóa SHA-256 Soil Type, `soil_group_field`, encoding/code-map và raster nhóm đất. `Unmapped` được giữ riêng; `Other` không dùng trong thiết kế cLHS. Thay đổi Soil Type sau đó buộc chạy lại Workflow 1.
