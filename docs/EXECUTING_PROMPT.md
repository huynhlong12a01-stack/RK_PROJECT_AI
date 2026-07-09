# EXECUTING PROMPT - R Regression Kriging Agent Workflow

Bạn là AI coding agent đang làm việc trực tiếp trong thư mục dự án R Regression Kriging hiện có. Nhiệm vụ là thực thi workflow đã có để chạy RK, kiểm định kết quả, tạo report, đọc JSON output, và nếu cần thì chạy lại có kiểm soát. Không thiết kế lại dự án nếu không cần.

## 0. Quy tắc bắt buộc

- Không chuyển sang Python, Flask, Shiny hoặc web server.
- Không sửa input CSV/raster gốc.
- Không tự ý thay CRS hoặc đổi tên cột dữ liệu.
- Không tắt cross-validation để làm kết quả đẹp hơn.
- Không chọn mô hình chỉ vì RMSE thấp nhất.
- Không chạy vòng lặp vô hạn.
- Không hard-code đường dẫn máy cá nhân.
- Kiểm tra `git status --short` trước và sau khi sửa.
- Không commit trừ khi người dùng yêu cầu rõ.

## 1. Đọc file trước khi chạy

Đọc nếu có:

```text
README.md
AGENT_README.md
docs/EXECUTING_PROMPT.md
scripts/00_config.R
scripts/main.R
scripts/agent_run.R
scripts/agent_batch_run.R
scripts/agent_validate_decision.R
scripts/agent_compare_runs.R
scripts/validate_point_schema.R
rk_evaluation/evaluation.R
run_agent.ps1
run_agent_batch.ps1
validate_point_schema.ps1
check_dependencies.ps1
install_dependencies.ps1
run_rk.bat
```

Xác định:

```text
Config chính: scripts/00_config.R
Engine chính: scripts/main.R
Agent single-run: run_agent.ps1
Agent batch: run_agent_batch.ps1
Evaluation: rk_evaluation/evaluation.R
Request template: agent/requests/run_request_template.json
Output agent: output/agent_runs/<run_id>/
JSON response: agent/responses/<run_id>_run_result.json
```

## 2. Kiểm tra môi trường

Luôn chạy dependency gate nếu wrapper tồn tại:

```powershell
.\check_dependencies.ps1 -Profile all
```

Nếu thiếu package và người dùng đã cho phép cài đặt:

```powershell
.\install_dependencies.ps1 -Profile "core,rag"
.\install_dependencies.ps1 -Profile "geostat_extra,spatial_cv,modeling"
```

Không tự cài package bằng lệnh rời rạc nếu wrapper còn dùng được.

## 3. Kiểm tra input

Trước khi chạy thật:

```powershell
.\validate_point_schema.ps1
```

Nếu thiếu `POINT_FILE`, thiếu raster `PC*.tif`, hoặc target không tồn tại trong CSV, dừng và báo rõ file/cột nào thiếu.

## 4. Chọn workflow

Ưu tiên batch khi CSV có nhiều chỉ tiêu:

```powershell
.\run_agent_batch.ps1
.\run_agent_batch.ps1 -Targets "pH,Humus,CEC"
```

Một chỉ tiêu:

```powershell
.\run_agent.ps1 -Target pH -Request agent\requests\run_request_template.json
```

Workflow thường:

```powershell
.\run_rk.bat
```

Nếu chỉ cần test hạ tầng batch:

```powershell
.\run_agent_batch.ps1 -Targets pH -DryRun
```

Dry-run không phải kết quả khoa học.

## 5. Target field

Nếu `TARGET_FIELD <- "auto"` và CSV chỉ có một chỉ tiêu, engine có thể tự chọn. Nếu CSV có nhiều chỉ tiêu, không để engine đoán; dùng batch hoặc truyền `-Target` rõ ràng. Khi không rõ target, ưu tiên thử các cột có thật theo thứ tự: `pH`, `Humus`, `CEC`.

## 6. Output cần đọc

Sau mỗi run, đọc:

```text
agent/responses/<run_id>_run_result.json
output/agent_runs/<run_id>/06_report/index_<target>.html
output/agent_runs/<run_id>/06_report/json/evaluation_<target>.json
output/agent_runs/<run_id>/06_report/tables/model_comparison_<target>.csv
output/agent_runs/<run_id>/06_report/tables/cv_results_<target>.csv
output/agent_runs/<run_id>/06_report/tables/neighbor_tuning_<target>.csv
output/agent_runs/<run_id>/06_report/interactive/variogram_interactive_<target>.html
```

Trích xuất: RMSE, MAE, ME, R²_pred, baseline RMSE, variogram model, nugget, sill, range, nugget/sill, range_hit_max, selected_nmax_neighbors, selected_search_radius, warnings, recommendations, missing_outputs.

## 7. Đánh giá khoa học

Không chọn mô hình chỉ vì RMSE thấp nhất. Ưu tiên:

- R²_pred dương.
- ME gần 0.
- RK cải thiện so với regression-only.
- RK không kém rõ so với Ordinary Kriging.
- Nugget/Sill không quá cao.
- Range không chạm max.
- Practical range không quá dài so với cutoff.
- Ít cảnh báo nghiêm trọng.
- Class accuracy hợp lý nếu có phân cấp.
- Uncertainty hợp lý nếu có.

Nếu dữ liệu là random/test, không cố chứng minh RK tốt; chỉ báo kết quả dùng để kiểm tra workflow.

## 8. Quyết định iteration

Chọn một trong:

```text
ACCEPT
RERUN
MANUAL_REVIEW
REJECT
```

RERUN chỉ khi có cảnh báo có thể cải thiện bằng tham số hợp lệ. MANUAL_REVIEW khi variogram/bản đồ cần chuyên gia xem. REJECT khi R²_pred âm, RK kém baseline rõ, variogram không có cấu trúc hoặc dữ liệu quá ít.

## 9. Nếu cần RERUN

Tạo `agent/decisions/ai_decision_<TARGET>_iter_001.json` đúng schema. Chỉ dùng whitelist trong `AGENT_README.md`. Sau đó chạy validator:

```powershell
Rscript scripts\agent_validate_decision.R --decision agent\decisions\ai_decision_<TARGET>_iter_001.json --request agent\requests\run_request_<TARGET>_iter_001.json --output agent\decisions\validated_decision_<TARGET>_iter_001.json
```

Nếu validator từ chối, dừng. Không bypass validator.

## 10. Stop conditions

Mặc định `MAX_ITERATIONS = 3`. Dừng nếu ACCEPT, REJECT, MANUAL_REVIEW, đạt max iterations, validator từ chối, R²_pred vẫn âm, hoặc hai lần rerun liên tiếp không cải thiện RMSE khoảng 3-5%.

## 11. Compare runs

Nếu có từ 2 run trở lên:

```powershell
Rscript scripts\agent_compare_runs.R --results agent\responses --output agent\history\run_comparison_<TARGET>.json
```

Không dùng cú pháp `--target` hoặc `--history` nếu script hiện tại không hỗ trợ.

## 12. RAG local nếu cần tra cứu tài liệu

```powershell
.\run_rag_inventory.ps1
.\run_rag_build_local_index.ps1
.\run_rag_query.ps1 -Query "spatial cross-validation variogram range" -TopK 8
```

Không tải, chia sẻ hoặc commit tài liệu bản quyền. Chỉ đọc tài liệu local người dùng cung cấp hợp pháp.

## 13. Báo cáo cuối cho người dùng

Trả lời bằng tiếng Việt có dấu, nêu rõ:

```text
Workflow đã chạy
Target đã chạy
Số iteration
Metric từng iteration
Variogram và neighbor được chọn
Run được chọn và lý do
Vì sao không chọn RMSE thấp nhất nếu có
Output cụ thể nằm ở đâu
Có cần manual review không
Giới hạn còn lại
```

Nếu lỗi, báo lệnh đã chạy, lỗi nhận được, file/log liên quan, nguyên nhân có khả năng và cách khắc phục.
## Ghi chú cập nhật về compare và loop

- Khi so sánh nhiều run, không trỏ mù vào toàn bộ `agent/responses` nếu có nhiều lịch sử cũ. Hãy dùng `--target`, `--run_prefix`, `--source_contains` hoặc thư mục `agent/history/<loop_id>/results`.
- `run_agent_loop.ps1` là wrapper ưu tiên khi muốn chạy nhiều iteration có kiểm soát. Nếu không có file AI decision và không bật `-AutoDecision`, loop sẽ dừng ở `WAITING_FOR_AI_DECISION` thay vì tự đoán bừa.