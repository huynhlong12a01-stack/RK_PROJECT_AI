# AKS_2026 — Bước 0: xác lập vùng mía

AKS_2026 đã có ranh giới mía đáng tin cậy. Nguồn người dùng nên quản lý là `01_DAU_VAO/roi_field_area.geojson`; ranh giới `roi.geojson` cũ ở Quy trình 1 chỉ được nhận để di chuyển/tương thích.

Nhấp `CHAY_XAC_LAP_VUNG_MIA.bat` để kiểm tra hình học, CRS, diện tích, hash và ghi QA. Bước này không tự biến ROI thành một mô hình phân loại.

## Ý nghĩa gói tham chiếu AKS

Gói AKS là `positive_reference_only`:

- xác nhận vị trí mía;
- không có lớp âm tính đã kiểm chứng;
- không phải binary pretrained model;
- không đủ để báo precision/recall hoặc chuyển thẳng sang địa phương khác.

Khi tạo dự án mới chưa có ROI:

1. đặt `roi_search.geojson`;
2. tạo `sugarcane_labels.csv` có cả mía và không-mía chắc chắn;
3. xác nhận `feature_end_date_exclusive`, lịch thời vụ và nguồn tại `interpretation.yml`;
4. chạy Bước 0;
5. review `sugarcane_probability` và `roi_field_area_candidate`;
6. lưu bản đã duyệt thành `roi_field_area.geojson`, rồi chạy lại Bước 0.

Tham chiếu dương AKS chỉ được bổ sung vào tập train sau khi qua gate schema/thời kỳ/phenology/miền môi trường; không được vào fold hiệu chỉnh ngưỡng hoặc outer test.

Không dùng điểm ngẫu nhiên làm âm tính, không dùng ảnh/quý chưa hoàn tất và không dùng vùng ứng viên chưa review cho thiết kế mẫu. Lưới 10 m chỉ là lưới tính toán/xuất, không bảo đảm support ranh giới 10 m.

Hướng dẫn đầy đủ: [WORKFLOW0_GUIDE.md](../../../docs/templates/WORKFLOW0_GUIDE.md).
