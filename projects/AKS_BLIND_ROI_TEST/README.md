# AKS_BLIND_ROI_TEST

## Cách chạy phép thử mù AKS

Nhấp `00_CHAY_THU_MU_AKS.bat`. Ứng dụng tự:

1. kiểm tra hash/biên nhận của đúng 1.000 điểm mía tại gói tham chiếu AKS;
2. tạo `roi_search.geojson` từ convex hull của 1.000 điểm cộng buffer 5 km;
3. từ chối chạy nếu có `roi_field_area` trong đầu vào inference;
4. tải chuỗi Sentinel-1/Sentinel-2 của 8 quý hoàn tất và tạo `sugarcane_positive_support_score.tif`;
5. tạo `roi_field_area_candidate.geojson` chỉ để review;
6. sau khi candidate đã tồn tại mới mở ROI gốc để ghi báo cáo đối chiếu hậu nghiệm.

Đây là phép thử tái dựng từ điểm dương, không phải bản đồ phân loại nhị phân. Không có nhãn không-mía nên điểm hỗ trợ không phải xác suất, các chỉ số overlap không phải precision/recall và candidate không được tự đưa vào cLHS.

Các kết quả cần xem nằm tại `00_XAC_LAP_VUNG_MIA/02_KET_QUA`.

Phép thử vùng rộng dùng lưới 20 m vì các band Sentinel-2 red-edge/SWIR chính có support gốc 20 m; ô tải 5 km và 8 prototype giúp tránh timeout. Đây là cấu hình riêng của phép thử, không tuyên bố ranh thực địa có độ chính xác 20 m.

Lượt chuẩn đầu tiên đã tải cả score và mask GEE để đối chứng. Lõi v2 hiện chỉ tải score rồi tạo mask cục bộ; báo cáo `local_postprocess_equivalence.json` ghi IoU 0,99993 so với mask GEE chuẩn, giúp giảm gần một nửa số lượt tải ở lần chạy sau.

`THONG_SO_DU_AN.yml` ở thư mục gốc là nguồn duy nhất cho `crs_mode`/`crs_epsg`, `gee_project_id`, `resolution_m`, `covariate_support_buffer_m` và ngày tải covariates. Với `crs_mode: auto`, CRS được xác định từ ROI và đồng bộ giữa ba giai đoạn; không giữ EPSG 32649 cho dự án ở múi khác.

Đây không phải tệp duy nhất người dùng cần sửa. ROI/nhãn, phenology, Soil Type, tham số cLHS, `sample_actual.csv` và metadata lab vẫn nằm ở các tệp chuyên trách. Người dùng chỉ thao tác trong các thư mục `00`, `01`, `02` cùng `THONG_SO_DU_AN.yml`; không chỉnh `_NOI_BO`.

## Bước 0 — Xác lập ROI_field_area

Chọn một trong hai cách:

- Đã có ranh giới mía: đặt `00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson`.
- Chưa có ranh giới: đặt `roi_search.geojson`, sao chép `sugarcane_labels_template.csv` thành `sugarcane_labels.csv` rồi điền cả `label=1` và `label=0` đã kiểm chứng; hoàn thiện phenology/cổng phân loại trong `interpretation.yml`.

Khi giải đoán, phải xác nhận lịch thời vụ địa phương và chỉ dùng các kỳ ảnh đã hoàn tất. Kết quả `roi_field_area_candidate` là vùng ứng viên; review thủ công trên ảnh và bằng kiến thức thực địa, sau đó lưu bản đã duyệt thành `roi_field_area.geojson` và chạy lại Bước 0.

Thư viện AKS chỉ là `positive_reference_only`, không phải mô hình nhị phân tiền huấn luyện. Nó không thay thế nhãn dương/âm địa phương và không được dùng trong fold chọn ngưỡng hoặc outer test.

## Quy trình 1 — Thiết kế lấy mẫu

Đặt `soil_type.geojson` nếu có và kiểm tra số mẫu, spacing cùng tham số cLHS trong `sampling.yml`. CRS, GEE, lưới và ngày covariates không sửa tại đây mà lấy từ `THONG_SO_DU_AN.yml`. Bước 0 cung cấp ROI đã duyệt.

Với `clhs_backend: auto`, ứng dụng ưu tiên gói CRAN `clhs`:

- REDUCED là lõi `clhs_core` nếu backend gốc chạy thành công;
- FULL là REDUCED cộng `spatial_infill` và `short_lag`;
- toàn bộ FULL là thiết kế lai, không phải cLHS thuần;
- nếu fallback, QA ghi `python_clhs_like` và lõi `lhs_core`.

FULL và REDUCED không được xem là có chất lượng tương đương. Giá trị `resolution_m` chỉ đặt lưới tính toán/xuất và không nâng độ phân giải gốc của covariates.

## Quy trình 2 — Nội suy

Sau thực địa, cập nhật `02_NOI_SUY_BAN_DO/01_DAU_VAO/sample_actual.csv`:

- mỗi mẫu một dòng;
- `code`, `lat`, `lon` là GPS thực tế;
- các cột sau là kết quả lab dạng số và để trống khi chưa có;
- mọi kết quả được xem là giá trị trung bình của mẫu, không tách tầng.

Xác nhận phương pháp/đơn vị trong `indicator_metadata.yml`, rồi chạy `CHAY_NOI_SUY_BAN_DO.bat`. Điểm ngoài ROI chỉ được dùng sau kiểm tra target population, support và AOA; chúng không tự động là validation set. Bản đồ cuối mask theo `ROI_field_area`.

## Kiểm tra trạng thái

Nhấp `0_KIEM_TRA_DU_AN.bat`. Dòng trạng thái cho biết đang chờ ROI/nhãn, chờ review vùng ứng viên, chờ thiết kế mẫu, chờ lab hay sẵn sàng nội suy.

Nếu đổi ROI, CRS, thời gian ảnh hoặc lịch thời vụ sau khi đã tạo sản phẩm trung gian, hãy tạo phiên bản dự án mới hoặc chạy lại có kiểm soát.
