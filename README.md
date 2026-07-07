# Regression Kriging R Project

Dá»± Ã¡n nÃ y cháº¡y ná»™i suy Regression Kriging cho báº£n Ä‘á»“ Ä‘áº¥t báº±ng R/Rscript. Engine hiá»‡n táº¡i dÃ¹ng dá»¯ liá»‡u Ä‘iá»ƒm máº«u, cÃ¡c raster PC Ä‘Ã£ Ä‘Æ°á»£c xá»­ lÃ½ sáºµn theo vÃ¹ng nghiÃªn cá»©u vÃ  buffer, sau Ä‘Ã³ xuáº¥t báº£n Ä‘á»“ RK, báº£n Ä‘á»“ Ä‘á»™ báº¥t Ä‘á»‹nh, variogram, cross-validation vÃ  report Ä‘Ã¡nh giÃ¡.

## YÃªu cáº§u pháº§n má»m

- R vÃ  `Rscript` cÃ³ trong `PATH`.
- PowerShell trÃªn Windows.
- CÃ¡c package R chÃ­nh: `sf`, `terra`, `gstat`, `sp`.
- `jsonlite` lÃ  tÃ¹y chá»n. Náº¿u chÆ°a cÃ i, project váº«n cÃ³ bá»™ Ä‘á»c/ghi JSON nháº¹ báº±ng base R cho agent workflow.

## Chuáº©n bá»‹ input

- Äiá»ƒm máº«u CSV: `input/points/soil_points.csv`.
- Raster covariates: `input/raster/PC*.tif`.
- CSV cáº§n cÃ³ cá»™t tá»a Ä‘á»™ theo cáº¥u hÃ¬nh trong `scripts/00_config.R`: `lat`, `lon`, `code`.
- CÃ¡c lá»›p PC Ä‘Æ°á»£c giáº£ Ä‘á»‹nh Ä‘Ã£ crop/mask/buffer Ä‘Ãºng vÃ¹ng cáº§n ná»™i suy. Project hiá»‡n khÃ´ng dÃ¹ng ROI riÃªng.

## Cháº¡y ná»™i suy bÃ¬nh thÆ°á»ng

CÃ¡ch cÅ© váº«n giá»¯ nguyÃªn:

```powershell
.\run_rk.bat
```

Hoáº·c cháº¡y trá»±c tiáº¿p:

```powershell
Rscript scripts\main.R
```

Cáº¥u hÃ¬nh chÃ­nh náº±m á»Ÿ:

```text
scripts/00_config.R
```

## Tá»± chá»n neighbors

Máº·c Ä‘á»‹nh project báº­t `AUTO_NEIGHBORS <- TRUE` trong `scripts/00_config.R`. Pipeline sáº½ cháº¡y spatial CV trÃªn má»™t lÆ°á»›i vá»«a Ä‘á»§ rá»™ng gá»“m `NMAX_NEIGHBORS` vÃ  `SEARCH_RADIUS`, sau Ä‘Ã³ chá»n bá»™ dÃ¹ng cho CV chÃ­nh vÃ  báº£n Ä‘á»“ cuá»‘i. Grid hiá»‡n Ä‘Æ°á»£c thiáº¿t káº¿ cho dá»¯ liá»‡u tháº­t khoáº£ng 100 Ä‘iá»ƒm máº«u, Æ°u tiÃªn cháº¥t lÆ°á»£ng nhÆ°ng váº«n trÃ¡nh search quÃ¡ rá»™ng gÃ¢y lÃ m mÆ°á»£t gáº§n-global.

Káº¿t quáº£ tuning náº±m á»Ÿ:

```text
06_report/tables/neighbor_tuning_<target>.csv
```

Grid máº·c Ä‘á»‹nh hiá»‡n thá»­ 36 tá»• há»£p: `NMAX_NEIGHBORS = 8, 12, 16, 20, 24, 32` vÃ  `SEARCH_RADIUS = 6000, 8000, 10000, 12000, 15000, 18000`. NhÃ³m giÃ¡ trá»‹ nÃ y giá»¯ kriging á»Ÿ dáº¡ng local, trÃ¡nh dÃ¹ng quÃ¡ nhiá»u Ä‘iá»ƒm xa gÃ¢y lÃ m mÆ°á»£t quÃ¡ má»©c, Ä‘á»“ng thá»i váº«n thá»­ Ä‘á»§ rá»™ng quanh practical range/cutoff cá»§a variogram. NgÆ°á»i dÃ¹ng bÃ¬nh thÆ°á»ng khÃ´ng cáº§n chá»‰nh `NMAX_NEIGHBORS` trÆ°á»›c. Chá»‰ nÃªn xem láº¡i khi report cáº£nh bÃ¡o thiáº¿u neighbor trong CV, báº£n Ä‘á»“ quÃ¡ Ä‘á»‘m/nhiá»…u, hoáº·c báº£n Ä‘á»“ quÃ¡ mÆ°á»£t.
## Output bÃ¬nh thÆ°á»ng

Má»—i láº§n cháº¡y táº¡o má»™t thÆ° má»¥c trong `output/`. CÃ¡c file quan trá»ng náº±m á»Ÿ:

- `05_final_rk/`: GeoTIFF báº£n Ä‘á»“ RK vÃ  uncertainty STD.
- `06_report/index_<target>.html`: report chÃ­nh nÃªn má»Ÿ Ä‘áº§u tiÃªn.
- `06_report/interactive/`: variogram tÆ°Æ¡ng tÃ¡c.
- `06_report/tables/`: báº£ng CSV ká»¹ thuáº­t.
- `06_report/json/`: JSON Ä‘Ã¡nh giÃ¡.
- `06_report/logs/`: log cháº¡y.

## Cháº¡y agent-ready mode

Agent-ready mode dÃ¹ng JSON request, khÃ´ng sá»­a trá»±c tiáº¿p `00_config.R`.

```powershell
.\run_agent.ps1 -Target pH -Request agent\requests\run_request_template.json
```

Sau khi cháº¡y, káº¿t quáº£ tÃ³m táº¯t cho AI agent náº±m á»Ÿ:

```text
agent/responses/<run_id>_run_result.json
agent/history/<run_id>/run_result.json
output/agent_runs/<run_id>/run_result.json
```

## Validate quyáº¿t Ä‘á»‹nh AI

```powershell
Rscript scripts\agent_validate_decision.R --decision agent\decisions\ai_decision_template.json --request agent\requests\run_request_template.json --output agent\decisions\validated_decision.json
```

Validator chá»‰ nháº­n tham sá»‘ náº±m trong whitelist vÃ  sáº½ chuyá»ƒn sang `MANUAL_REVIEW` náº¿u AI cá»‘ sá»­a input, CRS, raw data hoáº·c source script.

## So sÃ¡nh nhiá»u láº§n cháº¡y

```powershell
Rscript scripts\agent_compare_runs.R --results agent\responses --output agent\history\run_comparison.json
```

Script nÃ y khÃ´ng chá»n mÃ´ hÃ¬nh chá»‰ vÃ¬ RMSE tháº¥p nháº¥t. NÃ³ cÃ¢n báº±ng RMSE, MAE, ME, RÂ²_pred, cáº£i thiá»‡n so vá»›i baseline, nugget/sill, range, range-hit-max vÃ  sá»‘ cáº£nh bÃ¡o.

## Smoke test

```powershell
.\run_agent_smoke_test.ps1
```

Smoke test kiá»ƒm tra Ä‘á»c request, validator, reject tham sá»‘ nguy hiá»ƒm, compare fake runs vÃ  vÃ­ dá»¥ lá»‡nh trong README. Test nÃ y khÃ´ng cháº¡y full raster RK.

## Lá»—i thÆ°á»ng gáº·p

- `Rscript was not found on PATH`: cÃ i R hoáº·c thÃªm thÆ° má»¥c chá»©a `Rscript.exe` vÃ o PATH.
- `Missing R package`: cÃ i package R cÃ²n thiáº¿u, vÃ­ dá»¥ `install.packages("terra")`.
- `TARGET_FIELD does not exist`: kiá»ƒm tra tÃªn cá»™t chá»‰ tiÃªu trong CSV hoáº·c tham sá»‘ `-Target`.
- Variogram cáº£nh bÃ¡o range quÃ¡ xa hoáº·c nugget/sill cao: má»Ÿ `06_report/interactive/variogram_interactive_<target>.html` Ä‘á»ƒ kiá»ƒm tra thá»§ cÃ´ng.
- CV cÃ³ prediction bá»‹ thiáº¿u: tÄƒng máº­t Ä‘á»™ máº«u, kiá»ƒm tra `SEARCH_RADIUS`, hoáº·c xem láº¡i phÃ¢n bá»‘ Ä‘iá»ƒm máº«u.
## Chạy nhiều chỉ tiêu trong cùng CSV

Project hiện xử lý an toàn theo nguyên tắc: một lần chạy RK chỉ nội suy một chỉ tiêu. Nếu CSV chỉ có một cột chỉ tiêu và `TARGET_FIELD <- "auto"`, engine sẽ tự chọn cột đó. Nếu CSV có nhiều cột chỉ tiêu, không nên để engine đoán bừa; hãy dùng batch runner hoặc đặt `TARGET_FIELD` rõ ràng.

Kiểm tra file điểm mẫu trước khi chạy:

```powershell
.\validate_point_schema.ps1
```

Chạy tất cả các chỉ tiêu phát hiện trong CSV bằng agent-ready batch:

```powershell
.\run_agent_batch.ps1
```

Chạy một nhóm chỉ tiêu cụ thể:

```powershell
.\run_agent_batch.ps1 -Targets "pH,Humus,CEC"
```

Batch runner sẽ tạo request riêng cho từng chỉ tiêu, chạy tuần tự, ghi log riêng trong `agent/history/batch_<timestamp>/`, và xuất bảng tổng hợp tại `agent/responses/batch_summary_*.csv/json`. Bảng tổng hợp có `profile_name` và `profile_matched` để biết chỉ tiêu đó dùng evaluation profile riêng hay fallback tổng quát.

## Template input và tên cột chuẩn

Tạo template CSV/Excel cho file điểm mẫu:

```powershell
.\create_input_templates.ps1
```

Output chính:

- `input/points/soil_points_template.csv`
- `input/points/soil_points_template.xlsx` hoặc file timestamp nếu Excel cũ đang bị khóa
- `input/points/indicator_profiles.csv`
- `input/points/soil_points_template_instructions.csv`

Nên dùng tên cột canonical trong `indicator_profiles.csv`, ví dụ `pH`, `Humus`, `CEC`, `N_total`, `P_Olsen`, `P_Bray`, `K_available_mgkg`, `K_exchangeable_cmol`, `Ca_exchangeable`, `Mg_exchangeable`, `S_available`, `B_available`, `Zn_available`, `Cu_available`, `Mn_available`, `Fe_available`, `EC`. Nếu dùng alias được hỗ trợ thì vẫn match profile; nếu không match, report sẽ cảnh báo đang dùng `generic_continuous`.

## Quy tắc đặt tên output

`OUTPUT_NAME_PREFIX` mặc định hiện để trống. Khi chạy thường và `ASK_OUTPUT_FOLDER <- TRUE`, chương trình sẽ hỏi tên dự án/output sau khi biết target:

- Bỏ trống: folder là `<target>-<timestamp>`.
- Có nhập tên: folder là `<ten_du_an>_<target>-<timestamp>`.

Agent-ready mode không hỏi tương tác; tên folder lấy theo `run_id` trong request để workflow tự động không bị treo.