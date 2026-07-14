# Báo cáo cập nhật nguồn tri thức

Ngày cập nhật: 2026-07-13

## Thống kê

- Tổng nguồn: 52.
- Core: 45.
- Supporting: 7.
- Evidence cards: 22.
- Hướng dẫn tổng hợp tiếng Việt: 6.
- Năm xuất bản/phiên bản mới nhất trong metadata: 2026 đối với living documentation được chụp theo ngày truy cập; báo cáo chính thức mới nhất là ISRIC WoSIS 2025.

## Nội dung đã bổ sung

1. Thiết kế mẫu: cLHS gốc, thiết kế theo mục tiêu, nested FULL/REDUCED và validation sampling.
2. Covariates: đúng collection/asset cho Sentinel-2, Cloud Score+, CHIRPS, SRTM và MERIT Hydro; paper nền cho NDVI, TWI và Earth Engine.
3. PCA và Soil Type: PCA toàn hạng, reference đóng băng, categorical encoding và sample support.
4. DSM và validation: spatial CV, independent probability validation, AOA, uncertainty calibration và map support.
5. Phòng lab: FAO GLOSOLAN, USDA KSSL 2022, USDA Field Book 2024 và ISRIC WoSIS 2025.
6. Dinh dưỡng: FAO GSNmap 2022, FAO plant nutrition và ví dụ nutrient mapping quy mô vùng.

## Sửa metadata cũ

- brus_2019_sampling_dsm đã có DOI 10.1016/j.geoderma.2018.07.036, URL WUR và nâng thành core.
- usda_2014_kslm_methods được thay bằng usda_2022_kssl_methods, SSIR 42 v6.0 Part 1.
- Taxonomy được mở rộng và có alias Việt–Anh.
- Các DOI lặp ở catalog đã được bỏ; paper và catalog vẫn liên kết qua notes/doc_id.

## Nguyên tắc kiểm chứng

- Core cần DOI hoặc URL chính thức có thể kiểm tra.
- Living documentation dùng năm của access snapshot và ghi rõ trong license note.
- Không lưu full text có bản quyền; curated corpus chỉ chứa metadata, tóm tắt tự viết và evidence cards.
- Ngưỡng dinh dưỡng chỉ được dùng khi crop, vùng, phương pháp và đơn vị tương thích.
- Nguồn exact asset được ưu tiên cho provenance; paper gốc được ưu tiên cho claim phương pháp.

## Khoảng trống còn lại

- Chưa có guideline chính thức riêng cho ngưỡng dinh dưỡng cây mía tại đúng vùng dự án và đúng phương pháp lab.
- Chưa có bộ independent probability validation ngoài thực địa.
- Chưa có calibration set để gọi uncertainty map là prediction interval.
- Cần cập nhật metadata method/unit ngay khi phòng lab trả kết quả.

Các khoảng trống trên là điều kiện chờ dữ liệu/ngữ cảnh địa phương, không được bù bằng ngưỡng hoặc citation suy đoán.
