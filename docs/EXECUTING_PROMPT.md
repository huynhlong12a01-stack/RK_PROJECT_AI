# Prompt thực thi cho AI agent

Tài liệu này dành cho Codex/AI agent khi vận hành một dự án trong RK_R_Project. Luồng chính luôn gồm Bước 0 và hai workflow theo project; các script engine ở root chỉ là hạ tầng kỹ thuật.

## 1. Quy tắc

- Không sửa ROI, Soil Type, sample_actual hoặc kết quả lab gốc để làm model đẹp hơn.
- Không thay tọa độ thực tế bằng tọa độ sample_cLHS.
- Không xóa mẫu ngoài ROI chỉ dựa vào ranh giới.
- Không refit PCA trên sample_actual.
- Không dùng mã Soil Type như biến liên tục.
- Không tắt cross-validation hoặc scientific gate.
- Không chọn model chỉ vì RMSE nhỏ nhất.
- Không gọi outer spatial CV là independent field validation.
- Không gọi residual kriging SD là total uncertainty.
- Không tạo ngưỡng dinh dưỡng hoặc liều phân khi thiếu crop, region, method và unit.
- Không chỉnh thư mục _NOI_BO trừ khi đang sửa lỗi engine có chủ đích.
- Kiểm tra git status trước và sau; không commit nếu người dùng chưa yêu cầu.

## 2. Chọn dự án

Danh sách project nằm trong projects. Với mỗi project, đọc:

    projects/TEN_DU_AN/README.md
    projects/TEN_DU_AN/THONG_SO_DU_AN.yml
    projects/TEN_DU_AN/00_XAC_LAP_VUNG_MIA/HUONG_DAN.md
    projects/TEN_DU_AN/01_THIET_KE_LAY_MAU/HUONG_DAN.md
    projects/TEN_DU_AN/02_NOI_SUY_BAN_DO/HUONG_DAN.md
    projects/TEN_DU_AN/_NOI_BO/config/project.yml

Đọc thêm:

    docs/00_MUC_LUC.md
    docs/SCIENTIFIC_VALIDATION.md
    knowledge/README.md
    knowledge/CATALOG.md

## 3. Entry point chuẩn

Kiểm tra trạng thái:

    powershell -ExecutionPolicy Bypass -File projects/TEN_DU_AN/RUN.ps1 status

Xác lập vùng mía:

    powershell -ExecutionPolicy Bypass -File projects/TEN_DU_AN/RUN.ps1 interpret

Thiết kế mẫu:

    powershell -ExecutionPolicy Bypass -File projects/TEN_DU_AN/RUN.ps1 design

Nội suy:

    powershell -ExecutionPolicy Bypass -File projects/TEN_DU_AN/RUN.ps1 interpolate

Các BAT người dùng nhấp chỉ gọi các action trên; đầu vào và kết quả luôn nằm trong đúng thư mục của từng dự án.

## 4. Bước 0 và Workflow 1

Bước 0 nhận `roi_field_area.geojson`, hoặc `roi_search.geojson` cùng nhãn dương/âm đã kiểm chứng. Không cho ROI ứng viên chưa review đi tiếp; không coi gói AKS `positive_reference_only` là binary pretrained model; classifier phải qua phenology gate và spatial holdout riêng.

Kiểm tra:

    projects/TEN_DU_AN/THONG_SO_DU_AN.yml
    projects/TEN_DU_AN/00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson
    projects/TEN_DU_AN/01_THIET_KE_LAY_MAU/01_DAU_VAO/soil_type.geojson
    projects/TEN_DU_AN/01_THIET_KE_LAY_MAU/01_DAU_VAO/sampling.yml

`THONG_SO_DU_AN.yml` là nguồn duy nhất cho CRS, GEE, `resolution_m`, `covariate_support_buffer_m` và ngày covariates. ROI bắt buộc; Soil Type tùy chọn; `sampling.yml` chứa số mẫu, spacing và tham số cLHS. Không coi `THONG_SO_DU_AN.yml` là tệp duy nhất người dùng được sửa.

Sau run, đọc:

    projects/TEN_DU_AN/01_THIET_KE_LAY_MAU/02_KET_QUA/sample_cLHS_REDUCED.csv
    projects/TEN_DU_AN/01_THIET_KE_LAY_MAU/02_KET_QUA/sample_cLHS_FULL.csv
    projects/TEN_DU_AN/01_THIET_KE_LAY_MAU/02_KET_QUA/sampling_QA.json

Kiểm tra REDUCED là tập con FULL, mọi điểm trong ROI, mã/tọa độ duy nhất, Soil Type coverage, minimum distance, covariate coverage và provenance.

Ưu tiên lõi CRAN `clhs`. Chỉ `clhs_core` là đầu ra direct optimizer; FULL là hybrid sau spatial augmentation. Nếu fallback `python_clhs_like`, giữ đúng method metadata và lý do. Không hứa REDUCED có chất lượng tương đương FULL.

## 5. Workflow 2

Đầu vào kết quả mẫu người dùng chỉnh:

    projects/TEN_DU_AN/02_NOI_SUY_BAN_DO/01_DAU_VAO/sample_actual.csv
    projects/TEN_DU_AN/02_NOI_SUY_BAN_DO/01_DAU_VAO/indicator_metadata.yml

Kết quả lab chỉ nằm trong `sample_actual.csv`; `indicator_metadata.yml` chỉ chứa định nghĩa phương pháp/đơn vị. Ba cột bắt buộc là code, lat, lon. Mỗi target phải có số liệu numeric và metadata lab rõ trước khi phát hành.

Preflight cần báo:

- số dòng/mã trùng;
- tọa độ ngoài ROI;
- missing covariates/PCA;
- nhóm Soil Type và Other;
- target có dữ liệu, method/unit;
- trạng thái PCA reference.

Nếu lab còn trống, dừng sau bước chuẩn bị predictor và báo đang chờ lab; đây không phải lỗi.

Khi chạy model, so PC_ONLY và PC_PLUS_SOIL nếu có. Điểm ngoài ROI có thể tham gia fit sau QA; map cuối mask ROI.

Đọc output công khai:

    projects/TEN_DU_AN/02_NOI_SUY_BAN_DO/02_KET_QUA/maps
    projects/TEN_DU_AN/02_NOI_SUY_BAN_DO/02_KET_QUA/reports
    projects/TEN_DU_AN/02_NOI_SUY_BAN_DO/02_KET_QUA/tables

Model/log chi tiết ở projects/TEN_DU_AN/_NOI_BO/work chỉ dùng chẩn đoán.

## 6. Scientific gate

Chỉ coi một model đạt Internal QA khi có outer held-out nested spatial CV, target metadata phù hợp, baseline comparison, residual/variogram diagnostics, AOA/clipping diagnostics và không có hard failure.

Nếu pure nugget fallback, ghi regression-only; không gọi đó là RK improvement.

Với 22 điểm ngoài ROI, báo target population/support, covariate AOA/dissimilarity và sensitivity analysis. Không gọi chúng là validation set.

## 7. Knowledge retrieval

Kiểm tra knowledge:

    .\_UNG_DUNG\tools\run_rag_smoke_test.ps1
    .\_UNG_DUNG\tools\run_rag_build_curated_index.ps1

Tra cứu:

    .\_UNG_DUNG\tools\run_rag_query.ps1 -Query "điểm ngoài ROI và area of applicability" -TopK 8

Chỉ dùng claim có doc_id/DOI/URL và đúng phạm vi. Không suy citation.

## 8. Báo cáo cuối

Nêu rõ:

- project và workflow đã chạy;
- input đã dùng và target;
- sample count, trong/ngoài ROI, Soil Type/Other;
- FULL/REDUCED hoặc PC_ONLY/PC_PLUS_SOIL được chọn và lý do;
- metric outer held-out và baseline;
- variogram/prediction method;
- AOA, clipping, uncertainty type;
- output công khai;
- cảnh báo, hard failure và việc người dùng còn phải làm;
- không gọi bản đồ là khuyến cáo phân bón nếu chưa có hiệu chuẩn nông học.
