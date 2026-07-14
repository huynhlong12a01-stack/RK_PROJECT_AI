# Chính sách kiểm định khoa học cho dự án bản đồ dinh dưỡng

Tài liệu này mô tả các điều kiện để kết quả được dùng trong nội bộ. Grade của engine là Internal QA grade, không phải chứng nhận công bố khoa học, kiểm định độc lập ngoài thực địa hoặc khuyến cáo phân bón.

## 1. Phạm vi ba giai đoạn

### Xác lập vùng mía

Đầu vào là `ROI_field_area` đã được cung cấp, hoặc `ROI_search` cùng nhãn mía/không-mía đã kiểm chứng tại địa phương. Trường hợp giải đoán dùng chuỗi Sentinel-1/2 theo các quý đã hoàn tất và bị chặn nếu chưa xác nhận sự phù hợp với lịch thời vụ.

Thư viện AKS là `positive_reference_only`, không phải mô hình nhị phân tiền huấn luyện. Nó chỉ có thể bổ sung tập train sau gate schema/thời kỳ/phenology/miền môi trường; dự án đích vẫn cần cả hai lớp địa phương. Fold hiệu chỉnh ngưỡng và outer test không nhận dữ liệu tham chiếu chuyển vùng.

`roi_field_area_candidate` là sản phẩm sàng lọc. Chỉ ranh giới đã được người dùng review và lưu thành `roi_field_area.geojson` mới đủ điều kiện cho thiết kế mẫu. Outer spatial test của classifier là kiểm định nội bộ không gian, không phải kiểm định thực địa độc lập.

### Thiết kế lấy mẫu

Đầu vào người dùng: `ROI_field_area` đã duyệt, Soil Type tùy chọn và `sampling.yml`.

Dòng xử lý: tải covariates, chuẩn hóa, fit PCA reference, tạo lõi conditioned Latin hypercube, rồi xuất REDUCED và FULL sau bổ sung không gian.

Khi `backend_used=r_clhs_cran`, chỉ vai trò `clhs_core` là đầu ra trực tiếp của optimizer gốc trong gói CRAN `clhs`. REDUCED là lõi; FULL thêm `spatial_infill` và `short_lag`, nên toàn bộ thiết kế là hybrid và phải ghi `is_pure_original_clhs_design=false`. Nếu backend fallback là `python_clhs_like`, lõi không được gọi là cLHS optimizer gốc và QA phải lưu lý do.

cLHS dùng simulated annealing/nghiệm ngẫu nhiên nên không chứng minh tối ưu toàn cục, không bảo đảm khả năng tiếp cận, minimum spacing hay độ chính xác bản đồ nếu đứng một mình. Với năm covariates và PC1–PC5, PCA là chuẩn hóa cộng phép quay trực giao toàn hạng, không phải giảm chiều.

REDUCED là tập con lõi. FULL bổ sung spatial infill và short-lag. Không tuyên bố REDUCED bảo đảm chất lượng tương đương FULL; phải so QA feature-space, spatial coverage và variogram support.

### Nội suy

Đầu vào người dùng: sample_actual.csv với code, lat, lon và các chỉ tiêu lab.

Tọa độ là nơi đã lấy thực tế, không phải điểm kế hoạch. Mẫu ngoài ROI không tự bị loại; chúng chỉ được dùng khi có predictor hợp lệ, cùng target population/support và không tạo ngoại suy nguy hiểm. Bản đồ cuối mask về ROI.

PCA reference của workflow 1 được tái sử dụng; không fit PCA mới trên sample_actual. Khi có Soil Type, engine so PC_ONLY và PC_PLUS_SOIL. Soil Type là categorical; Other là nhóm coverage kỹ thuật, không phải một lớp đất đồng nhất.

## 2. Nested spatial cross-validation

Metric xếp hạng phải đến từ outer held-out nested spatial CV:

    outer spatial folds
      -> giữ outer-test chưa tham gia fit/tuning của fold
      -> inner spatial CV trên outer-train
      -> chọn transform, variogram family và neighborhood
      -> fit lại trên outer-train
      -> dự báo outer-test
      -> lặp theo cấu hình

Dùng cụm outer held-out. Không gọi outer folds là independent field validation. Independent probability validation cần bộ mẫu thu thập riêng theo thiết kế xác suất để ước lượng map accuracy và sai số chuẩn design-based.

Random CV và spatial k-means chỉ là chẩn đoán phụ nếu profile quy định nested spatial block là tiêu chí chính.

Không tự động ACCEPT khi thiếu outer spatial CV, outer R² dự báo không dương hoặc inner tuning thường xuyên không tìm được candidate hợp lệ.

## 3. Chống leakage

Transform target, lựa chọn mô hình, variogram và neighborhood phải được lựa chọn trong inner CV của outer-train. Outer-test chỉ dùng tính metric của fold.

Sau đánh giá, production model được fit lại trên toàn bộ mẫu. Điều này không làm mất tính held-out của các metric đã tính, nhưng production model không có một external test set mới.

PCA reference là một phần của data pipeline. Trong dự án hiện tại, reference đã được fit từ population covariates ở workflow 1 và phải đóng băng cho workflow 2.

## 4. Variogram và fallback

Engine tạo classical/robust variogram, variogram cloud, directional diagnostics và candidate table. Candidate singular hoặc không hội tụ không được chọn.

Nếu không có residual spatial structure hợp lệ, engine phải dùng pure-nugget/regression-only fallback, đặt residual correction bằng 0 và báo prediction method rõ. Không dùng bộ range/sill mặc định để tạo cảm giác có cấu trúc không gian.

Anisotropy hiện là chẩn đoán; việc fit anisotropic model cần chuyên gia xem directional variogram và xác nhận hướng/ratio.

## 5. Baseline và lựa chọn mô hình

Mỗi chỉ tiêu cần so ít nhất:

- naive/mean baseline;
- regression-only;
- Ordinary Kriging;
- Regression Kriging PC_ONLY;
- Regression Kriging PC_PLUS_SOIL khi Soil Type đủ support.

Không chọn chỉ vì RMSE nhỏ nhất. Cùng xem MAE, bias/ME, R² dự báo, độ ổn định qua repeat, chênh lệch so baseline, variogram, clipping, AOA, sample support theo Soil Type và tính hợp lý không gian.

PC_PLUS_SOIL không được ưu tiên mặc định. Nhóm Other hoặc lớp ít mẫu phải có cảnh báo.

## 6. Điểm ngoài ROI và AOA

Ranh giới ROI không phải tiêu chí duy nhất cho tính hợp lệ. Với điểm ngoài ROI, cần đánh giá:

- thuộc cùng quần thể/vùng quản lý mục tiêu;
- cùng độ sâu và quy trình mẫu;
- covariates đầy đủ;
- covariate dissimilarity/Area of Applicability;
- khoảng cách tới ROI và điểm kế hoạch nếu có;
- sensitivity analysis khi loại/giữ các điểm đáng ngờ.

22 điểm di chuyển thuận tiện hiện tại là dữ liệu hiệu chỉnh đã điều chỉnh thực địa, không phải independent validation.

AOA lớn hoặc clipping lớn phải chặn tự động ACCEPT theo ngưỡng dự án.

## 7. Uncertainty

RK uncertainty STD chỉ là residual kriging standard deviation. Nó chưa bao gồm uncertainty của trend, model selection, covariates, tham số variogram, sai số lab và toàn bộ back-transform.

Không gọi lớp này là total predictive uncertainty hoặc 90/95 percent prediction interval. Quantile hiển thị chỉ dùng phân màu.

Muốn công bố prediction interval phải xác định cách kết hợp các thành phần uncertainty và kiểm định calibration, coverage, sharpness, bias hai phía cùng số quan sát interval hợp lệ.

## 8. Phương pháp lab và target metadata

Tên cột phải có định nghĩa không mơ hồ. Ví dụ nên phân biệt:

- pH_H2O và pH_KCl;
- P_Olsen_mgkg, P_Bray1_mgkg, P_Mehlich3_mgkg;
- K_available_mgkg và K_exchangeable_cmolkg;
- ECe_dSm và EC theo tỷ lệ chiết khác;
- SOC và OM theo phương pháp xác định.

sample_actual.csv vẫn giữ cấu trúc thân thiện. Tuy nhiên trước khi phát hành, mỗi target phải có metadata về canonical name, unit, analytical method/extractant, reporting basis, detection limit, valid range, lab batch, crop/region và nguồn phân cấp.

Không tự map một alias mơ hồ như P, K, OM hoặc EC sang profile chuyên biệt. Không gộp kết quả khác phương pháp/đơn vị nếu chưa harmonize có căn cứ.

## 9. Scale, raster manifest và provenance

Lưới output 10 m chỉ là computational grid. Native scale hiện gồm NDVI 10 m, SRTM/Slope khoảng 30 m, MERIT Hydro 92,77 m và CHIRPS khoảng 5.566 m. Resampling không tạo chi tiết mới.

Raster continuous dùng bilinear khi phù hợp; categorical dùng nearest-neighbour. Soil class code không được dùng như số liên tục.

Mọi run cần lưu asset ID, phiên bản, date range, temporal reducer, cloud threshold, CRS, export scale, resampling, công thức TWI/NDVI và PCA center/scale/loadings.

Manifest dự án do workflow quản lý ở projects/TEN_DU_AN/_NOI_BO/config. Người dùng không chỉnh thủ công; các thông tin công bố phải được copy vào report/QA.

## 10. Output và trạng thái

Output công khai:

    projects/TEN_DU_AN/00_XAC_LAP_VUNG_MIA/02_KET_QUA
    projects/TEN_DU_AN/01_THIET_KE_LAY_MAU/02_KET_QUA
    projects/TEN_DU_AN/02_NOI_SUY_BAN_DO/02_KET_QUA

Model/log trung gian:

    projects/TEN_DU_AN/_NOI_BO/work

Ba mức thông tin:

- messages: thông tin vận hành;
- warnings: rủi ro cần xem;
- hard_failures: điều kiện chặn FINAL_ACCEPT.

## 11. Điều kiện chặn tự động ACCEPT

- ROI giải đoán chưa qua phenology gate hoặc vùng ứng viên chưa được review thành `ROI_field_area`;
- classifier thiếu cả nhãn dương và âm đã kiểm chứng tại địa phương;
- thiếu outer held-out spatial CV;
- outer R² dự báo không dương hoặc mô hình kém baseline rõ;
- target thiếu đơn vị/phương pháp lab;
- duplicate coordinate có target xung đột;
- variogram singular, pure nugget không fallback đúng hoặc range chạm giới hạn;
- inner tuning thất bại trên phần lớn outer folds;
- anisotropy mạnh nhưng bị bỏ qua;
- vùng ngoài AOA hoặc clipping vượt hard limit;
- Soil Type phụ thuộc lớp không đủ support;
- residual SD bị diễn giải như prediction interval;
- ngưỡng dinh dưỡng không có nguồn phù hợp cây trồng, vùng, method và unit.

## 12. Giới hạn còn lại

Dự án chưa tự động tạo independent probability validation set, total calibrated predictive uncertainty, anisotropic fit được chuyên gia xác nhận, hoặc khuyến cáo liều phân theo hiệu chuẩn cây mía địa phương.

Cơ sở nguồn và evidence cards nằm trong knowledge/README.md và knowledge/CATALOG.md.
