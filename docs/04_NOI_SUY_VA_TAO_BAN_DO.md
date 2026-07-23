# Quy trình 2 — Nội suy và tạo bản đồ

## Điều kiện để bắt đầu

Quy trình 2 sử dụng lại sản phẩm của Quy trình 1. Trước khi chạy cần có:

- Bước 0 đã phê duyệt nguồn canonical `00_XAC_LAP_VUNG_MIA/01_DAU_VAO/roi_field_area.geojson`;
- `THONG_SO_DU_AN.yml` hợp lệ và `sampling.yml` có cấu hình thiết kế phù hợp;
- PC1–PC5 của Quy trình 1;
- `pca_model_reference.json` được tạo từ cùng covariates của Quy trình 1;
- `sample_actual.csv` có mã và tọa độ thực tế. Có thể để trống toàn bộ chỉ tiêu để chạy giai đoạn chuẩn bị predictor; cần ít nhất một chỉ tiêu số mới chạy mô hình và tạo bản đồ.
- `indicator_metadata.yml` có đúng phương pháp, đơn vị và `confirmed: true` cho chỉ tiêu cần chạy. Nếu chưa xác nhận, engine chỉ cho phép sản phẩm trạng thái nháp và khóa phân hạng/khuyến cáo.

Không cần ép vị trí thực tế trùng với `sample_cLHS`. Không cần xóa 22 điểm ngoài ROI của AKS_2026 chỉ vì chúng ở ngoài vùng; chúng được kiểm tra coverage và được ghi nhận trong QA.

## Cách chạy

Nhấp đúp `02_NOI_SUY_BAN_DO/CHAY_NOI_SUY_BAN_DO.bat`. Ứng dụng chạy lần lượt:

1. Chuẩn hóa `sample_actual.csv`, kiểm tra tọa độ, chỉ tiêu và trạng thái trong/ngoài ROI.
2. Kiểm chứng chuỗi hash/sidecar của năm raw covariates, PC1–PC5, lưới, ROI và PCA reference của Quy trình 1.
3. Tạo mask phân tích ngay trên máy bằng `mask PC Quy trình 1 + các ô raster chứa sample_actual`, rồi tạo lại PC1–PC5 từ raw covariates đã kiểm chứng bằng **PCA reference đã đóng băng**. Đây là đường chính và không truyền tọa độ, mã mẫu hay hình học mẫu ra ngoài.
4. Chỉ khi raw covariates thực sự thiếu tại ô cần phân tích, tạo bounding envelope của ROI đã duyệt, nới theo `covariate_support_buffer_m` trong `THONG_SO_DU_AN.yml`, rồi dùng GEE để tải bổ sung. Hình học này không chứa dữ liệu mẫu, phải qua privacy gate trước `ee.Initialize` và chỉ là miền tải dữ liệu, không phải miền dự báo.

Trước khi nội suy, ứng dụng đồng bộ cấu hình, xác lập lại CRS và kiểm cả raw provenance lẫn PCA lineage. Nếu ROI, GEE project, CRS, độ phân giải, khoảng ngày, raster thô, PC1–PC5 hoặc PCA reference đã đổi, Quy trình 2 dừng và yêu cầu chạy lại Quy trình 1.

5. Nếu có Soil Type, xây biến phân loại; lớp đã map nhưng thiếu mẫu được gom vào `Other`, còn ngoài coverage polygon là `Unmapped`.
6. Kiểm tra schema giữa điểm và raster predictor.
7. Nếu chưa có kết quả lab, ghi QA/predictor hoàn chỉnh, kết thúc thành công ở `WAITING_LAB` và không tạo bản đồ. Nếu đã có kết quả, chạy riêng từng chỉ tiêu.
8. Xuất bản đồ và báo cáo, sau đó mask toàn bộ GeoTIFF cuối về `ROI_field_area` đã duyệt.

## Phân biệt các miền không gian

| Miền | Dùng để làm gì | Có phải miền bản đồ cuối không? |
|---|---|---|
| Mask PC Quy trình 1 | Giữ nguyên miền predictor đã kiểm chứng của thiết kế mẫu | Là phần nền để tạo predictor, nhưng bản đồ cuối vẫn mask theo ROI |
| Mask phân tích cục bộ | Mask PC Quy trình 1 cộng đúng các ô chứa `sample_actual` | Không tự mở rộng bản đồ ra ngoài ROI |
| Bounding envelope ROI + fixed buffer | Chỉ dùng để tải raw covariates dự phòng từ GEE | Không |
| `ROI_field_area` đã duyệt | Miền xuất bản đồ dinh dưỡng cuối | Có |

## Hai giai đoạn của Quy trình 2

- **Chuẩn bị trước lab:** chạy ngay sau khi có tọa độ thật để kiểm tra 22 điểm ngoài ROI, tái tạo PCA cục bộ từ raw covariates Quy trình 1, chỉ tải support an toàn nếu raw thật sự thiếu, chuẩn bị Soil Type và ghi QA. Kết quả hợp lệ là `WAITING_LAB`; chưa có GeoTIFF dinh dưỡng.
- **Nội suy sau lab:** dán số vào chính `sample_actual.csv`, xác nhận đơn vị/phương pháp trong `indicator_metadata.yml`, rồi chạy lại. Chỉ giai đoạn này mới fit mô hình và xuất bản đồ.

`0_KIEM_TRA_DU_AN.bat` phải hiển thị predictor/PCA trước hướng dẫn nhập lab: nếu PCA chưa `VERIFIED`, chạy chuẩn bị Quy trình 2 trước; khi predictor đã sẵn sàng mới chờ lab.

## Hai nhánh mô hình

### `PC_ONLY`

Sử dụng PC1–PC5 làm covariates xu thế. Nhánh này luôn được chạy và là mốc so sánh khi đánh giá việc bổ sung Soil Type.

### `PC_PLUS_SOIL`

Chỉ chạy khi có `soil_type.geojson`. Mô hình dùng PC1–PC5 cùng các biến giả Soil Type. Mã nhóm đất không được đưa vào hồi quy như biến số liên tục.

Không mặc định `PC_PLUS_SOIL` tốt hơn. Chọn nhánh có bằng chứng tốt hơn qua spatial cross-validation, độ ổn định, cảnh báo ngoại suy và chẩn đoán residual/variogram.

## Vai trò của các điểm ngoài ROI

- Điểm có predictor đầy đủ có thể tham gia tập phát triển mô hình và các fold outer held-out. Chúng không tự động trở thành tập kiểm định thực địa độc lập.
- Mỗi điểm ngoài ROI phải được ghi rõ quan hệ với target population, trạng thái covariate support và kết quả AOA; không tự loại chỉ vì ngoài ROI, cũng không tự chấp nhận chỉ vì có đủ PC.
- Điểm thiếu PC nhưng còn đủ raw covariates được xử lý cục bộ; GEE chỉ được dùng nếu raw thật sự thiếu và vùng tải đã qua privacy gate.
- PCA không được fit lại cho riêng nhóm ngoài ROI.
- Các điểm này mở rộng tập hiệu chuẩn nhưng cũng có thể làm tăng khác biệt miền; cần xem QA và area of applicability.
- Mọi raster giao cho người dùng trong `02_KET_QUA/maps` được mask về `ROI_field_area`. Mask phân tích cục bộ và bounding envelope dùng để tải không mở rộng miền bản đồ dinh dưỡng cuối.

## Regression Kriging trong ứng dụng

Với mỗi chỉ tiêu và mỗi nhánh predictor, engine:

1. mô hình hóa thành phần xu thế từ covariates;
2. phân tích phần dư theo không gian;
3. chọn/kiểm tra variogram và tham số lân cận trong nested spatial cross-validation; các dự báo outer held-out là đánh giá ngoài-fold của quá trình phát triển mô hình, không phải kiểm định thực địa độc lập;
4. kriging phần dư nếu có cấu trúc hợp lệ;
5. cộng xu thế và phần dư để tạo dự báo cuối.

Nếu residual variogram chỉ thể hiện pure nugget, engine chuyển sang regression-only thay vì ép một cấu trúc không gian giả. Đây là cơ chế bảo vệ, không phải lỗi chạy.

## Kết quả ở đâu

```text
02_NOI_SUY_BAN_DO/02_KET_QUA/
  maps/
    TEN_CHI_TIEU/
      PC_ONLY/
      PC_PLUS_SOIL/       <- chỉ có khi dùng Soil Type
  reports/
    TEN_CHI_TIEU/
      PC_ONLY/
      PC_PLUS_SOIL/
  tables/
```

Trong mỗi thư mục bản đồ có thể có dự báo đã/không clamp, clipping mask, area of applicability, dissimilarity và residual kriging standard deviation tùy kết quả mô hình. `final_roi_mask_summary.json` xác nhận chính sách mask ROI và liệt kê các file được xuất.

## Không nên làm

- Không chạy Quy trình 2 bằng file `sample_cLHS` thay cho tọa độ thực tế.
- Không thay PCA reference sau khi đã tạo kế hoạch và dữ liệu hỗ trợ.
- Không chọn bản đồ chỉ vì nhìn mượt hơn.
- Không xem residual kriging standard deviation là toàn bộ độ bất định dự báo.
- Không diễn giải lớp dinh dưỡng theo ngưỡng nông học khi chưa xác nhận phương pháp lab, đơn vị, cây trồng và nguồn ngưỡng địa phương.

## Cổng Soil Type trước nội suy

Quy trình 2 kiểm tra `soil_lineage_ready` trước cả preflight mẫu. Hash file Soil Type, `soil_group_field`, encoding nominal, code-map và hash raster Workflow 1 phải còn khớp; nếu không, workflow dừng và yêu cầu chạy lại Quy trình 1. Không được thay Soil Type ở giữa hai quy trình rồi tái sử dụng PCA/kế hoạch cũ như thể lineage vẫn hợp lệ.

Trong `PC_PLUS_SOIL`, `Unmapped` chỉ nghĩa là ngoài coverage polygon; `Other` chỉ nghĩa là các lớp đã map nhưng thiếu sample support và được gộp kỹ thuật. `Soil_Group_Code.tif` giữ hai trạng thái riêng để audit. Các raster `SoilDummy_*` chỉ được tạo cho hiệu ứng có mẫu để ước lượng; nhóm xuất hiện trên miền dự báo nhưng không có mẫu được ghi rõ trong QA và tạm dùng hiệu ứng nhóm tham chiếu, không được diễn giải như đã học được hiệu ứng đất của nhóm đó.
