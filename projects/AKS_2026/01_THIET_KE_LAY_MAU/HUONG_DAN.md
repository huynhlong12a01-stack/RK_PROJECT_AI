# AKS_2026 — Quy trình 1: thiết kế lấy mẫu

## Chuẩn bị

- Hoàn tất Bước 0 để có `ROI_field_area` đã duyệt.
- Giữ `soil_type.geojson` nếu sử dụng Soil Type và kiểm tra `soil_group_field`.
- Kiểm tra CRS, GEE, `resolution_m` và ngày covariates trong `..\THONG_SO_DU_AN.yml`.
- Kiểm tra `sampling.yml`, đặc biệt số lõi, spacing và tham số `clhs_*`; không sửa lại thông số chung tại đây.
- Không đặt `sample_actual.csv` tại đây.

## Chạy và ý nghĩa phương pháp

Nhấp `CHAY_THIET_KE_LAY_MAU.bat`. Ứng dụng tải/tái sử dụng CHIRPS, DEM, NDVI, Slope, TWI; tạo PC1–PC5/PCA reference; rồi thiết kế hai phương án.

Ứng dụng chỉ tái sử dụng PCA khi `pca_summary.json` v2 chứng minh đúng 5 raw covariates, sidecar tải, PCA reference và PC1–PC5 bằng SHA-256. Trạng thái STALE/UNVERIFIED sẽ tự chặn Quy trình 2 và yêu cầu chạy lại Quy trình 1.


Lần chạy đã kiểm tra hiện tại dùng CRAN `clhs` 0.9.2, 4 lần khởi tạo × 20.000 vòng; quần thể optimizer là 200.000 ô lấy đều không hoàn lại từ 660.661 ô hợp lệ. REDUCED có 79 `clhs_core`; FULL có 105 điểm gồm 79 lõi, 16 infill và 10 short-lag. Luôn đọc lại QA nếu chạy lại cấu hình.

Khi `backend_used=r_clhs_cran`:

- điểm `clhs_core` là đầu ra trực tiếp từ gói CRAN `clhs`;
- REDUCED là lõi này;
- FULL cộng `spatial_infill` và `short_lag`;
- FULL là thiết kế lai, không phải cLHS thuần.

Khi QA ghi `backend_used=python_clhs_like`, optimizer gốc không chạy; lõi đổi thành `lhs_core` và phải đọc `fallback_reason`.

cLHS là tối ưu ngẫu nhiên, không chứng minh nghiệm tối ưu toàn cục. PC1–PC5 và Soil Type factor nằm trong objective; tọa độ chỉ phục vụ lọc ứng viên, chọn restart theo spacing và bổ sung không gian. Thiết kế không thay thế kiểm tra tiếp cận thực địa. FULL/REDUCED không được coi là tương đương về chất lượng.

PC1–PC5 từ năm covariates là phép quay full-rank, không phải giảm chiều. Lưới 10 m không làm CHIRPS, SRTM hay MERIT Hydro thành nguồn thật 10 m.

## Kết quả cần kiểm

- `sample_cLHS_REDUCED`: lõi, `priority=1`;
- `sample_cLHS_FULL`: lõi + bổ sung, `priority=2` cho phần thêm;
- `sampling_QA.json`: backend, method flags, số yêu cầu/thực tế, nesting, coverage và PCA;
- QA riêng FULL/REDUCED và `covariate_provenance.json`.

Nếu đổi chỗ ngoài thực địa, ghi GPS thật vào `sample_actual.csv`; không sửa file kế hoạch.

Hướng dẫn đầy đủ: [docs/02_THIET_KE_LAY_MAU.md](../../../docs/02_THIET_KE_LAY_MAU.md).

- Workflow 1 khóa SHA-256 Soil Type, trường phân loại, code-map và raster nhóm đất; sửa Soil Type sau bước này buộc chạy lại Workflow 1.
