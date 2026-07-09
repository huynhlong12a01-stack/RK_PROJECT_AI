# Regression Kriging R Project

Dự án này chạy nội suy Regression Kriging cho dữ liệu đất bằng R, Rscript và PowerShell. Luồng hiện tại giữ engine R làm lõi, có evaluation rules, report HTML/CSV/JSON, agent-ready workflow, batch runner nhiều chỉ tiêu, auto-neighbor tuning và kho tri thức RAG cục bộ.

## Yêu cầu phần mềm

- R và `Rscript` có trong `PATH`.
- PowerShell trên Windows.
- Git chỉ dùng để quản lý phiên bản, không bắt buộc khi chạy nội suy.

## Thiết lập thư viện R

Dự án dùng dependency chính thức trong `DESCRIPTION` và `scripts/dependencies.R`. Trước khi chạy thật:

```powershell
.\check_dependencies.ps1 -Profile all
```

Nếu thiếu package và bạn cho phép cài đặt:

```powershell
.\install_dependencies.ps1 -Profile "core,rag"
.\install_dependencies.ps1 -Profile "geostat_extra,spatial_cv,modeling"
```

Các profile:

- `core`: `sf`, `terra`, `gstat`, `sp`, `jsonlite`, `digest`, `yaml`.
- `rag`: `pdftools`, `readr`, `dplyr`, `purrr`, `stringr`, `tibble`.
- `geostat_extra`: `automap`.
- `spatial_cv`: `blockCV`, `CAST`, `rsample`.
- `modeling`: `mgcv`, `ranger`, `randomForest`, `xgboost`, `caret`.

Lưu ý: các package ML đã sẵn sàng để mở rộng, nhưng engine hiện vẫn dùng trend mặc định bằng hồi quy tuyến tính để giữ đúng bản chất RK và tránh đổi thuật toán khi chưa có kiểm định đầy đủ.

## Chuẩn bị input

- Điểm mẫu CSV: `input/points/soil_points.csv`.
- Raster covariates: `input/raster/PC*.tif`.
- Cột bắt buộc theo config: `code`, `lat`, `lon`.
- Các lớp PC được giả định đã crop/mask/buffer đúng vùng nghiên cứu. Project hiện không cần thư mục ROI riêng.

Kiểm tra schema điểm mẫu:

```powershell
.\validate_point_schema.ps1
```

Kiểm tra raster covariates, CRS, độ phân giải, extent và overlap với điểm mẫu:

```powershell
.\validate_raster_schema.ps1
```

Tạo template CSV/Excel:

```powershell
.\create_input_templates.ps1
```

## Chạy nội suy bình thường

```powershell
.\run_rk.bat
```

Hoặc:

```powershell
Rscript scripts\main.R
```

Config chính nằm ở `scripts/00_config.R`.

## Chạy agent-ready một chỉ tiêu

```powershell
.\run_agent.ps1 -Target pH -Request agent\requests\run_request_template.json
```

Output chính:

```text
agent/responses/<run_id>_run_result.json
agent/history/<run_id>/run_result.json
output/agent_runs/<run_id>/
```

## Chạy agent loop có kiểm soát

Workflow loop không gọi LLM thật. Nó chạy iteration, đọc `run_result.json`, validate `ai_decision.json` nếu có, tạo request kế tiếp và dừng theo giới hạn khoa học.

Chạy dry-run để kiểm tra request/log:

```powershell
.\run_agent_loop.ps1 -Target pH -MaxIterations 3 -DryRun
```

Chạy thật và chờ quyết định AI bên ngoài trước khi rerun:

```powershell
.\run_agent_loop.ps1 -Target pH -MaxIterations 3
```

Chạy thật với heuristic nội bộ bảo thủ, chỉ đổi tham số trong whitelist và vẫn qua validator:

```powershell
.\run_agent_loop.ps1 -Target pH -MaxIterations 3 -AutoDecision
```

Output loop nằm trong:

```text
agent/history/<loop_id>/
agent/responses/final_decision_<target>_<loop_id>.json
```

## Chạy nhiều chỉ tiêu trong cùng CSV

Khi CSV có nhiều cột chỉ tiêu, nên dùng batch runner thay vì để engine đoán target:

```powershell
.\run_agent_batch.ps1
```

Hoặc chỉ định danh sách:

```powershell
.\run_agent_batch.ps1 -Targets "pH,Humus,CEC"
```

Dry-run kỹ thuật:

```powershell
.\run_agent_batch.ps1 -Targets pH -DryRun
```

## Auto-neighbor tuning

Mặc định `AUTO_NEIGHBORS <- TRUE`. Engine thử các tổ hợp:

```r
AUTO_NEIGHBOR_NMAX_CANDIDATES <- c(8, 12, 16, 20, 24, 32)
AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES <- c(6000, 8000, 10000, 12000, 15000, 18000)
```

Bảng kết quả nằm trong:

```text
06_report/tables/neighbor_tuning_<target>.csv
```

Người dùng thường không cần tự chỉnh `NMAX_NEIGHBORS` và `SEARCH_RADIUS` trước. Chỉ xem lại khi report cảnh báo thiếu prediction, bản đồ quá nhiễu hoặc quá mượt.

## Report và output

Trong mỗi run folder:

- `05_final_rk/`: GeoTIFF RK và uncertainty STD.
- `06_report/index_<target>.html`: report chính.
- `06_report/interactive/`: variogram tương tác.
- `06_report/tables/`: bảng CSV kỹ thuật.
- `06_report/json/`: JSON evaluation.
- `06_report/logs/`: log chạy.

## Validator và compare runs

Validate quyết định AI:

```powershell
Rscript scripts\agent_validate_decision.R --decision agent\decisions\ai_decision_template.json --request agent\requests\run_request_template.json --output agent\decisions\validated_decision.json
```

So sánh nhiều run. Nên lọc theo target, run prefix hoặc thư mục loop/batch để tránh gom nhầm lịch sử cũ:

```powershell
.\run_agent_compare.ps1 -Target pH -Results agent\responses
Rscript scripts\agent_compare_runs.R --results agent\history\<loop_id>\results --target pH --include_output false --output agent\history\<loop_id>\run_comparison.json
```

Compare không chọn mô hình chỉ vì RMSE thấp nhất; nó cân bằng RMSE, MAE, ME, R²_pred, baseline improvement, nugget/sill, range, class accuracy, uncertainty và cảnh báo.

## RAG cục bộ

Đặt tài liệu bạn có quyền sử dụng vào `knowledge/library/`, sau đó chạy:

```powershell
.\run_rag_inventory.ps1
.\run_rag_build_local_index.ps1
.\run_rag_query.ps1 -Query "spatial cross-validation variogram range" -TopK 8
```

RAG local không tải tài liệu bản quyền, không gửi tài liệu ra ngoài và không commit PDF/chunks vào Git.

## Smoke test

```powershell
.\run_agent_smoke_test.ps1
.\run_agent_loop.ps1 -Target pH -MaxIterations 1 -DryRun
.\run_rag_smoke_test.ps1
```

## Lỗi thường gặp

- Thiếu Rscript: cài R hoặc thêm `Rscript.exe` vào PATH.
- Thiếu package: chạy `check_dependencies.ps1`, sau đó `install_dependencies.ps1` nếu được phép.
- Thiếu input CSV/raster: kiểm tra `POINT_FILE`, `RASTER_DIR`, `RASTER_PATTERN` trong `scripts/00_config.R`.
- Variogram cảnh báo range/nugget: mở `06_report/interactive/variogram_interactive_<target>.html` để xem thủ công.
- R²_pred âm với dữ liệu random/test: không cố chứng minh RK tốt; chỉ dùng kết quả để kiểm tra workflow.