# PHU_YEN_MOCK — kiểm thử phần mềm, không dùng trong sản xuất

Dự án này kiểm thử toàn bộ luồng trên phạm vi Phú Yên lịch sử trước thay đổi hành
chính năm 2025. ROI vùng mía, nhãn và chỉ tiêu phân tích đều là dữ liệu tổng hợp;
chúng không phải quan sát thực địa hoặc kết quả phòng thí nghiệm.

## Cách chạy

Chỉ sử dụng [00_CHAY_MOCK_AN_TOAN.bat](00_CHAY_MOCK_AN_TOAN.bat). File này tự kiểm
đầu vào, chạy các bước cần thiết, khóa mọi đường xuất tham chiếu và luôn chuyển kết
quả hoàn chỉnh hoặc dở dang vào vùng cách ly.

Nếu một lần chạy hoàn chỉnh đã tồn tại, lần nhấp tiếp theo chỉ kiểm lại an toàn và
hash, không tải lại GEE hoặc chạy lại tám mô hình. Muốn tái tạo từ đầu, chạy trong
PowerShell:

```powershell
.\00_CHAY_MOCK_AN_TOAN.bat -ForceRebuild
```

## Cấu hình mock

`THONG_SO_DU_AN.yml` là nguồn duy nhất cho CRS, GEE project, lưới 30 m, `covariate_support_buffer_m` và ngày covariates. Orchestrator đồng bộ các giá trị này sang cấu hình kỹ thuật; không sửa các bản sao trong từng giai đoạn hoặc `_NOI_BO`. Đây không phải tệp duy nhất của một dự án thật: ROI/nhãn, Soil Type, tham số cLHS và lab vẫn nằm ở các tệp chuyên trách.

## Phạm vi kiểm thử

- Stage 0 chỉ kiểm đường đi từ hình học giả lập đến cLHS và nội suy; không kiểm độ
  chính xác giải đoán mía từ ảnh vệ tinh.
- `APPROVED_FOR_SAMPLE_DESIGN` chỉ là cổng hình học của phần mềm, không xác nhận
  vùng đó là mía.
- REDUCED là lõi CRAN `clhs`; FULL là thiết kế lai gồm cLHS core, spatial infill và
  short-lag, không phải cLHS thuần.
- Nested spatial CV là outer held-out nội bộ, không phải kiểm định thực địa độc lập.
- Lưới tính toán 30 m không làm CHIRPS, SRTM hoặc TWI trở thành quan sát thực 30 m.
- Bản đồ hàm lượng đất không phải bản đồ liều phân bón.

Soil Type chuẩn được đọc tại
`shared_data/soil_type_vietnam/raw/VN_soil_type.geojson`. Dự án giữ mọi nhóm `Ma1`
có mặt trong quần thể ứng viên và giữ vùng thiếu Soil Type bằng mức `Unmapped`.

## Kết quả và an toàn

Mọi sản phẩm Stage 2 chỉ được phép nằm dưới:

`02_NOI_SUY_BAN_DO/02_KET_QUA/MOCK_SYNTHETIC_NOT_FOR_USE`

Đọc `MOCK_RUN_MANIFEST.json` và `MOCK_QA_GATE.json` để xem trạng thái QA và hash.
`maps_accepted` luôn là `false` vì đây là mock. Dữ liệu mock bị cấm dùng cho train,
calibration, outer test, thư viện kiến thức, tái sử dụng liên dự án, sản xuất hoặc
khuyến cáo phân bón.

Hợp đồng an toàn tĩnh nằm trong [MOCK_CONTRACT.json](MOCK_CONTRACT.json).
