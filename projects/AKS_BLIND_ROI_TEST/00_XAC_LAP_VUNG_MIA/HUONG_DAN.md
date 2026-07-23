# Bước 0 — Xác lập vùng mía

Cấu hình chung lấy từ `THONG_SO_DU_AN.yml` ở gốc dự án. Với `crs_mode: auto`, ứng dụng tự xác định múi UTM từ tâm ROI field/search và đồng bộ CRS cho cả ba giai đoạn. Nếu phạm vi rộng hơn 6° kinh độ, ứng dụng dừng; chỉ chuyển sang `crs_mode: manual` trong `THONG_SO_DU_AN.yml` sau khi chuyên gia GIS xác nhận `crs_epsg`. GEE project và `resolution_m` cũng chỉ sửa tại tệp chung này.

Bước này tạo `ROI_field_area` đã được xác nhận trước khi tải covariates và thiết kế mẫu.

## Trường hợp A — đã có ranh giới vùng mía

Đặt `00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson`, rồi nhấp `CHAY_XAC_LAP_VUNG_MIA.bat`.

Ứng dụng kiểm tra CRS, hình học, diện tích và hash. Các bước thiết kế mẫu và nội suy đọc trực tiếp nguồn duy nhất 01_DAU_VAO/roi_field_area.geojson; ứng dụng không tạo bản sao ROI ở Quy trình 1.

## Trường hợp B — chưa có ranh giới vùng mía

Đặt trong `01_DAU_VAO`:

- `roi_search.geojson`: ranh giới huyện/tỉnh cần tìm;
- sao chép `sugarcane_labels_template.csv` thành `sugarcane_labels.csv` rồi điền điểm đã kiểm chứng;
- `interpretation.yml`: chuỗi thời gian, phenology và cổng QA; GEE/CRS/lưới lấy từ `THONG_SO_DU_AN.yml`.

Cột nhãn:

```text
code,lat,lon,label,group_id,label_source,observation_date,reviewer,note
```

- `label=1`: chắc chắn là mía;
- `label=0`: chắc chắn không phải mía, ưu tiên các lớp dễ nhầm;
- `group_id`: lô/khối không gian để tránh leakage;
- nguồn, ngày quan sát và người review không được để mơ hồ.

Chỉ nhãn dương là chưa đủ cho mô hình nhị phân. Không gán điểm nền ngẫu nhiên thành âm tính.

## Cổng thời gian và phenology

Chuỗi Sentinel-1/2 phải dùng các quý đã hoàn tất. `feature_end_date_exclusive` là ngày đầu của quý kế tiếp; ví dụ `2026-07-01` chỉ dùng dữ liệu đến hết 30/06/2026. Các band dùng hậu tố tương đối `T01...T08` để tránh ghép nhầm năm lịch.

Trước huấn luyện/phân loại, đặt:

- `phenology_alignment_confirmed: true`;
- `crop_calendar_source`: nguồn lịch mùa vụ địa phương;
- `crop_calendar_note`: ghi chú cách chuỗi thời gian bao phủ các pha sinh trưởng.

Nếu chưa qua cổng này, kết quả không đủ điều kiện trở thành ROI ứng viên cho thiết kế mẫu.

## Trường hợp chỉ có nhãn mía đã kiểm chứng

Mặc định workflow vẫn dừng vì nhãn dương không xác định được ranh giới quyết định mía/không-mía. Chỉ khi người dùng chủ động đặt `allow_positive_only_screening: true`, ứng dụng mới chạy chế độ sàng lọc hỗ trợ dương:

- dùng khoảng cách đa biến tới các prototype dương theo các fold không gian;
- xuất `sugarcane_positive_support_score.tif`, không đặt tên là probability;
- không báo precision, recall, F1 hoặc accuracy;
- không dùng điểm nền ngẫu nhiên, WorldCover hay pixel ngoài ROI làm nhãn âm;
- candidate bắt buộc review và luôn có `approved_for_sample_design: false`.
- từ điểm số, ứng dụng tạo mask cục bộ bằng mode kernel tròn bán kính 1 pixel và cổng vùng liên thông; không tải lại cùng phép tính GEE lần thứ hai.

Chế độ này thích hợp cho kiểm tra/tạo danh sách vùng ứng viên khi chưa có nhãn âm. Muốn có bản đồ phân loại và đánh giá sai số, vẫn phải bổ sung nhãn mía/không-mía địa phương và thiết kế đánh giá độc lập phù hợp.

## Mô hình và kiểm định

Ứng dụng dùng Sentinel-2 Surface Reflectance + Cloud Score+, Sentinel-1 VV/VH và đặc trưng địa hình. Sentinel-1 GRD trên Earth Engine đã ở dB nên không log thêm. Pixel thiếu predictor không được đổi thành 0; WorldCover chỉ là predictor, không phải mặt nạ cứng.

Nhãn được tách theo nhóm không gian thành train, fold hiệu chỉnh ngưỡng và outer held-out test. Đây là kiểm định nội bộ không gian, không phải kiểm định thực địa độc lập.

## Kết quả và review bắt buộc

Kết quả có thể gồm:

- `sugarcane_probability.tif`;
- `roi_field_area_candidate.tif/.geojson`;
- `field_area_QA.json`;
- model/reference card trong `_NOI_BO/work/field_area`.

Ứng viên không tự động trở thành ROI. Hãy đối chiếu ảnh cùng thời kỳ, ranh giới lô và hiểu biết thực địa; sửa lỗi bỏ sót/nhầm; lưu bản duyệt thành `roi_field_area.geojson`; chạy lại Bước 0.

Lưới do `resolution_m` quy định chỉ là lưới tính toán/xuất. Nó không chứng minh mọi đặc trưng, ranh giới hoặc độ chính xác đều có support thực ở kích thước đó.

## Tái sử dụng AKS_2026

AKS cung cấp vị trí dương tính tin cậy nhưng chưa có lớp âm đã kiểm chứng. Gói này là `positive_reference_only`, không phải binary pretrained model. Chỉ được ghép vào **tập train** khi schema đặc trưng, thời kỳ, phenology và miền môi trường tương thích. Dự án đích vẫn cần cả hai lớp địa phương; tham chiếu AKS không được vào fold hiệu chỉnh ngưỡng hoặc outer test.

## Những điều bị ngăn

- cùng một lô xuất hiện ở train và test;
- cùng fold vừa chọn ngưỡng vừa báo cáo chất lượng;
- nhãn âm ngẫu nhiên;
- missing-to-zero hoặc WorldCover hard mask;
- dùng ảnh/quý chưa hoàn tất;
- gọi outer spatial test là independent validation;
- đưa ROI ứng viên chưa review vào cLHS.

## Nguồn chính

- [Sentinel-1 GRD](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_S1_GRD), [Sentinel-2 SR Harmonized](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_S2_SR_HARMONIZED) và [Cloud Score+](https://developers.google.com/earth-engine/datasets/catalog/GOOGLE_CLOUD_SCORE_PLUS_V1_S2_HARMONIZED).
- Wang et al. (2020), phenology mía đa cảm biến: [DOI 10.1016/j.rse.2020.111951](https://doi.org/10.1016/j.rse.2020.111951).
- Olofsson et al. (2014), đánh giá độ chính xác/diện tích: [DOI 10.1016/j.rse.2014.02.015](https://doi.org/10.1016/j.rse.2014.02.015).
