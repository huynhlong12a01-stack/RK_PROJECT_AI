# Danh mục tri thức

## Bắt đầu nhanh

| Câu hỏi | Tài liệu nên đọc | Evidence card chính |
|---|---|---|
| Nếu chưa có ROI mía thì làm gì? | guides/00_GIAI_DOAN_VUNG_MIA_TU_VE_TINH.md | sugarcane_temporal_s1_s2_mapping_001 |
| ROI ứng viên đã đủ để rải mẫu chưa? | guides/00_GIAI_DOAN_VUNG_MIA_TU_VE_TINH.md | crop_map_candidate_review_accuracy_001 |
| FULL hay REDUCED? | guides/01_THIET_KE_MAU_VA_DIEU_CHINH_THUC_DIA.md | full_reduced_tradeoff_001 |
| Có thật là cLHS? | guides/01_THIET_KE_MAU_VA_DIEU_CHINH_THUC_DIA.md | true_clhs_definition_001 |
| Xử lý 22 điểm ngoài ROI? | guides/01_THIET_KE_MAU_VA_DIEU_CHINH_THUC_DIA.md | outside_roi_aoa_relocation_001 |
| Covariates có thật là 10 m? | guides/02_COVARIATES_PCA_SOIL_TYPE.md | covariate_native_resolution_001 |
| PCA có giảm chiều không? | guides/02_COVARIATES_PCA_SOIL_TYPE.md | pca_full_rank_rotation_001 |
| Soil Type/Other dùng thế nào? | guides/02_COVARIATES_PCA_SOIL_TYPE.md | soil_type_categorical_support_001 |
| Có được gộp kết quả lab? | guides/03_PHUONG_PHAP_LAB_VA_Y_NGHIA_CHI_TIEU.md | lab_method_unit_harmonization_001 |
| Chọn PC_ONLY hay PC_PLUS_SOIL? | guides/04_REGRESSION_KRIGING_VA_KIEM_DINH.md | rk_baseline_comparison_001 |
| Spatial CV có phải validation độc lập? | guides/04_REGRESSION_KRIGING_VA_KIEM_DINH.md | probability_validation_vs_spatial_cv_001 |
| RK_STD có phải uncertainty tổng? | guides/05_UNCERTAINTY_AOA_VA_DO_PHAN_GIAI.md | residual_sd_not_total_uncertainty_001 |
| Có thể tạo liều phân ngay không? | guides/03_PHUONG_PHAP_LAB_VA_Y_NGHIA_CHI_TIEU.md | nutrient_map_not_fertilizer_rate_001 |

## Nhóm nguồn chính thống

### Giải đoán vùng mía

jiang_etal_2019_sugarcane_s1_s2; wang_etal_2020_sugarcane_phenology; remote_sensing_sugarcane_review_2021; olofsson_etal_2014_accuracy_area; gee_copernicus_s1_grd_catalog; google_s2_sr_harmonized_catalog; google_cloud_score_plus_catalog.

### Thiết kế mẫu

minasny_mcbratney_2006_clhs; brus_2019_sampling_dsm; brus_kempen_heuvelink_2011_validation; fao_2022_gsnmap.

### Covariates và hạ tầng

gorelick_2017_gee; drusch_2012_sentinel2; google_s2_sr_harmonized_catalog; google_cloud_score_plus_catalog; funk_2015_chirps; google_chirps_daily_catalog; farr_2007_srtm; google_srtmgl1_catalog; yamazaki_2019_merit_hydro; google_merit_hydro_catalog; beven_kirkby_1979_topmodel; jolliffe_cadima_2016_pca.

### DSM, RK và validation

mcbratney_2003_dsm; hengl_2007_about_rk; roberts_2017_spatial_cv; wadoux_2021_spatial_cv_map_accuracy; meyer_pebesma_2021_aoa; schmidinger_heuvelink_2023_uncertainty; globalsoilmap_2015_specs; poggio_2021_soilgrids2.

### Lab và dinh dưỡng

fao_glosolan_sops; usda_2022_kssl_methods; batjes_2025_wosis_methods; fao_2006_plant_nutrition_food_security; fao_2022_gsnmap; hengl_2017_africa_soil_nutrients.

Danh mục đầy đủ, DOI, URL, license và phạm vi nằm trong `metadata/sources.csv`.
