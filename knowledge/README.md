# Knowledge base cho ba giai đoạn của dự án

Đây là kho tri thức có kiểm soát cho toàn bộ luồng của dự án:

0. xác lập vùng mía từ `ROI_field_area` có sẵn hoặc giải đoán trong `ROI_search`;
1. thiết kế lấy mẫu từ ROI đã duyệt, Soil Type và covariates;
2. nội suy các chỉ tiêu trong `sample_actual.csv` và tạo bản đồ trong ROI.

Knowledge không thay đầu vào dự án, không tự tạo ngưỡng dinh dưỡng và không tự biến bản đồ hàm lượng thành khuyến cáo phân bón.

## Cấu trúc

| Vị trí | Vai trò | Có commit |
|---|---|---|
| metadata/sources.csv | Danh mục nguồn, DOI/URL, license, tag và tóm tắt tự viết | Có |
| metadata/topic_taxonomy.json | Từ vựng chuẩn và alias Việt–Anh | Có |
| notes/evidence_cards | Luận điểm đã gắn nguồn, điều kiện và giới hạn | Có |
| guides | Tổng hợp chuyên đề bằng tiếng Việt cho dự án | Có |
| index/curated | Chỉ mục từ metadata và evidence cards; không chứa toàn văn có bản quyền | Có |
| library | PDF/tài liệu người dùng có quyền sử dụng | Không, được Git ignore |
| index/local_chunks | Chunks riêng tư tạo từ library | Không |

Thống kê hiện tại: 58 nguồn gồm 51 nguồn `core` và 7 nguồn `supporting`, 25 evidence cards và 7 hướng dẫn chuyên đề. Manifest chỉ mục phải khớp 58 nguồn và 25 evidence cards trước khi phát hành.

## Chính sách nguồn

Ưu tiên theo thứ tự:

- tiêu chuẩn/hướng dẫn chính thức FAO, ISRIC, USDA/NRCS;
- bài báo gốc có DOI về giải đoán mía, DSM, cLHS, PCA, RK, validation, AOA và uncertainty;
- catalog chính thức của đúng Earth Engine asset được ứng dụng sử dụng;
- nguồn hỗ trợ chỉ dùng khi phạm vi phù hợp.

Không lưu toàn văn Elsevier/Wiley/Springer hoặc tài liệu có điều khoản không rõ trong repository. Với FAO GSNmap có điều khoản CC BY-NC-SA 3.0 IGO, repository doanh nghiệp chỉ giữ metadata, diễn giải tự viết và liên kết chính thức.

## Nguồn cốt lõi theo giai đoạn

Bước 0 — xác lập vùng mía:

- Jiang et al. (2019) cho phân loại mía bằng chuỗi Sentinel-1/2 và machine learning;
- Wang et al. (2020) cho đặc trưng phenology đa cảm biến;
- Som-ard et al. (2021) cho tổng quan viễn thám trong canh tác mía;
- Olofsson et al. (2014) cho accuracy assessment và ước lượng diện tích;
- catalog chính thức Sentinel-1 GRD, Sentinel-2 SR Harmonized và Cloud Score+.

Quy trình 1 — thiết kế mẫu:

- Minasny & McBratney (2006) cho cLHS chuẩn;
- Brus (2019) cho lựa chọn thiết kế theo mục tiêu;
- FAO GSNmap (2022) cho sản phẩm 0–30 cm, covariates, PCA và QA;
- catalog chính thức CHIRPS, SRTM và MERIT Hydro.

Quy trình 2 — nội suy:

- McBratney et al. (2003) cho DSM/SCORPAN;
- Hengl et al. (2007) cho Regression Kriging;
- Roberts et al. (2017), Wadoux et al. (2021) và Brus et al. (2011) để phân biệt spatial CV với independent validation;
- Meyer & Pebesma (2021) cho Area of Applicability;
- Schmidinger & Heuvelink (2023) cho kiểm định uncertainty;
- FAO GLOSOLAN, USDA KSSL và ISRIC WoSIS cho phương pháp lab.

Xem [CATALOG.md](CATALOG.md) và thư mục `guides` để đọc theo chủ đề.

## Tra cứu curated knowledge

Chạy kiểm tra metadata:

    .\_UNG_DUNG\tools\run_rag_smoke_test.ps1

Tạo lại curated index:

    .\_UNG_DUNG\tools\run_rag_build_curated_index.ps1

Tra cứu tiếng Việt hoặc tiếng Anh:

    .\_UNG_DUNG\tools\run_rag_query.ps1 -Query "giải đoán mía Sentinel-1 Sentinel-2 phenology" -TopK 8
    .\_UNG_DUNG\tools\run_rag_query.ps1 -Query "22 điểm ngoài ROI và vùng áp dụng" -TopK 8
    .\_UNG_DUNG\tools\run_rag_query.ps1 -Query "spatial cross validation map accuracy" -TopK 8
    .\_UNG_DUNG\tools\run_rag_query.ps1 -Query "phương pháp lab và đơn vị P K pH" -TopK 8

Kết quả là evidence candidates có citation, không phải kết luận tự động.

## Tài liệu riêng tư/local

Nếu người dùng có PDF hợp pháp cần tra cứu, đặt trong `library` rồi làm theo [LOCAL_LIBRARY_WORKFLOW.md](LOCAL_LIBRARY_WORKFLOW.md). Curated index hoạt động ngay cả khi `library` trống; local chunks chỉ là corpus bổ sung và không được commit.

## Quy tắc diễn giải bắt buộc

- Gói AKS chỉ là `positive_reference_only`; dự án đích vẫn cần nhãn dương và âm đã kiểm chứng tại địa phương.
- Engine ưu tiên lõi optimizer từ gói CRAN `clhs`; chỉ `clhs_core` thuộc optimizer gốc. FULL có bổ sung không gian nên là thiết kế lai; fallback phải được ghi rõ cLHS-like.
- PC1–PC5 từ năm covariates không phải giảm chiều.
- Lưới 10 m không làm CHIRPS, SRTM hoặc MERIT trở thành dữ liệu 10 m.
- Điểm ngoài ROI được xem xét theo target population, support và AOA; convenience relocation không phải independent validation.
- Soil Type là categorical. Thiết kế mẫu giữ mọi lớp hợp lệ và Unmapped; Other trong nhánh nội suy chỉ là nhóm kỹ thuật, không phải một loại đất đồng nhất.
- Outer nested spatial CV không được gọi là kiểm định độc lập ngoài thực địa.
- RK residual SD không được gọi là prediction interval tổng nếu chưa hiệu chuẩn.
- Không trộn target khác phương pháp/đơn vị và không suy ra liều phân phổ quát.
