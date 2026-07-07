# AI Agent Workflow For Regression Kriging

TÃ i liá»‡u nÃ y dÃ nh cho Codex/AI agent hoáº·c prompt executor Ä‘á»c nhanh trÆ°á»›c khi Ä‘iá»u phá»‘i nhiá»u iteration Regression Kriging.

## 1. Kiáº¿n trÃºc dá»± Ã¡n

Luá»“ng chÃ­nh:

```text
R engine tÃ­nh toÃ¡n
-> Evaluation rules kiá»ƒm Ä‘á»‹nh káº¿t quáº£
-> File-based API cho agent
-> AI/prompt engine Ä‘á»c káº¿t quáº£, Ä‘á» xuáº¥t thÃ´ng sá»‘
-> Validator kiá»ƒm soÃ¡t Ä‘á» xuáº¥t
-> R cháº¡y láº¡i nhiá»u iteration cÃ³ giá»›i háº¡n
-> So sÃ¡nh cÃ¡c láº§n cháº¡y
-> Chá»n káº¿t quáº£ cuá»‘i cÃ¹ng
-> Xuáº¥t report rÃµ rÃ ng
```

CÃ¡c file chÃ­nh:

- `scripts/main.R`: entry point engine RK.
- `scripts/00_config.R`: config máº·c Ä‘á»‹nh.
- `rk_evaluation/evaluation.R`: evaluation rules, scoring, HTML/CSV/JSON report.
- `scripts/agent_run.R`: cháº¡y má»™t request agent.
- `scripts/agent_validate_decision.R`: kiá»ƒm Ä‘á»‹nh quyáº¿t Ä‘á»‹nh AI.
- `scripts/agent_compare_runs.R`: so sÃ¡nh nhiá»u run.
- `scripts/agent_utils.R`: JSON, whitelist, safety helpers.
- `run_agent.ps1`: wrapper PowerShell cho agent-ready mode.

## 2. R engine hiá»‡n táº¡i

`main.R` Ä‘á»c `00_config.R`, sau Ä‘Ã³ cÃ³ thá»ƒ Ä‘á»c thÃªm override file qua biáº¿n mÃ´i trÆ°á»ng `RK_CONFIG_OVERRIDE`. Override nÃ y chá»‰ dÃ¹ng cho agent iteration vÃ  khÃ´ng sá»­a config gá»‘c.

Engine hiá»‡n cÃ³:

- Äá»c CSV Ä‘iá»ƒm máº«u.
- Äá»c cÃ¡c raster `PC*.tif`.
- Chuyá»ƒn Ä‘iá»ƒm/raster sang UTM theo `UTM_EPSG`.
- Extract PC táº¡i Ä‘iá»ƒm máº«u.
- Fit regression `target ~ PC1 + ...`.
- Fit hoáº·c dÃ¹ng manual residual variogram.
- Kriging pháº§n dÆ°.
- Xuáº¥t raster RK vÃ  uncertainty STD.
- Cháº¡y random vÃ  spatial k-means CV náº¿u báº­t.
- Xuáº¥t HTML/CSV/JSON report.

## 3. Evaluation rules

`rk_evaluation/evaluation.R` Ä‘Ã¡nh giÃ¡:

- Data quality: sá»‘ Ä‘iá»ƒm, outlier, valid range, duplicate coordinate.
- Regression trend: RÂ² vÃ  residual.
- Residual variogram: nugget/sill, range, range so vá»›i Ä‘iá»ƒm máº«u/extent, lag bins.
- Cross-validation: RMSE, MAE, ME, RÂ²_pred, NRMSE, RPD, RPIQ.
- Class evaluation náº¿u profile cÃ³ class bins.
- Uncertainty tá»« residual kriging STD.

Hard caps hiá»‡n cÃ³ gá»“m: Ã­t Ä‘iá»ƒm, RÂ²_pred Ã¢m, RK khÃ´ng cáº£i thiá»‡n, class accuracy tháº¥p vá»›i profile phÃ¢n cáº¥p.

## 4. File-based API

KhÃ´ng cÃ³ server. AI agent trao Ä‘á»•i qua file:

```text
agent/requests/run_request_template.json
agent/responses/<run_id>_run_result.json
agent/decisions/ai_decision_template.json
agent/history/<run_id>/
agent/prompts/
agent/schemas/
```

## 5. run_request.json

Request quy Ä‘á»‹nh `run_id`, `target_field`, `output_root`, `parameters`, `safety_limits`.

Cháº¡y má»™t request:

```powershell
.\run_agent.ps1 -Target pH -Request agent\requests\run_request_template.json
```

`agent_run.R` táº¡o file override trong `agent/history/<run_id>/override_<run_id>.R`, gá»i `scripts/main.R`, rá»“i tá»•ng há»£p `run_result.json`.

## 6. run_result.json

Sau má»—i run cÃ³ tá»‘i thiá»ƒu:

- `run_id`, `target_field`, `status`, `output_folder`.
- `quality.final_grade`, `quality.final_score`, `quality.decision_hint`.
- `metrics`: RK RMSE, MAE, ME, RÂ²_pred, NRMSE_mean, RPD.
- `model_comparison`: regression-only, OK, RK RMSE.
- `variogram`: model, nugget, psill, sill, range, practical range, nugget/sill, range_hit_max.
- `warnings`, `recommendations`.
- `files`: link tá»›i report HTML, evaluation JSON, CSV, variogram tÆ°Æ¡ng tÃ¡c, logs.
- `missing_outputs`: file nÃ o khÃ´ng táº¡o Ä‘Æ°á»£c hoáº·c chÆ°a cÃ³.

## 7. ai_decision.json

Quyáº¿t Ä‘á»‹nh há»£p lá»‡:

```text
ACCEPT
RERUN
MANUAL_REVIEW
REJECT
```

Confidence há»£p lá»‡:

```text
low
medium
high
```

Validate báº±ng:

```powershell
Rscript scripts\agent_validate_decision.R --decision agent\decisions\ai_decision_template.json --request agent\requests\run_request_template.json --output agent\decisions\validated_decision.json
```

## 8. Whitelist parameters

AI Ä‘Æ°á»£c Ä‘á» xuáº¥t thay Ä‘á»•i:

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
CV_METHODS
CV_K_FOLDS
CLAMP_TO_SAMPLE_RANGE
TARGET_TRANSFORM
```

LÆ°u Ã½: `TARGET_TRANSFORM` Ä‘Ã£ Ä‘Æ°á»£c giá»¯ chá»— trong whitelist nhÆ°ng engine hiá»‡n chÆ°a implement transform. Validator sáº½ chuyá»ƒn sang human review náº¿u AI dÃ¹ng tham sá»‘ nÃ y.

## 9. Protected settings

AI khÃ´ng Ä‘Æ°á»£c tá»± Ã½ sá»­a:

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
source R scripts
```

Náº¿u AI muá»‘n thay Ä‘á»•i cÃ¡c pháº§n nÃ y, validator pháº£i dá»«ng á»Ÿ `MANUAL_REVIEW`.

## 9b. Auto-neighbor tuning

Project máº·c Ä‘á»‹nh báº­t:

```text
AUTO_NEIGHBORS <- TRUE
```

TrÆ°á»›c CV chÃ­nh vÃ  trÆ°á»›c khi táº¡o báº£n Ä‘á»“ cuá»‘i, engine cháº¡y spatial CV trÃªn candidate grid vá»«a Ä‘á»§ rá»™ng, thiáº¿t káº¿ cho dá»¯ liá»‡u tháº­t khoáº£ng 100 Ä‘iá»ƒm máº«u vÃ  Æ°u tiÃªn cháº¥t lÆ°á»£ng nhÆ°ng váº«n trÃ¡nh search quÃ¡ rá»™ng gÃ¢y lÃ m mÆ°á»£t gáº§n-global:

```text
AUTO_NEIGHBOR_NMAX_CANDIDATES
AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES
```

Báº£ng káº¿t quáº£ náº±m á»Ÿ:

```text
06_report/tables/neighbor_tuning_<target>.csv
```

Grid máº·c Ä‘á»‹nh hiá»‡n cÃ³ 36 tá»• há»£p: `NMAX_NEIGHBORS = 8, 12, 16, 20, 24, 32` vÃ  `SEARCH_RADIUS = 6000, 8000, 10000, 12000, 15000, 18000`. CÃ¡c giÃ¡ trá»‹ nÃ y giá»¯ kriging á»Ÿ dáº¡ng local, bao phá»§ vÃ¹ng tá»« cá»¥c bá»™ tá»›i hÆ¡i mÆ°á»£t, vÃ  radius Ä‘Æ°á»£c Ä‘áº·t quanh practical range/cutoff thay vÃ¬ má»Ÿ quÃ¡ xa. Quy táº¯c chá»n khÃ´ng dá»±a riÃªng vÃ o RMSE. Score cÃ³ tÃ­nh RMSE, bias ME, tá»· lá»‡ prediction bá»‹ thiáº¿u vÃ  pháº¡t nháº¹ khi RÂ²_pred Ã¢m. Agent cÃ³ thá»ƒ Ä‘á» xuáº¥t thu háº¹p hoáº·c má»Ÿ rá»™ng candidate grid, nhÆ°ng validator váº«n kiá»ƒm soÃ¡t báº±ng `min_neighbors`, `max_neighbors`, `min_range`, `max_range`.
## 10. Safety rules

Safety limits náº±m trong request:

- `max_iterations`
- `allow_delete_points`
- `allow_modify_raw_data`
- `min_range`, `max_range`
- `min_neighbors`, `max_neighbors`

Cross-validation khÃ´ng Ä‘Æ°á»£c táº¯t trong agent workflow. `agent_run.R` luÃ´n set `RUN_CROSS_VALIDATION <- TRUE` trong override.

## 11. Iteration workflow

1. Cháº¡y `run_agent.ps1` vá»›i request hiá»‡n táº¡i.
2. AI Ä‘á»c `agent/responses/<run_id>_run_result.json`.
3. AI tráº£ vá» `ai_decision.json` theo prompt trong `agent/prompts/`.
4. Cháº¡y validator.
5. Náº¿u `RERUN` há»£p lá»‡, táº¡o request má»›i vá»›i `run_id` má»›i vÃ  accepted parameters.
6. Láº·p láº¡i tá»›i khi Ä‘áº¡t stop condition.
7. Cháº¡y compare runs.
8. Má»Ÿ report cá»§a selected run.

## 12. Stop conditions

Dá»«ng náº¿u:

- Grade A hoáº·c B vÃ  khÃ´ng cÃ³ cáº£nh bÃ¡o nghiÃªm trá»ng.
- Rerun 2 láº§n liÃªn tiáº¿p khÃ´ng cáº£i thiá»‡n RMSE khoáº£ng 3-5%.
- RMSE tá»‘t hÆ¡n nhÆ°ng variogram xáº¥u hÆ¡n rÃµ rá»‡t.
- Äáº¡t `max_iterations`.
- AI yÃªu cáº§u `MANUAL_REVIEW`.
- RÂ²_pred váº«n Ã¢m sau nhiá»u láº§n cháº¡y.
- KhÃ´ng cÃ³ candidate variogram há»£p lá»‡.
- Validator tá»« chá»‘i quyáº¿t Ä‘á»‹nh AI.

## 13. Compare runs

```powershell
Rscript scripts\agent_compare_runs.R --results agent\responses --output agent\history\run_comparison.json
```

Output gá»“m `selected_run_id`, `decision`, `reason`, `why_not_lowest_rmse`, `human_review_required` vÃ  CSV tÃ³m táº¯t. Quy táº¯c chá»n khÃ´ng dá»±a riÃªng vÃ o RMSE tháº¥p nháº¥t.

## 14. KhÃ´ng Ä‘Æ°á»£c AI tá»± Ã½ sá»­a

- KhÃ´ng sá»­a input CSV/raster.
- KhÃ´ng xÃ³a Ä‘iá»ƒm máº«u.
- KhÃ´ng Ä‘á»•i CRS.
- KhÃ´ng sá»­a source engine.
- KhÃ´ng bá» cross-validation.
- KhÃ´ng táº¡o uncertainty giáº£.
- KhÃ´ng chá»n mÃ´ hÃ¬nh chá»‰ vÃ¬ RMSE tháº¥p nháº¥t.

## 15. ThÃªm chá»‰ tiÃªu hoáº·c evaluation profile

ThÃªm hoáº·c chá»‰nh profile trong:

```text
config/evaluation_profiles.R
```

Profile nÃªn khai bÃ¡o alias, valid range, soft warning range, class bins náº¿u cÃ³ phÃ¢n cáº¥p nÃ´ng há»c, vÃ  scoring weights náº¿u cáº§n.
## 16. Batch nhiều chỉ tiêu

Khi CSV có nhiều cột chỉ tiêu, không chạy `scripts/main.R` ở chế độ `TARGET_FIELD <- "auto"` để đoán target. Agent nên dùng batch wrapper:

```powershell
.\run_agent_batch.ps1
```

Hoặc chỉ định danh sách:

```powershell
.\run_agent_batch.ps1 -Targets "pH,Humus,CEC"
```

Luồng batch:

1. Đọc `POINT_FILE` trong `scripts/00_config.R`.
2. Xác định các cột phân tích sau khi loại `code`, `lat`, `lon`.
3. Tạo `agent/requests/run_request_<target>_iter_001.json` cho từng target.
4. Gọi `scripts/agent_run.R` tuần tự.
5. Ghi log riêng tại `agent/history/batch_<timestamp>/agent_run_<target>.log`.
6. Xuất `agent/responses/batch_summary_*.json` và `.csv`.

Trước batch nên chạy:

```powershell
.\validate_point_schema.ps1
```

Validator schema báo số giá trị không thiếu, cột không numeric, profile được match, và cột nào phải dùng `generic_continuous`.

## 17. Input template cho agent và người dùng

Tạo template:

```powershell
.\create_input_templates.ps1
```

Các file template nằm trong `input/points/`. AI agent không được tự sửa file dữ liệu gốc; chỉ dùng template để hướng dẫn người dùng chuẩn bị CSV/Excel đúng tên cột. Nếu cần thêm chỉ tiêu mới chưa có profile riêng, hãy chỉnh `config/evaluation_profiles.R` thay vì đổi logic engine.

## 18. Output naming trong workflow tự động

Normal run có thể hỏi tên dự án khi `ASK_OUTPUT_FOLDER <- TRUE`. Blank nghĩa là `<target>-<timestamp>`; nhập tên nghĩa là `<project>_<target>-<timestamp>`. Agent workflow luôn set `ASK_OUTPUT_FOLDER <- FALSE` và dùng `RUN_NAME_OVERRIDE <- run_id`, vì workflow tự động không được chờ người dùng nhập tên giữa chừng.