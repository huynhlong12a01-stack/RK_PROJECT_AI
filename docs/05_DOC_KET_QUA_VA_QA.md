# Đọc kết quả và kiểm tra QA

## Bước 0: kiểm tra ROI_field_area

Mở `00_XAC_LAP_VUNG_MIA/02_KET_QUA/field_area_QA.json`:

- nếu dùng ROI có sẵn, trạng thái phải xác nhận hình học/CRS/hash và đủ điều kiện chuyển sang thiết kế;
- nếu giải đoán, phải có cả nhãn dương và âm địa phương, nhóm không gian và ba vai trò train/calibration/outer-test tách biệt;
- `phenology_alignment_confirmed` phải đúng, nguồn lịch mùa vụ phải được ghi và chỉ dùng quý đã hoàn tất;
- gói AKS phải ghi `positive_reference_only`, `binary_classifier_trained=false`;
- precision/recall/F1 là outer spatial evaluation nội bộ, không phải independent field validation;
- `roi_field_area_candidate` vẫn chờ review; chỉ `roi_field_area.geojson` đã duyệt mới được Quy trình 1 dùng.

Lưới xác suất/ứng viên 10 m là lưới tính toán/xuất, không phải bằng chứng mọi ranh giới và predictor có support thật 10 m.

## Quy trình 1: kiểm tra kế hoạch lấy mẫu

Mở `01_THIET_KE_LAY_MAU/02_KET_QUA/sampling_QA.json` và kiểm tra:

- `nested_design` và `reduced_is_subset_of_full` phải là `true`;
- `FULL_count`, `REDUCED_count` khớp số dòng CSV;
- `FULL_role_counts` và số requested/actual có đúng số lõi, spatial infill và short-lag;
- `minimum_spacing_m`, `inner_buffer_m`, `random_seed` khớp cấu hình;
- `soil_quotas` hợp lý so với diện tích/phân bố loại đất;
- nếu `backend_used=r_clhs_cran`: `method_id=clhs_r_core_spatially_augmented_nested_design`, `is_original_clhs_optimizer_core=true`, `is_pure_original_clhs_design=false`, và chỉ `clhs_core` thuộc phạm vi optimizer gốc;
- nếu `backend_used=python_clhs_like`: `is_original_clhs_optimizer_core=false`, lõi là `lhs_core`, và phải đọc `fallback_reason`;
- `raw_covariate_coverage.raw_covariates.coverage_fraction` phải đạt ngưỡng; AKS_2026 hiện là 1,0;
- PCA phải ghi `n_input=5`, `n_retained=5`, `dimension_reduction_applied=false`, frozen reference và SHA-256;
- đọc `sampling_QA_FULL.json` và `sampling_QA_REDUCED.json` riêng; các chỉ số mô tả không chứng minh hai phương án có độ chính xác tương đương;
- đọc `covariate_provenance.json`; không diễn giải CHIRPS/DEM/Slope/TWI như nguồn chi tiết 10 m;
- không có cảnh báo điểm nằm ngoài ROI thiết kế.

Lần chạy AKS đã kiểm tra dùng CRAN `clhs` 0.9.2, 4 × 20.000 vòng, 200.000/660.661 ứng viên hợp lệ; REDUCED 79 lõi và FULL 105 điểm (79 + 16 + 10). Đây là provenance của lần chạy, không phải hằng số cho dự án khác hoặc lần chạy lại.

CSV phục vụ danh sách thực địa; GeoJSON phục vụ kiểm tra trên GIS. `priority=1` là lõi REDUCED, `priority=2` là phần bổ sung của FULL.

## Quy trình 2: QA đầu vào và predictor

Các báo cáo kỹ thuật nằm trong `_NOI_BO/work/interpolation/qa`. Người dùng có thể đọc nhưng không sửa:

- `preflight_summary.json`: tổng số mẫu, số trong/ngoài ROI, số điểm có PC đầy đủ, số điểm cần tải hỗ trợ và các chỉ tiêu đã có kết quả.
- `sample_roi_status.csv`: trạng thái từng điểm so với ROI và coverage.
- `outside_sample_review.csv` trong thư mục đầu vào: chỉ xuất hiện khi có điểm ngoài ROI; đây là bảng người dùng xác nhận target population/sampling support, không phải file kết quả lab.
- `sensitivity_plan.json`: kế hoạch so sánh ALL_ACTUAL, INSIDE_ROI_ONLY và nhóm đã xác nhận; không dùng nhóm ngoài ROI làm validation giả.
- `pca_support_point_coverage.csv`/`pca_support_summary.json`: xuất hiện khi phải bổ sung covariates/PCA.
- `pca_current_provenance.json`: hash PC1–PC5 và hash frozen PCA reference; chỉ trạng thái `verified` mới được tái sử dụng như PCA đáng tin cậy.
- `soil_predictor_summary.json`: nhóm tham chiếu, nhóm giữ lại, nhóm `Other` và các biến giả.
- `soil_predictor_point_groups.csv`: nhóm Soil Type gán cho từng mẫu.
- `raster_schema_current.json`: kiểm tra predictor ở điểm và raster có cùng tên, loại và phạm vi hợp lệ.

Với AKS_2026 hiện tại, QA đã ghi nhận 94 mẫu, gồm 72 trong ROI và 22 ngoài ROI; cả 94 có PC1–PC5 đầy đủ tại lần kiểm tra gần nhất. Con số này phải được kiểm tra lại sau mỗi lần thay đổi `sample_actual.csv`.

## Chọn giữa `PC_ONLY` và `PC_PLUS_SOIL`

Không chọn theo độ mượt hay màu sắc. So sánh cùng chỉ tiêu theo thứ tự:

1. Có outer held-out spatial cross-validation hợp lệ hay không; đây là đánh giá ngoài-fold trong phát triển mô hình, không phải kiểm định thực địa độc lập.
2. RMSE/MAE thấp hơn và ME gần 0 hơn.
3. `R²_pred` ngoài mẫu có dương và ổn định qua các lần lặp hay không.
4. RK có thực sự cải thiện so với regression-only và ordinary kriging hay không.
5. Variogram có singular, chạm giới hạn range hoặc gần pure nugget hay không.
6. Tỷ lệ ngoài area of applicability và tỷ lệ bị clamp có lớn hay không.
7. Nhánh Soil có phụ thuộc quá mức vào nhóm ít mẫu/`Other` hay không.

Nếu Soil Type không cải thiện đánh giá không gian hoặc làm tăng cảnh báo, dùng `PC_ONLY` là lựa chọn hợp lý hơn.

## Ý nghĩa các sản phẩm thường gặp

| Sản phẩm | Cách hiểu |
|---|---|
| `RK_final_*` | Dự báo cuối; có thể đã clamp theo cấu hình |
| `RK_final_unclamped_*` | Dự báo chưa clamp để audit ngoại suy |
| `RK_clipping_mask_*` | Ô bị cắt thấp/cao |
| `area_of_applicability_*` | Miền covariates đủ tương đồng với dữ liệu hiệu chuẩn |
| `dissimilarity_index_*` | Mức khác biệt so với miền hiệu chuẩn |
| `RK_uncertainty_STD_*` | Độ lệch chuẩn của residual kriging, không phải total uncertainty |
| `evaluation.json` | Chỉ số, cảnh báo, hard failures và phương pháp dự báo thực tế |
| báo cáo HTML | Tổng hợp trực quan chẩn đoán và chất lượng |

Khi pure nugget, dự báo cuối có thể là regression-only và không có raster uncertainty. Không nên xem việc thiếu raster uncertainty trong trường hợp này là lý do tự tạo một lớp giả.

## Tiêu chí tối thiểu trước khi sử dụng bản đồ

- Đúng chỉ tiêu, phương pháp và đơn vị phòng thí nghiệm.
- Không có lỗi schema, tọa độ trùng xung đột hoặc chỉ tiêu bị đọc nhầm kiểu.
- Outer held-out spatial CV đủ số mẫu/fold và không có hard failure; không gắn nhãn “independent field validation” nếu không có tập mẫu độc lập thực sự.
- Kiểm tra sai số theo đơn vị thật của chỉ tiêu, không chỉ nhìn grade.
- Đánh giá bản đồ chưa clamp, clipping mask và AOA cùng bản đồ chính.
- Xác nhận file trong `maps` đã được mask về ROI qua `final_roi_mask_summary.json`.
- So sánh với hiểu biết đất, địa hình và quản lý canh tác; điều tra các vùng bất thường.
- Ghi lại phiên bản ROI, thời gian covariates, file mẫu, ngày nhận lab và nhánh mô hình được chọn.

## Giới hạn khi ra quyết định dinh dưỡng

Bản đồ thể hiện ước lượng không gian của kết quả phân tích đất theo phương pháp đã dùng. Nó không tự động là bản đồ khuyến cáo phân bón. Việc phân hạng thiếu/đủ/thừa và khuyến cáo liều lượng còn cần ngưỡng đã được phê duyệt cho cây mía, điều kiện địa phương, đơn vị/phương pháp lab, năng suất mục tiêu và hiệu chuẩn nông học.
