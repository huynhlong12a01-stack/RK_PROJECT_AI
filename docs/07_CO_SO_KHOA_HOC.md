# Cơ sở khoa học và thư viện chuyên ngành

Tài liệu này nối các quyết định chính của ứng dụng với nguồn khoa học/tiêu chuẩn có thẩm quyền. Nó không thay thế việc đọc bài gốc. Danh mục máy đọc được, DOI, trạng thái kiểm chứng và evidence cards nằm trong thư mục [knowledge](../knowledge/README.md).

## Bản đồ đất số và covariates

Khung digital soil mapping mô tả thuộc tính đất như hàm của các yếu tố hình thành đất, vị trí và phần dư không gian. DEM/Slope/TWI đại diện địa hình–thủy văn; CHIRPS đại diện khí hậu mưa; NDVI đại diện phản ứng thực vật. PCA tạo các trục trực giao; chỉ giảm chiều khi giữ ít thành phần hơn số biến gốc. Dự án giữ PC1–PC5 từ năm covariates nên đây là phép chuẩn hóa/quay toàn hạng, không phải giảm chiều. Phải lưu thứ tự biến, tâm, tỷ lệ và tải trọng để chiếu dữ liệu mới nhất quán.

Nguồn nền:

- McBratney, Mendonça Santos & Minasny (2003), khung digital soil mapping: [DOI 10.1016/S0016-7061(03)00223-4](https://doi.org/10.1016/S0016-7061(03)00223-4).
- GlobalSoilMap, đặc tả sản phẩm và uncertainty: [Specifications Release 2.4](https://files.isric.org/public/documents/GlobalSoilMap_specifications_december_2015_2.pdf).
- Google Earth Engine catalog cho đúng nguồn dữ liệu của workflow: [Sentinel-2 SR Harmonized](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_S2_SR_HARMONIZED), [CHIRPS Daily](https://developers.google.com/earth-engine/datasets/catalog/UCSB-CHG_CHIRPS_DAILY), [SRTM](https://developers.google.com/earth-engine/datasets/catalog/USGS_SRTMGL1_003), [MERIT Hydro](https://developers.google.com/earth-engine/datasets/catalog/MERIT_Hydro_v1_0_1) và [Cloud Score+](https://developers.google.com/earth-engine/datasets/catalog/GOOGLE_CLOUD_SCORE_PLUS_V1_S2_HARMONIZED).

## Giải đoán vùng mía trước thiết kế

Chuỗi thời gian Sentinel-1/2 có thể hỗ trợ nhận diện phenology mía, nhưng mô hình nhị phân cần cả nhãn mía và không-mía đã kiểm chứng tại miền đích. Nhãn dương AKS chỉ là thư viện tham chiếu `positive_reference_only`; nó không tự tạo một mô hình chuyển vùng. Phân tách theo nhóm không gian, fold hiệu chỉnh ngưỡng riêng và outer test riêng giúp giảm leakage nhưng vẫn chưa phải kiểm định thực địa độc lập. ROI ứng viên phải được review trước khi dùng.

Độ phân giải xuất 10 m không làm các predictor thô hơn hoặc sai số ranh giới trở thành thông tin thật ở 10 m. Chuỗi ảnh phải dùng kỳ đã hoàn tất và phù hợp lịch mùa vụ địa phương.

Nguồn chính:

- [Sentinel-1 GRD — Earth Engine](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_S1_GRD) và [Sentinel-2 SR Harmonized](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_S2_SR_HARMONIZED).
- Wang et al. (2020), lập bản đồ mía dựa trên phenology đa cảm biến: [DOI 10.1016/j.rse.2020.111951](https://doi.org/10.1016/j.rse.2020.111951).
- Olofsson et al. (2014), thực hành đánh giá độ chính xác/diện tích bản đồ: [DOI 10.1016/j.rse.2014.02.015](https://doi.org/10.1016/j.rse.2014.02.015).

## Thiết kế lấy mẫu có covariates

Conditioned Latin Hypercube Sampling nhằm bao phủ phân bố liên tục, tỷ lệ biến phân loại và cấu trúc tương quan của dữ liệu phụ trợ với số điểm hữu hạn. Lõi mới dùng optimizer trong gói CRAN `clhs` khi backend khả dụng; Soil Type được đưa như factor và PC1–PC5 như biến liên tục. Đây là simulated annealing ngẫu nhiên, không phải bằng chứng nghiệm tối ưu toàn cục.

Chỉ vai trò `clhs_core` được gọi là đầu ra trực tiếp của cLHS gốc. REDUCED là lõi; FULL bổ sung `spatial_infill` và `short_lag` vì bao phủ covariates chưa chắc tối ưu cho độ phủ địa lý hay ước lượng variogram. Do đó FULL là thiết kế lai, còn backend fallback `python_clhs_like` phải được ghi đúng và không được quảng bá như optimizer gốc. FULL và REDUCED là hai mức nguồn lực, không có bảo đảm tương đương.

Nguồn chính:

- Minasny & McBratney (2006), cLHS: [DOI 10.1016/j.cageo.2005.12.009](https://doi.org/10.1016/j.cageo.2005.12.009).
- Tài liệu triển khai chính thức: [CRAN clhs manual](https://cran.r-project.org/web/packages/clhs/clhs.pdf) và [mã nguồn clhs](https://github.com/pierreroudier/clhs).
- Brus (2019), lựa chọn thiết kế mẫu cho digital soil mapping và tách mục tiêu hiệu chuẩn/đánh giá: [DOI 10.1016/j.geoderma.2018.07.036](https://doi.org/10.1016/j.geoderma.2018.07.036), [bản lưu WUR](https://research.wur.nl/en/publications/sampling-for-digital-soil-mapping-a-tutorial-supported-by-r-scrip/).

Một thiết kế thuận tiện hoặc cLHS không tự động tạo ra ước lượng đánh giá bản đồ không chệch. Nếu mục tiêu là báo cáo chất lượng bản đồ theo thiết kế xác suất, cần cân nhắc một mẫu validation độc lập theo xác suất.

## Regression Kriging và variogram

Regression Kriging tách xu thế liên hệ với covariates và cấu trúc không gian của phần dư. Phần dư chỉ nên được kriging khi variogram có bằng chứng hỗ trợ. Fallback pure nugget của ứng dụng tránh áp một cấu trúc không gian giả.

Nguồn chính:

- Hengl, Heuvelink & Rossiter (2007), Regression-Kriging thực hành: [DOI 10.1016/j.cageo.2007.05.001](https://doi.org/10.1016/j.cageo.2007.05.001).
- Odeh, McBratney & Chittleborough (1995), kết hợp hồi quy và geostatistics: [DOI 10.1016/0016-7061(95)00007-B](https://doi.org/10.1016/0016-7061(95)00007-B).
- Pebesma (2004), phần mềm `gstat` cho geostatistics đa biến: [DOI 10.1016/j.cageo.2004.03.012](https://doi.org/10.1016/j.cageo.2004.03.012).
- Webster & Oliver (2007), *Geostatistics for Environmental Scientists*, và Cressie (1993), *Statistics for Spatial Data*, là tài liệu nền về variogram, kriging và chẩn đoán không gian.

## Kiểm định không gian và ngoại suy

Random cross-validation thường lạc quan khi điểm gần nhau có tính tự tương quan. Ứng dụng vì vậy ưu tiên nested spatial block CV, giữ outer-test ở trạng thái held-out đối với lựa chọn transform/variogram/neighbors trong mỗi fold. Đây không phải independent field validation. Area of applicability giúp nhận diện ô raster nằm ngoài miền predictor được dữ liệu mẫu hỗ trợ.

- Roberts và cộng sự (2017), chiến lược cross-validation cho dữ liệu không độc lập: [DOI 10.1111/ecog.02881](https://doi.org/10.1111/ecog.02881).
- Meyer & Pebesma (2021), area of applicability: [DOI 10.1111/2041-210X.13650](https://doi.org/10.1111/2041-210X.13650).

## Độ bất định

Kriging standard deviation của phần dư không bao gồm toàn bộ uncertainty từ hồi quy, chọn mô hình, covariates, tham số variogram và back-transform. Nó phải được ghi nhãn đúng và không được dùng như total predictive uncertainty. Coverage đơn lẻ cũng chưa đủ để chứng minh phân phối uncertainty được hiệu chuẩn.

- Schmidinger & Heuvelink (2023), kiểm định dự báo uncertainty trong digital soil mapping: [DOI 10.1016/j.geoderma.2023.116585](https://doi.org/10.1016/j.geoderma.2023.116585).
- Poggio và cộng sự (2021), SoilGrids 2.0 và định lượng uncertainty: [DOI 10.5194/soil-7-217-2021](https://doi.org/10.5194/soil-7-217-2021).

## Phương pháp phòng thí nghiệm và diễn giải dinh dưỡng

Tên chỉ tiêu phải gắn với phương pháp và đơn vị. `P_Olsen` không tương đương trực tiếp `P_Bray`; pH nước không đồng nhất pH KCl; K khả dụng theo mg/kg không đồng nhất K trao đổi theo cmol(+)/kg. Mọi ngưỡng phân hạng dinh dưỡng phải được phê duyệt cho cây trồng, vùng, phương pháp lab và mục tiêu sử dụng.

Nguồn chính thống:

- USDA NRCS, [Soil Survey Manual](https://www.nrcs.usda.gov/resources/guides-and-instructions/soil-survey-manual) và [Kellogg Soil Survey Laboratory Methods Manual](https://www.nrcs.usda.gov/sites/default/files/2022-10/SSIR42-v6-pt1.pdf).
- ISRIC WoSIS, chuẩn hóa mô tả phương pháp phân tích: [WoSIS documentation](https://docs.isric.org/globaldata/wosis/faq-wosis.html).
- FAO, [Plant Nutrition for Food Security](https://www.fao.org/4/a0443e/a0443e00.htm) và [Integrated Plant Nutrient Management](https://www.fao.org/agriculture/crops/thematic-sitemap/theme/spi/scpi-home/managing-ecosystems/integrated-plant-nutrient-management/en/).

## Cách sử dụng thư viện `knowledge`

- Bắt đầu tại `knowledge/README.md` để chọn chủ đề.
- Tra nguồn tại `knowledge/metadata/sources.csv`; ưu tiên mục `core` và DOI/URL đã kiểm chứng.
- Đọc `knowledge/notes/evidence_cards` để xem một khẳng định ngắn cùng phạm vi áp dụng và giới hạn.
- Dùng tài liệu trong `knowledge/guides` để liên hệ bằng chứng với từng bước workflow.
- Không coi tóm tắt/evidence card là thay thế bài báo, tiêu chuẩn hoặc hướng dẫn phòng thí nghiệm gốc.

Mô tả chi tiết các kiểm soát đang có trong engine nằm tại [SCIENTIFIC_VALIDATION.md](SCIENTIFIC_VALIDATION.md).
