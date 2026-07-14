# Prompt bảo trì knowledge và curated RAG

Đây là hướng dẫn hiện hành để AI agent cập nhật thư viện khoa học. Nó không phải kế hoạch triển khai lịch sử.

## Mục tiêu

Knowledge phải hỗ trợ Bước 0 và hai workflow của dự án bằng nguồn có thể kiểm tra, giới hạn claim rõ và không chứa toàn văn có bản quyền trái phép.

Corpus curated gồm:

- knowledge/metadata/sources.csv;
- knowledge/metadata/topic_taxonomy.json;
- knowledge/notes/evidence_cards;
- knowledge/guides;
- knowledge/index/curated được tạo lại từ các thành phần trên.

Corpus local/private nằm trong knowledge/library và knowledge/index/local_chunks, không commit.

## Trình tự cập nhật

1. Xác định câu hỏi khoa học cụ thể và workflow stage.
2. Tìm nguồn gốc/official trước: FAO, ISRIC, USDA/NRCS, publisher DOI, official dataset catalog.
3. Kiểm tra title, authors, year/version, DOI, official URL, scope và license.
4. Thêm một dòng duy nhất vào sources.csv; không tạo DOI trùng.
5. Chỉ dùng quality_level core khi nguồn đã kiểm chứng và trực tiếp.
6. Cập nhật taxonomy nếu cần, ưu tiên canonical tag hiện có.
7. Viết evidence card bằng diễn giải tự viết; nêu conditions, limitations, recommended và not allowed.
8. Cập nhật guide khi claim ảnh hưởng người dùng.
9. Chạy validator, build curated index và golden queries.
10. Không tải/commit full text nếu quyền sử dụng không rõ.

## Claim bắt buộc của dự án

Knowledge phải luôn giữ các phân biệt sau:

- giải đoán mía cần nhãn dương/âm địa phương, phenology gate và review ROI ứng viên;
- positive-only reference khác binary pretrained model;
- lõi CRAN cLHS khác toàn bộ FULL hybrid và khác fallback cLHS-like;
- FULL/REDUCED là nested trade-off, không phải bảo đảm tương đương;
- PCA năm biến giữ năm PC không phải giảm chiều;
- PCA reference phải đóng băng;
- Soil Type categorical, Other không đồng nhất;
- native/effective resolution khác grid 10 m;
- spatial CV khác independent probability validation;
- điểm ngoài ROI cần target population/support/AOA;
- lab method, extractant và unit quyết định ý nghĩa target;
- residual kriging SD không phải total uncertainty;
- nutrient status map không tự động là fertilizer recommendation.

## Schema nguồn

Các cột bắt buộc hiện tại:

    doc_id, title, authors, year, source_type, journal_or_publisher,
    doi, url, access_date, language, topic_tags, soil_indicators,
    geography, method_tags, quality_level, license_or_access_note, notes

Living documentation có thể dùng năm access snapshot nhưng phải ghi rõ trong license note. Paper và report phiên bản phải dùng năm xuất bản.

## Evidence card

Mỗi card cần:

    claim_id
    claim
    applies_to
    evidence_sources
    strength
    conditions
    limitations
    recommended_action
    not_allowed_action

Strong claim cần ít nhất hai nguồn và tối thiểu một nguồn core. Project-specific implementation claim nên hạ moderate nếu nguồn chỉ hỗ trợ nguyên tắc chung.

## Cổng chất lượng

Chạy:

    .\run_rag_smoke_test.ps1
    .\run_rag_build_curated_index.ps1
    .\run_rag_query.ps1 -Query "spatial cross validation map accuracy" -TopK 8
    .\run_rag_query.ps1 -Query "kiểm định chéo không gian độ chính xác bản đồ" -TopK 8
    .\run_rag_query.ps1 -Query "phương pháp lab đơn vị extractant" -TopK 8
    .\run_rag_query.ps1 -Query "22 điểm ngoài ROI vùng áp dụng" -TopK 8

Không hoàn tất nếu có unknown source id, duplicate DOI/doc_id, tag ngoài taxonomy, URL không hợp lệ, card mạnh thiếu nguồn, index rỗng hoặc truy vấn song ngữ không trả đúng chủ đề.

## Bản quyền và trích dẫn

- Metadata, original summary và evidence card được commit.
- knowledge/library và local chunks là riêng tư.
- Không sao chép abstract/toàn văn dài vào curated index.
- Kết quả query phải trả doc_id và DOI/official URL.
- Khi không có evidence phù hợp, trả confidence thấp và nêu thiếu nguồn; không tự tạo citation.

## Liên kết với workflow

Report người dùng nằm trong projects/TEN_DU_AN/02_NOI_SUY_BAN_DO/02_KET_QUA. Agent chỉ đưa evidence phù hợp target và diagnostic vào giải thích, không liệt kê mọi card theo thứ tự file.

Đọc knowledge/README.md, knowledge/CATALOG.md và docs/SCIENTIFIC_VALIDATION.md trước khi thay đổi claim.
