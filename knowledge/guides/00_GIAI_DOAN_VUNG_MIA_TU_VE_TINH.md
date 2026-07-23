# Giải đoán vùng mía từ dữ liệu vệ tinh: nguyên tắc dùng trong RK_R_Project

## 1. Sản phẩm cần phân biệt

Quy trình tạo ba sản phẩm khác nhau:

1. **Bản đồ xác suất/điểm số mía** từ mô hình.
2. **Vùng ứng viên** sau ngưỡng và hậu xử lý không gian.
3. **ROI field-area được duyệt** sau giải đoán trực quan/thực địa.

Chỉ sản phẩm 3 được làm target population cho thiết kế lấy mẫu. Việc tách này ngăn sai số phân loại vùng phủ lan trực tiếp sang cLHS, lấy mẫu thực địa và bản đồ đất.

## 2. Vì sao cần chuỗi thời gian Sentinel-1 và Sentinel-2

Mía có phổ tức thời dễ trùng với nhiều cây xanh khác. Thông tin phân biệt quan trọng nằm trong quỹ đạo sinh trưởng, thu hoạch và tái sinh theo thời gian. Jiang et al. dùng chuỗi Sentinel-1/2 và cho thấy VH/VV hữu ích trong điều kiện nhiều mây; Wang et al. khai thác các mốc phenology từ chuỗi Landsat, Sentinel-2 và Sentinel-1 để lập bản đồ mía 10 m. Vì vậy workflow dùng đặc trưng theo quý của NDVI, EVI, NDMI, NDRE, NBR2 cùng VV, VH và VV−VH, thay vì một ảnh NDVI duy nhất.

Nguồn:

- [Jiang et al. (2019), Remote Sensing 11, 861](https://doi.org/10.3390/rs11070861)
- [Wang et al. (2020), Remote Sensing of Environment 247, 111951](https://doi.org/10.1016/j.rse.2020.111951)
- [Remote Sensing Applications in Sugarcane Cultivation: A Review](https://doi.org/10.3390/rs13204040)

## 3. Xử lý dữ liệu Earth Engine

- Sentinel-2 dùng `COPERNICUS/S2_SR_HARMONIZED`, là surface reflectance được scale 10.000. Workflow nhân 0,0001 trước khi tính chỉ số.
- Cloud Score+ `cs_cdf` biểu diễn mức pixel nhìn rõ bề mặt từ 0 đến 1. Ngưỡng là tham số cần ghi provenance, không phải hằng số đúng cho mọi địa phương.
- `COPERNICUS/S1_GRD` đã được hiệu chỉnh, terrain-corrected và chuyển sang dB. Không áp dụng `10*log10()` lần nữa.
- Ngày kết thúc `filterDate` trong Earth Engine là exclusive; workflow dùng ngày 1 tháng 1 của năm sau để bao phủ hết năm mục tiêu.
- Pixel thiếu ảnh vẫn bị mask. Không `unmask(0)` predictor vì 0 là giá trị vật lý có thể bị mô hình hiểu nhầm.
- WorldCover chỉ là predictor/prior chẩn đoán, không là hard mask mặc định: sản phẩm 2021 có thể bỏ sót chuyển đổi canh tác mới và sai lớp địa phương.

Nguồn chính thức:

- [Sentinel-2 SR Harmonized](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_S2_SR_HARMONIZED)
- [Cloud Score+ S2 Harmonized](https://developers.google.com/earth-engine/datasets/catalog/GOOGLE_CLOUD_SCORE_PLUS_V1_S2_HARMONIZED)
- [Sentinel-1 GRD](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_S1_GRD)
- [Earth Engine Sentinel-1 preprocessing guide](https://developers.google.com/earth-engine/guides/sentinel1)

## 4. Nhãn và rò rỉ dữ liệu

Một tập ROI mía hiện có chỉ cho nhãn dương tính. Nó không xác định được các lớp âm dễ nhầm như sắn, ngô, lúa, cây lâu năm hoặc đất trống theo mùa. Điểm ngẫu nhiên trong ROI search là **unlabelled**, không phải non-sugarcane chắc chắn.

Mô hình nhị phân chỉ chạy khi có cả hai lớp được kiểm chứng. Polygon hoặc nhiều pixel của cùng một lô phải ở cùng một spatial group. Workflow dành một nhóm fold để chọn ngưỡng, một nhóm fold khác làm outer held-out test, và train trên các fold còn lại. Điều này giảm rò rỉ không gian và tránh báo F1 trên chính dữ liệu dùng chọn ngưỡng.

Outer held-out test vẫn là kiểm định nội bộ; chỉ một mẫu tham chiếu độc lập, được thiết kế xác suất và thu thập riêng mới là accuracy assessment độc lập.

Nguồn:

- [Valavi et al. (2019), blockCV](https://doi.org/10.1111/2041-210X.13107)
- [Olofsson et al. (2014), good practices for accuracy and area estimation](https://doi.org/10.1016/j.rse.2014.02.015)

## Sàng lọc khi chỉ có điểm mía dương tính

Khi chỉ có vị trí mía đã kiểm chứng, ứng dụng không thể học ranh giới quyết định mía/không-mía. Chế độ `allow_positive_only_screening` chỉ đo mức hỗ trợ/tương đồng đa biến với các điểm dương theo fold không gian và xuất lớp ứng viên để review.

Điểm hỗ trợ không phải xác suất mía. Không được tính precision, recall, F1 hoặc accuracy; không dùng điểm nền ngẫu nhiên hay WorldCover làm nhãn âm; không tự nâng candidate thành `roi_field_area` hoặc chuyển sang cLHS. Để lập bản đồ phân loại có đánh giá sai số vẫn cần nhãn dương/âm địa phương và mẫu đánh giá phù hợp.

Để tránh tính và tải GEE hai lần, phiên bản v2 tải một raster điểm hỗ trợ rồi hậu xử lý mask cục bộ bằng kernel tròn bán kính 1 pixel và lọc vùng liên thông. Trên phép thử AKS 20 m, mask cục bộ đạt IoU 0,99993 so với mask GEE đầy đủ; đây là kiểm tra tương đương tính toán, không phải độ chính xác phân loại.

## 5. Chỉ số cần báo cáo

Với lớp mía, chỉ overall accuracy có thể cao dù bỏ sót nhiều mía khi lớp này hiếm. Báo ít nhất:

- confusion matrix;
- precision/user's accuracy của lớp mía (kiểm soát commission);
- recall/producer's accuracy của lớp mía (kiểm soát omission);
- F1 và balanced accuracy;
- số nhãn và số spatial group của từng lớp;
- ngưỡng được chọn trên calibration fold;
- diện tích ứng viên;
- tỷ lệ/không gian ngoài miền áp dụng;
- independent field validation = true/false.

Nếu mục tiêu là ước lượng diện tích mía cấp huyện/tỉnh, diện tích đếm trực tiếp từ pixel phân loại bị bias bởi commission/omission. Cần mẫu accuracy assessment theo thiết kế xác suất và ước lượng diện tích hiệu chỉnh sai số theo Olofsson et al.

## 6. Tái sử dụng mô hình giữa dự án

Một model package chỉ được xem xét tái sử dụng khi khớp:

- feature schema và collection ID;
- mùa vụ/năm mục tiêu và cửa sổ phenology;
- định nghĩa nhãn và support;
- miền khí hậu, địa hình, giống/canh tác;
- preprocessing và độ phân giải;
- kiểm tra applicability/domain tại dự án mới.

Ngay cả khi khớp, model cũ chỉ nên khởi tạo hoặc bổ sung training. Dự án mới vẫn cần nhãn địa phương ở cả hai lớp và outer spatial test tại địa phương. ROI AKS_2026 hiện được lưu là `positive_reference_only`, không được tuyên bố là pretrained model tổng quát.

Gói AKS cục bộ hiện giữ 1.000 hàng tham chiếu: 975 hàng hoàn chỉnh cho 75 predictor và 25 hàng thiếu do mask được biểu diễn bằng NA, không bao giờ điền 0. Knowledge xuất ra đã loại tọa độ/hình học và tạo 8 prototype từ các hàng hoàn chỉnh; các con số này mô tả miền lớp dương, không phải mô hình mía/không-mía.

## 7. Hậu xử lý và phê duyệt

Lọc vùng nhỏ và smoothing giúp giảm nhiễu salt-and-pepper nhưng có thể xóa ruộng nhỏ hoặc nhập hai lô sát nhau. Tham số diện tích tối thiểu phải phản ánh cấu trúc ruộng địa phương. Vùng ứng viên cần review cùng ảnh cùng mùa/năm, ảnh độ phân giải cao và kiến thức thực địa. Mọi chỉnh sửa/phê duyệt cần lưu người review, ngày review và phiên bản nguồn.
