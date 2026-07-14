# AI Agent Guide — RK_R_Project

Tài liệu này định hướng AI agent. Hướng dẫn người dùng bắt đầu tại `docs/00_MUC_LUC.md`.

## Luồng chính

Mỗi project có ba giai đoạn:

1. `00_XAC_LAP_VUNG_MIA`: dùng `ROI_field_area` có sẵn, hoặc `ROI_search` + nhãn đã kiểm chứng để tạo vùng ứng viên và yêu cầu review.
2. `01_THIET_KE_LAY_MAU`: ROI đã duyệt + Soil Type tùy chọn -> covariates -> PCA reference -> REDUCED/FULL.
3. `02_NOI_SUY_BAN_DO`: `sample_actual` + lab -> predictor -> PC_ONLY/PC_PLUS_SOIL -> validation -> maps/reports/tables.

Entry point:

```text
projects/TEN_DU_AN/RUN.ps1 status
projects/TEN_DU_AN/RUN.ps1 interpret
projects/TEN_DU_AN/RUN.ps1 design
projects/TEN_DU_AN/RUN.ps1 interpolate
```

BAT người dùng chỉ gọi các action này. Không dùng `run_rk.bat` hoặc `output/agent_runs` làm entry point mặc định.

## Phân quyền thư mục

Người dùng chỉnh:

```text
projects/TEN_DU_AN/00_XAC_LAP_VUNG_MIA/01_DAU_VAO
projects/TEN_DU_AN/01_THIET_KE_LAY_MAU/01_DAU_VAO
projects/TEN_DU_AN/02_NOI_SUY_BAN_DO/01_DAU_VAO/sample_actual.csv
projects/TEN_DU_AN/02_NOI_SUY_BAN_DO/01_DAU_VAO/indicator_metadata.yml
```

Ứng dụng xuất vào các thư mục `02_KET_QUA`. Mã, work, cache và model trung gian nằm trong `_NOI_BO`; không yêu cầu người dùng sửa.

## Scientific invariants

- `roi_field_area_candidate` không tự được phê duyệt; chỉ ROI đã review đi vào thiết kế.
- AKS reference là `positive_reference_only`, không phải binary pretrained model. Dự án đích cần nhãn dương/âm địa phương, phenology gate và outer spatial test riêng.
- Chỉ `clhs_core` từ backend CRAN là đầu ra optimizer gốc. FULL là hybrid sau spatial infill/short-lag; fallback `lhs_core` phải giữ nhãn cLHS-like.
- cLHS là simulated annealing ngẫu nhiên, không chứng minh global optimum; tọa độ không nằm trong objective gốc.
- REDUCED là tập con FULL; không hứa chất lượng tương đương.
- PCA reference fit ở workflow 1 và đóng băng; năm covariates -> PC1–PC5 không phải giảm chiều.
- Lưới 10 m không nâng native/effective resolution của nguồn thô hơn.
- `sample_actual` dùng GPS thật; điểm ngoài ROI cần target population, support, covariate coverage, AOA và sensitivity. Chúng không tự động là validation set.
- Soil Type là categorical; `Other` là nhóm kỹ thuật.
- So PC_ONLY và PC_PLUS_SOIL bằng outer held-out nested spatial CV cùng baseline; outer CV không phải independent field validation.
- Pure nugget dẫn đến regression-only fallback.
- RK residual SD không phải total calibrated uncertainty.
- Target phải có method/unit; nutrient map không tự động là fertilizer recommendation.

## Tài liệu bắt buộc đọc

```text
docs/EXECUTING_PROMPT.md
docs/SCIENTIFIC_VALIDATION.md
knowledge/README.md
knowledge/CATALOG.md
```

## Thay đổi code

- Kiểm tra git status trước/sau và giữ thay đổi của người dùng.
- Dùng template trong `docs/templates` khi thay generator.
- Chạy parse/smoke test liên quan.
- Không commit dữ liệu riêng tư, cache hoặc sản phẩm dự án.
- Chỉ commit/push khi người dùng yêu cầu.

Chi tiết thực thi nằm trong `docs/EXECUTING_PROMPT.md`.
