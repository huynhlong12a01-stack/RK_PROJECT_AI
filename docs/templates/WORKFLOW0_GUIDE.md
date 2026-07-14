# Bước 0 — Xác lập vùng mía

Bước này tạo `ROI_field_area` đã được xác nhận trước khi tải covariates và thiết kế mẫu.

## Trường hợp A — đã có ranh giới vùng mía

Đặt `00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson`, rồi nhấp `CHAY_XAC_LAP_VUNG_MIA.bat`.

Ứng dụng kiểm tra CRS, hình học, diện tích, hash và tạo bản tương thích kỹ thuật cho Quy trình 1. `roi.geojson` của dự án cũ chỉ được nhận để di chuyển có kiểm soát; người dùng nên quản lý một nguồn chính là `roi_field_area.geojson`.

## Trường hợp B — chưa có ranh giới vùng mía

Đặt trong `01_DAU_VAO`:

- `roi_search.geojson`: ranh giới huyện/tỉnh cần tìm;
- `sugarcane_labels.csv`: điểm đã kiểm chứng;
- `interpretation.yml`: GEE project, chuỗi thời gian, CRS và cổng QA.

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

Lưới 10 m là lưới tính toán/xuất. Nó không chứng minh mọi đặc trưng, ranh giới hoặc độ chính xác đều có support thực ở 10 m.

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
