# RAG Source Collection Report

Ngay tao: 2026-07-07

## Tom tat

Da tao thu vien tri thuc ban dau cho Regression Kriging / Digital Soil Mapping.

- Tong so nguon trong `sources.csv`: 26
- Nguon core: 18
- Nguon supporting: 8
- Evidence cards: 10
- Vector/embedding index: chua tao
- PDF/raw library: chua tai va khong commit vao Git

## Nhom chu de da phu

```text
- Nen tang dia thong ke: variogram, kriging, stationarity, uncertainty.
- Regression Kriging: trend + residual variogram + kriged residual.
- Digital Soil Mapping: SCORPAN/covariates, DSM history, SoilGrids.
- Spatial cross-validation: random CV risk, block/spatial CV.
- Metrics: RMSE, MAE, ME, R2_pred, NSE, RPD/RPIQ.
- Soil nutrients: nguon guideline ho tro dien giai nong hoc.
```

## Nguon can kiem chung them

`brus_2019_sampling_dsm` dang de DOI trong metadata la trong vi can kiem chung DOI truoc khi nang len `core`.

## Evidence cards da tao

```text
- rk_residual_workflow_001
- rk_baseline_comparison_001
- spatial_cv_random_bias_001
- cv_refit_leakage_001
- variogram_range_cutoff_001
- nugget_sill_weak_structure_001
- uncertainty_kriging_variance_limits_001
- dsm_covariates_validation_001
- metrics_multi_metric_assessment_001
- soil_nutrient_class_accuracy_001
```

## Gioi han hien tai

```text
- Day la seed library, khong phai toan bo tai lieu khoa hoc cua linh vuc.
- Chua tai PDF va chua tao embedding index.
- Chua co retrieval engine that.
- Chua co rag_assessment generator tu dong tu run_result.json.
- Cac threshold khoa hoc van phai ap dung theo ngu canh du lieu, vung nghien cuu va thiet ke lay mau.
```

## Buoc tiep theo de nang cap

```text
1. Kiem chung DOI/URL cho tat ca nguon supporting.
2. Them source cho tung chi tieu dat theo bo nguong dia phuong/cay trong neu co.
3. Tao summaries rieng cho tung source, khong copy full text co ban quyen.
4. Tao keyword retrieval truoc embedding.
5. Tao script sinh rag_assessment_<run_id>.json tu run_result.json + evidence cards.
6. Sau khi co cong cu embedding duoc phep, moi tao vector index trong knowledge/index/vector_store/.
```