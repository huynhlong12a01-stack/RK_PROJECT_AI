# Kho kiến thức tham chiếu riêng tư

Thư mục này chỉ lưu các thư viện đặc trưng được tạo cục bộ từ dữ liệu hình học riêng tư. Git chỉ theo dõi tệp chính sách này và quy tắc `.gitignore`; bảng đặc trưng, prototype, miền dữ liệu và manifest không được đưa lên kho mã nguồn.

Gói AKS là tri thức của **lớp dương mía**, không phải mô hình nhị phân có khả năng chuyển trực tiếp sang tỉnh khác. Mọi dự án đích phải có nhãn mía và không-mía tại địa phương, xác nhận lịch mùa vụ, vượt cổng tương thích schema/miền dữ liệu và kiểm định không gian.

Dòng tham chiếu AKS chỉ được thêm vào TRAIN. Chúng không bao giờ được dùng trong calibration hoặc test. Gói kiến thức không chứa tọa độ hay hình học, mã dòng nguồn được thay mới, và mọi lần tạo gói đều phải vượt kiểm tra quyền riêng tư đệ quy.
