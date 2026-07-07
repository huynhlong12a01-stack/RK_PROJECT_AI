# EXECUTING PROMPT - R Regression Kriging Agent Workflow

Bạn là AI coding agent đang làm việc trực tiếp trong thư mục dự án R Regression Kriging hiện có.

Nhiệm vụ lần này **không phải thiết kế lại dự án**, mà là thực thi workflow đã có để:

```text
Chạy Regression Kriging
→ Kiểm định kết quả bằng evaluation rules
→ Đọc JSON output cho agent
→ Chạy lại có kiểm soát nếu thật sự cần
→ So sánh các iteration
→ Chọn kết quả cuối cùng
→ Xuất final decision rõ ràng cho người dùng
```

Dự án chạy bằng:

```text
R
Rscript
PowerShell
File-based JSON API
```

Không chuyển sang Python. Không dựng web server. Không sửa dữ liệu gốc. Không hard-code đường dẫn máy cá nhân.

---

## 0. Thông tin mặc định của dự án hiện tại

Dự án hiện đã có agent-ready workflow. Ưu tiên chạy agent workflow nếu các file sau tồn tại:

```text
scripts/agent_run.R
scripts/agent_validate_decision.R
scripts/agent_compare_runs.R
run_agent.ps1
agent/requests/run_request_template.json
AGENT_README.md
```

Config chính:

```text
scripts/00_config.R
```

Engine chính:

```text
scripts/main.R
```

Evaluation module:

```text
rk_evaluation/evaluation.R
```

Output mặc định:

```text
output/agent_runs/<run_id>/
agent/responses/
agent/history/
```

Nếu `TARGET_FIELD <- "auto"`, ưu tiên target theo thứ tự:

```text
pH
Humus
CEC
```

Chỉ chọn target có thật trong CSV input.

Giới hạn iteration mặc định:

```text
MAX_ITERATIONS = 3
```

Chỉ tăng lên 5 nếu người dùng yêu cầu rõ hoặc mỗi lần chạy rất nhanh và có lý do khoa học rõ ràng.

---

## 1. Đọc tài liệu trước khi chạy

Trước khi chạy bất kỳ lệnh nào, đọc nếu tồn tại:

```text
README.md
AGENT_README.md
docs/AI_AGENT_WORKFLOW.md
scripts/00_config.R
scripts/agent_run.R
scripts/agent_validate_decision.R
scripts/agent_compare_runs.R
run_agent.ps1
run_rk.bat
run_rk.ps1
```

Sau khi đọc, xác định:

```text
1. Lệnh chạy RK thông thường.
2. Lệnh chạy agent-ready workflow.
3. File config chính.
4. Target field mặc định.
5. Output root.
6. Agent workflow đã sẵn sàng chưa.
7. AUTO_NEIGHBORS có đang bật không.
```

Không chạy lung tung trước khi hiểu entry point.

---

## 2. Kiểm tra môi trường

Kiểm tra:

```text
1. Rscript có trong PATH không.
2. PowerShell chạy được không.
3. Package R bắt buộc có đủ không: sf, terra, gstat, sp.
4. jsonlite là optional, không bắt buộc.
5. POINT_FILE trong config có tồn tại không.
6. RASTER_DIR có các file PC*.tif không.
7. Thư mục output ghi được không.
```

Nếu thiếu package, không tự cài trừ khi có script setup rõ ràng. Báo package thiếu và gợi ý lệnh cài, ví dụ:

```r
install.packages("terra")
```

Nếu thiếu input file, dừng và báo rõ file nào thiếu.

---

## 3. Chọn workflow

Ưu tiên 1: Agent-ready workflow.

Dùng nếu có:

```text
scripts/agent_run.R
run_agent.ps1
agent/requests/run_request_template.json
AGENT_README.md
```

Ưu tiên 2: RK workflow thông thường.

Dùng nếu agent workflow thiếu nhưng có:

```text
scripts/main.R
scripts/00_config.R
run_rk.bat
```

Ưu tiên 3: Nếu agent workflow chưa sẵn sàng.

Báo rõ:

```text
Agent-ready workflow chưa sẵn sàng.
Các file còn thiếu là: ...
Cần chạy prompt nâng cấp trước, hoặc tôi có thể bổ sung tối thiểu các file còn thiếu.
```

Chỉ sửa code tối thiểu nếu lỗi nhỏ như wrapper gọi sai script, log sai, hoặc đường dẫn tương đối sai.

---

## 4. Tạo run request mới

Nếu chạy agent workflow, tạo request mới từ template:

```text
agent/requests/run_request_template.json
```

Tên file:

```text
agent/requests/run_request_<TARGET>_iter_001.json
```

Cập nhật các trường chính:

```json
{
  "run_id": "<TARGET>_iter_001",
  "target_field": "<TARGET>",
  "output_root": "output/agent_runs",
  "safety_limits": {
    "max_iterations": 3,
    "allow_delete_points": false,
    "allow_modify_raw_data": false,
    "min_range": 500,
    "max_range": 25000,
    "min_neighbors": 4,
    "max_neighbors": 50
  }
}
```

Giữ nguyên các tham số hợp lệ có sẵn trong template, đặc biệt:

```json
"AUTO_NEIGHBORS": true,
"AUTO_NEIGHBOR_NMAX_CANDIDATES": [8, 12, 16, 20, 24, 32],
"AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES": [6000, 8000, 10000, 12000, 15000, 18000],
"AUTO_NEIGHBOR_CV_METHOD": "spatial_kmeans",
"AUTO_NEIGHBOR_MAX_CANDIDATES": 50
```

Không hard-code đường dẫn tuyệt đối.

---

## 5. Chạy iteration 1

Nếu có wrapper PowerShell:

```powershell
.\run_agent.ps1 -Target <TARGET> -Request agent\requests\run_request_<TARGET>_iter_001.json
```

Nếu không có wrapper nhưng có script R:

```powershell
Rscript scripts\agent_run.R --request agent\requests\run_request_<TARGET>_iter_001.json --target <TARGET>
```

Sau khi chạy, tìm output chính:

```text
agent/responses/<run_id>_run_result.json
agent/history/<run_id>/run_result.json
output/agent_runs/<run_id>/run_result.json
output/agent_runs/<run_id>/06_report/index_<target>.html
output/agent_runs/<run_id>/06_report/json/evaluation_<target>.json
output/agent_runs/<run_id>/06_report/json/variogram_diagnostics_<target>.json
output/agent_runs/<run_id>/06_report/tables/model_comparison_<target>.csv
output/agent_runs/<run_id>/06_report/tables/cv_results_<target>.csv
output/agent_runs/<run_id>/06_report/tables/neighbor_tuning_<target>.csv
output/agent_runs/<run_id>/06_report/tables/rk_report_<target>.csv
output/agent_runs/<run_id>/06_report/interactive/variogram_interactive_<target>.html
output/agent_runs/<run_id>/05_final_rk/RK_final_<target>_utm.tif
output/agent_runs/<run_id>/05_final_rk/RK_uncertainty_STD_<target>_utm.tif
```

Nếu tên hoặc thư mục khác, ghi lại chính xác.

---

## 6. Đọc và đánh giá kết quả iteration

Ưu tiên đọc:

```text
agent/responses/<run_id>_run_result.json
```

Nếu cần chi tiết hơn, đọc:

```text
06_report/json/evaluation_<target>.json
06_report/tables/neighbor_tuning_<target>.csv
06_report/tables/model_comparison_<target>.csv
06_report/tables/rk_report_<target>.csv
```

Trích xuất nếu có:

```text
target_field
run_id
status
final_grade
final_score
decision_hint
RK_RMSE
RK_MAE
RK_ME
RK_R2_pred
Regression-only RMSE
Ordinary Kriging RMSE
Regression Kriging RMSE
RK improvement vs regression-only
RK improvement vs OK
kriging.auto_neighbors_enabled
kriging.auto_neighbors_method
kriging.selected_nmax_neighbors
kriging.selected_search_radius
variogram model
nugget
psill
sill
range
practical_range
nugget/sill ratio
range_hit_max
class_accuracy nếu có
severe_misclassification_rate nếu có
uncertainty mean/max nếu có
warnings
recommendations
missing_outputs
```

Đánh giá theo nguyên tắc:

```text
Không chọn mô hình chỉ vì RMSE thấp nhất.
Ưu tiên kết quả có:
- R²_pred dương.
- ME gần 0.
- RK cải thiện so với regression-only.
- RK cải thiện hoặc không kém rõ so với Ordinary Kriging.
- Nugget/Sill không quá cao.
- Range không chạm max.
- Practical range không quá dài so với cutoff/vùng dữ liệu.
- Ít cảnh báo nghiêm trọng.
- Class accuracy hợp lý nếu chỉ tiêu có phân cấp.
- Uncertainty không quá cao trên diện tích lớn nếu có.
```

---

## 7. Auto-neighbor tuning trong dự án hiện tại

Dự án hiện có `AUTO_NEIGHBORS <- TRUE`.

Không tự chỉnh `NMAX_NEIGHBORS` và `SEARCH_RADIUS` thủ công trong lần chạy đầu, trừ khi người dùng yêu cầu rõ.

Pipeline tự thử 36 tổ hợp:

```r
AUTO_NEIGHBOR_NMAX_CANDIDATES <- c(8, 12, 16, 20, 24, 32)
AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES <- c(6000, 8000, 10000, 12000, 15000, 18000)
```

Bảng kết quả nằm ở:

```text
06_report/tables/neighbor_tuning_<target>.csv
```

Khi đọc kết quả, phải báo rõ:

```text
selected_nmax_neighbors
selected_search_radius
```

Không kết luận rằng neighbor tốt nhất chỉ vì RMSE thấp nhất. Cơ chế chọn có tính RMSE, bias ME, missing predictions và phạt R²_pred âm.

Chỉ đề xuất sửa candidate grid khi:

```text
- Có quá nhiều prediction bị thiếu do search radius quá nhỏ.
- Bản đồ quá mượt do radius/nmax quá lớn.
- Bản đồ quá đốm/nhiễu do neighborhood quá nhỏ.
- Người dùng chấp nhận chạy lâu hơn hoặc muốn kiểm tra rất sâu.
```

---

## 8. Quyết định sau mỗi iteration

Chọn một trong bốn quyết định:

```text
ACCEPT
RERUN
MANUAL_REVIEW
REJECT
```

### ACCEPT nếu

```text
- Grade A hoặc B.
- R²_pred dương.
- ME gần 0.
- RK tốt hơn regression-only.
- RK không kém rõ so với Ordinary Kriging.
- Variogram không có cảnh báo nghiêm trọng.
- Range không chạm max.
- Nugget/Sill không quá cao.
- Không có hard-fail khoa học.
```

### RERUN nếu

```text
- RK có tiềm năng nhưng còn cảnh báo có thể cải thiện bằng tham số.
- Range quá lớn hoặc chạm max.
- Nugget/Sill hơi cao.
- RK chỉ cải thiện nhẹ.
- CV chưa ổn nhưng chưa phải hard-fail.
- Auto-neighbor cho thấy nhiều missing predictions nhưng có candidate tốt hơn để thử.
```

### MANUAL_REVIEW nếu

```text
- Variogram khó đánh giá.
- Experimental variogram không rõ cấu trúc.
- Có nhiều outlier hoặc dữ liệu nghi ngờ.
- Cần người dùng xem bản đồ/biểu đồ.
- Kết quả không đủ xấu để reject nhưng cũng không đủ tin để accept/rerun tự động.
```

### REJECT nếu

```text
- R²_pred âm.
- RK không cải thiện so với regression-only.
- Variogram không có cấu trúc rõ.
- Nugget/Sill quá cao.
- Dữ liệu quá ít.
- Class accuracy quá thấp với chỉ tiêu có phân cấp.
- Output không đáng tin.
```

Nếu có hard-fail như `R²_pred âm` và `RK không cải thiện so với regression-only`, dừng sớm. Không cố rerun chỉ để tìm RMSE đẹp hơn.

---

## 9. Nếu cần RERUN, tạo ai_decision JSON

Nếu quyết định là `RERUN`, tạo:

```text
agent/decisions/ai_decision_<TARGET>_iter_001.json
```

Schema:

```json
{
  "decision": "RERUN",
  "confidence": "medium",
  "reason": "...",
  "next_parameters": {},
  "must_keep": {
    "RUN_CROSS_VALIDATION": true
  },
  "stop_condition": {
    "accept_if_rmse_improves_percent": 5,
    "accept_if_warnings_reduce": true,
    "max_more_iterations": 2
  },
  "human_review_required": false
}
```

Whitelist hiện tại gồm:

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
TARGET_TRANSFORM nếu project có hỗ trợ
```

Không được đề xuất thay đổi:

```text
POINT_FILE
RASTER_DIR
ROI_FILE
UTM_EPSG
EXPORT_EPSG
CODE_COL
LAT_COL
LON_COL
raw input data
source R scripts
main engine logic
```

Lưu ý: `TARGET_TRANSFORM` hiện chỉ là tham số giữ chỗ. Nếu engine chưa hỗ trợ transform thì không tự bật transform sâu.

---

## 10. Gợi ý chọn thông số RERUN

Không áp dụng máy móc. Dựa vào cảnh báo thực tế.

Nếu range chạm max hoặc practical range quá dài:

```text
- Giảm VARIOGRAM_RANGE_MAX.
- Giảm MANUAL_RANGE nếu đang manual.
- Thử Sph hoặc Exp dưới cùng giới hạn range.
- Giữ cross-validation.
```

Nếu nugget/sill cao:

```text
- Kiểm tra outlier.
- Thử lag width khác.
- Thử model khác.
- Không ép grade tốt nếu cấu trúc không gian yếu.
```

Nếu bản đồ quá đốm/nhiễu:

```text
- Tăng range vừa phải.
- Cho AUTO_NEIGHBOR_NMAX_CANDIDATES có giá trị lớn hơn trong giới hạn an toàn.
- Tăng search radius vừa phải.
```

Nếu bản đồ quá mượt:

```text
- Giảm range.
- Thu hẹp AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES.
- Giảm nhóm nmax lớn.
- Kiểm tra overfit trend.
```

Nếu CV có nhiều missing predictions:

```text
- Tăng các radius candidate.
- Không tắt CV.
- Không silently extrapolate nếu project đang yêu cầu neighbor trong SEARCH_RADIUS.
```

Nếu P/K/vi lượng/EC lệch phải:

```text
- Nếu project hỗ trợ transform, cân nhắc log1p.
- Nếu chưa hỗ trợ transform, chỉ ghi recommendation, không tự sửa sâu.
```

---

## 11. Validate trước khi chạy lại

Nếu có:

```text
scripts/agent_validate_decision.R
```

chạy validator trước khi tạo request iteration tiếp theo:

```powershell
Rscript scripts\agent_validate_decision.R --decision agent\decisions\ai_decision_<TARGET>_iter_001.json --request agent\requests\run_request_<TARGET>_iter_001.json --output agent\decisions\validated_decision_<TARGET>_iter_001.json
```

Nếu validator từ chối, dừng và báo rõ lý do.

Nếu validator chấp nhận, tạo:

```text
agent/requests/run_request_<TARGET>_iter_002.json
```

rồi chạy iteration 2.

---

## 12. Chạy tối đa 3 iteration

Lặp lại:

```text
Run
→ Read result
→ Evaluate
→ Decide
→ Validate
→ Rerun if needed
```

Dừng nếu:

```text
1. ACCEPT.
2. Đạt MAX_ITERATIONS = 3.
3. Validator từ chối.
4. MANUAL_REVIEW.
5. REJECT.
6. Hai lần rerun liên tiếp không cải thiện RMSE ít nhất 3-5%.
7. RMSE tốt hơn nhưng variogram xấu hơn rõ.
8. R²_pred vẫn âm.
9. Auto-neighbor không tìm được candidate hợp lệ.
```

Không chạy vô hạn.

---

## 13. So sánh iteration

Nếu có script:

```text
scripts/agent_compare_runs.R
```

Chạy sau khi có ít nhất 2 iteration hoặc sau khi dừng:

```powershell
Rscript scripts\agent_compare_runs.R --results agent\responses --output agent\history\run_comparison_<TARGET>.json
```

Nếu chỉ muốn so sánh một nhóm history cụ thể:

```powershell
Rscript scripts\agent_compare_runs.R --results agent\history\<RUN_ID> --include_output false --output agent\history\<RUN_ID>\run_comparison.json
```

Không dùng cú pháp `--target` hoặc `--history` trừ khi script hiện tại thật sự hỗ trợ.

Khi so sánh, không chọn chỉ theo RMSE. So sánh:

```text
RMSE
MAE
ME
R²_pred
RK improvement
nugget/sill
range
range_hit_max
selected_nmax_neighbors
selected_search_radius
warnings
class_accuracy nếu có
uncertainty nếu có
```

---

## 14. Xuất final decision

Tạo hoặc cập nhật:

```text
agent/responses/final_decision_<TARGET>.json
```

Nội dung:

```json
{
  "target_field": "<TARGET>",
  "selected_run_id": "...",
  "decision": "FINAL_ACCEPT | MANUAL_REVIEW | REJECT",
  "reason": "...",
  "why_not_lowest_rmse": "...",
  "final_notes": "...",
  "human_review_required": false,
  "selected_outputs": {
    "html_report": "...",
    "evaluation_json": "...",
    "rk_map": "...",
    "uncertainty_map": "...",
    "cv_results": "...",
    "model_comparison": "...",
    "neighbor_tuning": "...",
    "interactive_variogram": "...",
    "rk_report": "..."
  }
}
```

Nếu kết quả RMSE thấp nhất không được chọn, giải thích rõ vì sao.

---

## 15. Báo cáo cuối cho người dùng

Sau khi hoàn tất, trả lời bằng tiếng Việt có dấu, gồm:

```text
1. Đã chạy target nào.
2. Đã chạy bao nhiêu iteration.
3. Kết quả từng iteration:
   - RMSE
   - MAE
   - ME
   - R²_pred
   - model variogram
   - range
   - nugget/sill
   - selected_nmax_neighbors
   - selected_search_radius
   - cảnh báo chính
4. Iteration nào được chọn.
5. Lý do chọn.
6. Nếu không chọn RMSE thấp nhất, giải thích.
7. Output nằm ở đâu.
8. Có cần chuyên gia xem thủ công không.
9. Những giới hạn còn lại.
```

Không trả lời chung chung. Phải nêu file output cụ thể.

---

## 16. Nếu workflow lỗi

Nếu có lỗi, không tự đoán. Báo rõ:

```text
- Lệnh đã chạy.
- Lỗi nhận được.
- File/log liên quan.
- Nguyên nhân có khả năng.
- Cách khắc phục đề xuất.
```

Nếu lỗi do thiếu package, ghi lệnh cài.

Nếu lỗi do thiếu input, ghi chính xác file nào thiếu.

Nếu lỗi do agent workflow chưa sẵn sàng, ghi rõ cần chạy prompt nâng cấp trước.

---

## 17. Không được làm

Không được:

```text
- Xóa dữ liệu gốc.
- Sửa input CSV/shapefile/raster gốc.
- Tự ý thay CRS.
- Tự ý đổi tên cột.
- Tắt cross-validation để kết quả trông tốt hơn.
- Chọn mô hình chỉ vì RMSE thấp nhất.
- Chạy quá 3 iteration nếu không có lý do rõ.
- Tạo uncertainty giả.
- Hard-code đường dẫn máy cá nhân.
- Bỏ qua cảnh báo range/nugget/sill.
- Bỏ qua bảng neighbor_tuning khi AUTO_NEIGHBORS bật.
```

---

## 18. Encoding và report tiếng Việt

Report mới dùng tiếng Việt có dấu và UTF-8.

Nếu PowerShell hiển thị tiếng Việt bị lỗi mã hóa, không kết luận file hỏng ngay. Hãy mở HTML bằng trình duyệt hoặc đọc file với UTF-8.

Report chính nên mở:

```text
output/agent_runs/<run_id>/06_report/index_<target>.html
```

---

## 19. Mục tiêu cuối cùng

Kết quả cuối cùng phải giúp người dùng biết:

```text
Bản đồ RK này có đáng tin không?
Dựa trên thông số nào?
Auto-neighbor đã chọn neighborhood nào?
Nếu chưa tốt thì cần chỉnh gì?
Nếu đã tốt thì output cuối nằm ở đâu?
```