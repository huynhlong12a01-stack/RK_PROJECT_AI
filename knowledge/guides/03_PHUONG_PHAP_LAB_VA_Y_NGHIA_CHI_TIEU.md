# Phương pháp lab và ý nghĩa chỉ tiêu dinh dưỡng

## Nguyên tắc dữ liệu

Dự án coi mỗi dòng là một kết quả trung bình duy nhất cho mẫu. Ứng dụng không yêu cầu cột độ sâu và không tách tầng. Tuy vậy, tên chỉ tiêu một mình chưa đủ để xác định ý nghĩa phân tích.

Các trường tối thiểu cần có ở cấp metadata cho mỗi cột kết quả:

- canonical name;
- đơn vị;
- phương pháp chuẩn bị và phân tích;
- dung dịch chiết hoặc tiêu hủy;
- tỷ lệ đất:dung dịch nếu có;
- reporting basis, ví dụ đất khô;
- giới hạn phát hiện/định lượng;
- khoảng giá trị hợp lệ;
- mã phòng lab và batch;
- quy tắc xử lý dưới giới hạn phát hiện.

Để giữ sample_actual.csv thân thiện, metadata này nên ở một từ điển chỉ tiêu riêng của dự án; không cần lặp lại trên từng dòng.

## Không trộn các đại lượng chỉ vì cùng ký hiệu

- pH-H₂O, pH-KCl và pH-CaCl₂ không phải một target.
- P Olsen, Bray I/II và Mehlich là các đại lượng phụ thuộc dung dịch chiết.
- K ở mg/kg và K trao đổi ở cmolc/kg khác định nghĩa và đơn vị.
- EC phụ thuộc tỷ lệ chiết/paste.
- SOC và OM phụ thuộc phương pháp; không tự dùng hệ số chuyển đổi cố định nếu chưa xác nhận.
- N tổng và N khoáng/dễ tiêu không thay thế nhau.

Nguồn chuẩn: fao_glosolan_sops; usda_2022_kssl_methods; batjes_2025_wosis_methods, DOI [10.17027/isric-wdcsoils-1nh7-zr51](https://doi.org/10.17027/isric-wdcsoils-1nh7-zr51).

## QA/QC trước nội suy

- mã mẫu duy nhất và khớp phiếu lab;
- số dạng numeric, decimal thống nhất;
- blank khác 0 và khác dưới giới hạn phát hiện;
- kiểm tra duplicate, đơn vị, valid range;
- kiểm tra batch, blank, reference material và replicate nếu lab cung cấp;
- tách target khi phương pháp không tương thích.

## Bản đồ dinh dưỡng không phải bản đồ khuyến cáo phân bón

Bản đồ đầu tiên là bản đồ hàm lượng/trạng thái kèm uncertainty và phạm vi áp dụng. Chuyển sang liều phân cần hiệu chuẩn theo cây mía, vùng, mục tiêu năng suất, phương pháp lab, ngưỡng địa phương và chuyên gia nông học.

Nguồn: fao_2022_gsnmap, DOI [10.4060/cc1717en](https://doi.org/10.4060/cc1717en); fao_2006_plant_nutrition_food_security.
