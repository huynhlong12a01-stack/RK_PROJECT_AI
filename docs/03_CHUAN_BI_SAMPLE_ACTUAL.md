# Chuẩn bị `sample_actual.csv`

## File này xuất hiện khi nào

Chỉ cập nhật `02_NOI_SUY_BAN_DO/01_DAU_VAO/sample_actual.csv` sau khi đã có vị trí lấy mẫu thực tế. Có thể nhập trước `code`, `lat`, `lon` và để trống chỉ tiêu trong lúc chờ phòng thí nghiệm. Quy trình nội suy chỉ chạy mô hình khi có ít nhất một cột chỉ tiêu chứa giá trị số.

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
2. điểm nằm đủ gần miền covariates hiện có hoặc Earth Engine tải được vùng hỗ trợ;
3. PC1–PC5 được tính bằng đúng PCA reference của Quy trình 1;
4. chênh lệch điều kiện môi trường không quá xa miền hiệu chuẩn đến mức trở thành ngoại suy không kiểm soát;
5. QA ghi nhận rõ trạng thái trong/ngoài `ROI_field_area`.

Ứng dụng dùng buffer hỗ trợ quanh điểm thiếu coverage và có thể tải thêm covariates. Việc “cho phép điểm ngoài ROI” không có nghĩa mọi điểm ở bất kỳ khoảng cách nào cũng tự động phù hợp. Bản đồ cuối vẫn bị mask về `ROI_field_area` đã duyệt ở Bước 0.

Khi phát hiện điểm ngoài ROI, preflight tạo/cập nhật `outside_sample_review.csv` chỉ cho đúng nhóm này và giữ lại câu trả lời cũ theo `code`. Điền `target_population_in_scope`, `sampling_support_compatible` và `include_in_model_development` bằng `true/false`, cùng người/ngày rà soát. Để trống nghĩa là đang chờ xác nhận; điểm đó không được gọi là validation set.

## Soil Type của mẫu thực tế

Khi có `soil_type.geojson`, Soil Type được xử lý như biến phân loại:

- nhóm phổ biến nhất có thể làm nhóm tham chiếu;
- nhóm có đủ mẫu được tạo biến giả;
- nhóm hiếm hoặc không khớp vùng polygon được gộp vào `Other`;
- mã đất không được xem là thang số có thứ tự.

Vì vậy, điểm ngoài lớp Soil Type không bị loại ngay; nó được đánh dấu `Other` và phải được xem trong QA. Nếu nhóm `Other` quá hỗn hợp hoặc chỉ có rất ít mẫu, không nên diễn giải hệ số của nhóm này như một loại đất đồng nhất.

## Kiểm tra trước khi chạy

- `code` duy nhất và khớp phiếu lab.
- Không đảo `lat` và `lon`; với khu vực AKS hiện tại, kinh độ khoảng 108 và vĩ độ khoảng 14.
- Không có dấu phân cách hàng nghìn hoặc ký tự đơn vị trong các cột số.
- Tên cột không tự ý đổi sau khi đã dùng cho một lần chạy.
- Đối chiếu phương pháp và đơn vị trong `indicator_metadata.yml`, rồi chỉ đặt `confirmed: true` cho chỉ tiêu đã xác nhận với phiếu lab.
- Giữ `classification.approved: false` nếu chưa có bộ ngưỡng được phê duyệt cho đúng cây trồng, vùng và phương pháp.
- Các giá trị bất thường được kiểm tra với phiếu gốc, không tự xóa chỉ vì khác số đông.

Sau khi lưu CSV, nhấp `0_KIEM_TRA_DU_AN.bat`. Số dòng mẫu phải đúng và `Indicators ready` phải lớn hơn 0 trước khi mong đợi bản đồ được tạo.
