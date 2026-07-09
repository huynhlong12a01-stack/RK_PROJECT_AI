# AI Agent Workflow For Regression Kriging

Tài liệu này dành cho Codex hoặc AI agent khi làm việc trong dự án R Regression Kriging. Mục tiêu là chạy workflow có kiểm soát, đọc output JSON, đề xuất tham số hợp lệ, so sánh iteration và chọn kết quả đáng tin theo tiêu chí khoa học.

## 0. Dependency Gate

Luôn kiểm tra môi trường trước khi chạy thật:

```powershell
.\check_dependencies.ps1 -Profile all
```

Nếu thiếu package và người dùng cho phép:

```powershell
.\install_dependencies.ps1 -Profile "core,rag"
.\install_dependencies.ps1 -Profile "geostat_extra,spatial_cv,modeling"
```

Không chạy RK thật khi thiếu `sf`, `terra`, `gstat`, `sp`, `jsonlite`, `readr`. Không build PDF RAG khi thiếu `pdftools`. Không tự gọi `install.packages()` rời rạc nếu wrapper còn hoạt động.

## 1. Entry Points

- Config chính: `scripts/00_config.R`.
- Engine RK: `scripts/main.R`.
- Agent single-run: `run_agent.ps1` -> `scripts/agent_run.R`.
- Batch nhiều chỉ tiêu: `run_agent_batch.ps1` -> `scripts/agent_batch_run.R`.
- Agent loop có kiểm soát: `run_agent_loop.ps1` -> `scripts/agent_loop.R`.
- Validator: `scripts/agent_validate_decision.R`.
- Compare: `scripts/agent_compare_runs.R` hoặc `run_agent_compare.ps1`, có filter theo target/run prefix/source và có tính thêm class accuracy/uncertainty nếu output có sẵn.
- Evaluation rules: `rk_evaluation/evaluation.R`.
- Request template: `agent/requests/run_request_template.json`.

## 2. Workflow Chuẩn

1. Kiểm tra Git status.
2. Đọc `README.md`, `AGENT_README.md`, `scripts/00_config.R`.
3. Chạy dependency gate.
4. Kiểm tra schema input bằng `validate_point_schema.ps1` và `validate_raster_schema.ps1`.
5. Chọn batch, single-agent, controlled loop hoặc normal RK.
6. Đọc `run_result.json` và report JSON/CSV.
7. Nếu cần RERUN, tạo `ai_decision.json` đúng whitelist.
8. Chạy validator trước khi tạo request mới.
9. Dừng theo stop conditions, không chạy vô hạn.
10. So sánh run bằng `agent_compare_runs.R` nếu có từ 2 run trở lên; luôn lọc bằng `--target`, `--run_prefix`, `--source_contains` hoặc dùng thư mục `agent/history/<loop_id>/results`.

## 3. Khi Nào Dùng Workflow Nào

Batch nhiều chỉ tiêu:

```powershell
.\run_agent_batch.ps1
.\run_agent_batch.ps1 -Targets "pH,Humus,CEC"
```

Single target:

```powershell
.\run_agent.ps1 -Target pH -Request agent\requests\run_request_template.json
```

Controlled loop:

```powershell
.\run_agent_loop.ps1 -Target pH -MaxIterations 3
.\run_agent_loop.ps1 -Target pH -MaxIterations 3 -AutoDecision
```

Không có OpenAI/API trong loop này. Nếu không bật `-AutoDecision`, loop sẽ dừng ở `WAITING_FOR_AI_DECISION` và ghi file cần thiết trong `agent/decisions/<loop_id>/` để agent bên ngoài điền quyết định.

Normal RK:

```powershell
.\run_rk.bat
```

## 4. Output Cần Đọc

Ưu tiên:

```text
agent/responses/<run_id>_run_result.json
agent/responses/final_decision_<target>_<loop_id>.json
output/agent_runs/<run_id>/06_report/json/evaluation_<target>.json
output/agent_runs/<run_id>/06_report/tables/model_comparison_<target>.csv
output/agent_runs/<run_id>/06_report/tables/cv_results_<target>.csv
output/agent_runs/<run_id>/06_report/tables/neighbor_tuning_<target>.csv
output/agent_runs/<run_id>/06_report/interactive/variogram_interactive_<target>.html
```

## 5. Nguyên Tắc Khoa Học

Không chọn mô hình chỉ vì RMSE thấp nhất. Cần xét:

- R²_pred dương.
- ME gần 0.
- RK cải thiện so với regression-only.
- RK không kém rõ so với Ordinary Kriging.
- Nugget/Sill không quá cao.
- Range không chạm max và không quá dài so với cutoff.
- Ít cảnh báo nghiêm trọng.
- Class accuracy hợp lý nếu chỉ tiêu có phân cấp.
- Uncertainty hợp lý nếu có.

Dữ liệu random/test không dùng để chứng minh RK tốt hơn; chỉ dùng để kiểm tra workflow.

## 6. Whitelist Tham Số AI Được Đổi

```text
VARIOGRAM_MODE
VARIOGRAM_MODEL
MANUAL_NUGGET
MANUAL_PSILL
MANUAL_RANGE
VARIOGRAM_CUTOFF
VARIOGRAM_WIDTH
VARIOGRAM_RANGE_MIN
VARIOGRAM_RANGE_MAX
NMAX_NEIGHBORS
SEARCH_RADIUS
AUTO_NEIGHBORS
AUTO_NEIGHBOR_NMAX_CANDIDATES
AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES
AUTO_NEIGHBOR_CV_METHOD
AUTO_NEIGHBOR_MAX_CANDIDATES
CV_METHODS
CV_K_FOLDS
CLAMP_TO_SAMPLE_RANGE
TARGET_TRANSFORM
```

`TARGET_TRANSFORM` hiện là tham số giữ chỗ; validator sẽ từ chối nếu engine chưa hỗ trợ transform thật.

## 7. Protected Settings

AI không được tự ý thay đổi:

```text
POINT_FILE
RASTER_DIR
ROI_FILE
UTM_EPSG
EXPORT_EPSG
CODE_COL
LAT_COL
LON_COL
RASTER_PATTERN
OUTPUT_RESOLUTION
USE_COMPLETE_PC_MASK
REGRESSION_FORMULA
raw input data
source scripts
main engine logic
```

## 8. Auto-Neighbor

Mặc định bật `AUTO_NEIGHBORS <- TRUE`. Khi báo cáo kết quả, luôn nêu:

```text
selected_nmax_neighbors
selected_search_radius
auto_neighbors_method
neighbor_tuning file
```

Không chỉnh thủ công neighbor nếu chưa đọc cảnh báo trong report.

## 9. Stop Conditions

Dừng nếu:

- ACCEPT.
- Đạt `MAX_ITERATIONS`.
- Validator từ chối.
- MANUAL_REVIEW hoặc REJECT.
- Hai lần rerun liên tiếp không cải thiện RMSE khoảng 3-5%.
- RMSE tốt hơn nhưng variogram xấu hơn rõ.
- R²_pred vẫn âm.
- Không có candidate variogram/neighborhood hợp lệ.

## 10. RAG Local

Inventory, index và query tài liệu local:

```powershell
.\run_rag_inventory.ps1
.\run_rag_build_local_index.ps1
.\run_rag_query.ps1 -Query "variogram range spatial CV" -TopK 8
```

Không tải, chia sẻ hoặc commit tài liệu bản quyền. Chỉ dùng tài liệu local do người dùng cung cấp hợp pháp.

## 11. Không Được Làm

- Không sửa input CSV/raster gốc.
- Không đổi CRS nếu chưa được yêu cầu.
- Không tắt cross-validation để kết quả đẹp hơn.
- Không chọn run chỉ vì RMSE thấp nhất.
- Không tạo uncertainty giả.
- Không hard-code đường dẫn cá nhân.
- Không commit runtime outputs như `output/`, `agent/responses/`, `agent/history/`, `knowledge/library/`.