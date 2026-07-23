# Chuẩn bị `sample_actual.csv`

## File này xuất hiện khi nào

Chỉ cập nhật `02_NOI_SUY_BAN_DO/01_DAU_VAO/sample_actual.csv` sau khi đã có vị trí lấy mẫu thực tế. Có thể nhập trước `code`, `lat`, `lon` và để trống chỉ tiêu trong lúc chờ phòng thí nghiệm. Có thể chạy Quy trình 2 ngay để chuẩn bị/kiểm chứng covariates, PCA, Soil Type và QA; ứng dụng sẽ kết thúc bình thường ở `WAITING_LAB`. Mô hình chỉ chạy khi có ít nhất một cột chỉ tiêu chứa giá trị số.

Kết quả lab vẫn chỉ được nhập vào `sample_actual.csv`. File `indicator_metadata.yml` đặt cạnh đó không chứa kết quả; nó ghi phương pháp, đơn vị và quyền phân hạng của từng chỉ tiêu. Ứng dụng mặc định xem sản phẩm là bản đồ hàm lượng nháp cho đến khi mục `confirmed` của chỉ tiêu được đổi thành `true` sau khi đối chiếu phiếu lab.

## Cấu trúc chuẩn

Ba cột đầu bắt buộc:

| Cột | Ý nghĩa | Quy tắc |
|---|---|---|
| `code` | Mã mẫu | Không trống, không trùng |
| `lat` | Vĩ độ | Số thập phân WGS84, từ -90 đến 90 |
| `lon` | Kinh độ | Số thập phân WGS84, từ -180 đến 180 |

Các cột sau là chỉ tiêu phân tích. Template hiện tại gồm:

```text
pH, Humus, CEC, N_total, P_Olsen, P_Bray,
K_available_mgkg, K_exchangeable_cmol,
Ca_exchangeable, Mg_exchangeable, S_available,
B_available, Zn_available, Cu_available,
Mn_available, Fe_available, EC
```

- Để ô trống nếu lab chưa trả kết quả; không nhập `0`, `NA`, dấu gạch hoặc chữ “chưa có”.
- Khi có kết quả, nhập số thuần; không gắn đơn vị vào ô.
- Mỗi mẫu là một dòng và mỗi chỉ tiêu giữ một đơn vị, một phương pháp phân tích nhất quán.
- Toàn bộ giá trị được xem là kết quả trung bình của mẫu. Không thêm cột độ sâu và không tách tầng đất.
- Chỉ giữ cột `P_Olsen` hoặc `P_Bray` có kết quả đúng phương pháp lab; không quy đổi hai phương pháp như thể cùng một đại lượng nếu chưa có hiệu chuẩn.

## Tọa độ thực tế khác điểm thiết kế

`sample_actual.csv` phải chứa GPS tại nơi đã lấy đất, không phải tọa độ của điểm cLHS dự kiến. Giữ mã nhận dạng ổn định để đối chiếu phiếu lấy mẫu và phiếu lab.

Điểm thực tế được phép nằm ngoài ROI, nhưng chỉ được sử dụng an toàn khi:

1. tọa độ hợp lệ và không bị đảo `lat`/`lon`;
2. năm raw covariates có giá trị tại ô chứa điểm, từ dữ liệu Quy trình 1 đã kiểm chứng hoặc từ nhánh GEE dự phòng khi raw thật sự thiếu;
3. PC1–PC5 được tính bằng đúng PCA reference của Quy trình 1;
4. chênh lệch điều kiện môi trường không quá xa miền hiệu chuẩn đến mức trở thành ngoại suy không kiểm soát;
5. QA ghi nhận rõ trạng thái trong/ngoài `ROI_field_area`.

Đường xử lý chính không kết nối GEE. Ứng dụng kiểm chứng hash/sidecar của CHIRPS, DEM, NDVI, Slope và TWI từ Quy trình 1, rồi tạo lại PC1–PC5 ngay trên máy bằng PCA reference đã đóng băng. Miền phân tích cục bộ là hợp của mask PC Quy trình 1 và đúng các ô raster chứa `sample_actual`; tọa độ mẫu chỉ được dùng trong bước cục bộ này và không rời khỏi máy.

Chỉ khi một hoặc nhiều raw covariates thực sự thiếu tại ô mẫu, ứng dụng mới dùng GEE làm phương án dự phòng. Hình học tải là **bounding envelope của `ROI_field_area` được nới đều** theo `covariate_support_buffer_m`; nó không chứa `code`, `lat`, `lon`, không được tạo từ vị trí mẫu và không phải miền dự báo/bản đồ. Điểm nằm ngoài vùng được cấu hình làm workflow dừng. Nếu điểm đã được rà soát và thực sự cần giữ, chỉ sửa `covariate_support_buffer_m` trong file thân thiện `THONG_SO_DU_AN.yml`, rồi chạy lại; không sửa file trong `_NOI_BO`. Việc “cho phép điểm ngoài ROI” không có nghĩa mọi điểm ở bất kỳ khoảng cách nào cũng tự động phù hợp. Bản đồ cuối vẫn bị mask về `ROI_field_area` đã duyệt ở Bước 0.

Khi phát hiện điểm ngoài ROI, preflight tạo/cập nhật `outside_sample_review.csv` chỉ cho đúng nhóm này và giữ lại câu trả lời cũ theo `code`. Điền `target_population_in_scope`, `sampling_support_compatible` và `include_in_model_development` bằng `true/false`, cùng người/ngày rà soát. Để trống nghĩa là đang chờ xác nhận; điểm đó không được gọi là validation set.

## Soil Type của mẫu thực tế

Khi có `soil_type.geojson`, Soil Type được xử lý như biến phân loại:

- nhóm phổ biến nhất có thể làm nhóm tham chiếu;
- nhóm có đủ mẫu được tạo biến giả;
- nhóm đã map nhưng thiếu số mẫu được gộp vào `Other`; điểm ngoài coverage polygon giữ riêng là `Unmapped`;
- mã đất không được xem là thang số có thứ tự.

Vì vậy, điểm ngoài lớp Soil Type không bị loại ngay; nó được đánh dấu `Unmapped` và phải được xem trong QA. `Other` chỉ là tập gộp các lớp nguồn đã map nhưng thiếu mẫu, không phải một loại đất đồng nhất.

## Kiểm tra trước khi chạy

- `code` duy nhất và khớp phiếu lab.
- Không đảo `lat` và `lon`; đối chiếu với phạm vi ROI của chính dự án (AKS chỉ là ví dụ có kinh độ khoảng 108 và vĩ độ khoảng 14).
- Không có dấu phân cách hàng nghìn hoặc ký tự đơn vị trong các cột số.
- Tên cột không tự ý đổi sau khi đã dùng cho một lần chạy.
- Đối chiếu phương pháp và đơn vị trong `indicator_metadata.yml`, rồi chỉ đặt `confirmed: true` cho chỉ tiêu đã xác nhận với phiếu lab.
- Giữ `classification.approved: false` nếu chưa có bộ ngưỡng được phê duyệt cho đúng cây trồng, vùng và phương pháp.
- Các giá trị bất thường được kiểm tra với phiếu gốc, không tự xóa chỉ vì khác số đông.

Sau khi lưu CSV, nhấp `0_KIEM_TRA_DU_AN.bat`. Trước khi có lab, chạy Quy trình 2 một lần và xác nhận `Actual PCA: provenance VERIFIED`. Đường cục bộ phải báo không cần truyền dữ liệu ra ngoài; nếu thật sự phải dùng GEE, privacy gate phải được xác minh bằng chuỗi hash/sidecar trước khi kết nối. Trạng thái đúng sau đó là `WAITING_LAB`, chạy thành công và không tạo bản đồ. `Indicators ready` chỉ cần lớn hơn 0 khi mong đợi bản đồ được tạo.

### Quy ước bắt buộc cho `Unmapped` và `Other`

- `Unmapped`: điểm hoặc ô lưới không nằm trong bất kỳ polygon Soil Type hợp lệ nào; đây là trạng thái thiếu coverage, không phải loại đất.
- `Other`: chỉ gộp các lớp Soil Type **đã được map** nhưng không đủ số mẫu để ước lượng riêng; tuyệt đối không trộn `Unmapped` vào `Other`.
- Cả hai là mức danh mục nominal. Nếu một mức có trên miền dự báo nhưng không có mẫu, QA vẫn giữ mức đó trong raster audit và ghi `unsupported_prediction_groups_assigned_reference_effect`; nhánh hồi quy không tạo một dummy không thể ước lượng. Khi cảnh báo này xuất hiện, ưu tiên diễn giải `PC_ONLY` và chỉ dùng `PC_PLUS_SOIL` sau khi đã xem xét support.
