"""Machine-readable scientific identity and covariate provenance for workflow 1."""

METHOD_ID = "clhs_like_spatially_constrained_soil_stratified_lhs"
METHOD_FAMILY = "spatially_constrained_soil_stratified_lhs"
METHOD_LABEL = (
    "cLHS-like: spatially constrained, soil-stratified Latin-hypercube "
    "targets in PCA space"
)
METHOD_METADATA = {
    "method_id": METHOD_ID,
    "method_family": METHOD_FAMILY,
    "method_label": METHOD_LABEL,
    "is_clhs_like": True,
    "is_original_clhs_optimizer": False,
    "selection_objective": (
        "Nearest feasible candidate to Latin-hypercube targets within each soil "
        "stratum, followed by spatial infill and short-lag augmentation."
    ),
    "scientific_scope": (
        "This implementation does not optimize the conditioned Latin hypercube "
        "objective of a dedicated cLHS optimizer."
    ),
    "compatibility_note": (
        "The sample_cLHS_* filenames are retained only for backward compatibility."
    ),
}


def covariate_provenance(project_id, crs, computational_grid_m, start_date, end_date):
    """Return provenance matching the image stack implemented by the downloader."""
    grid_note = (
        "The computational grid is used for alignment, extraction and export. It "
        "does not increase the native/effective spatial detail of a covariate."
    )
    return {
        "schema_version": "1.0.0",
        "project_id": project_id,
        "output_grid": {
            "crs": crs,
            "computational_grid_m": float(computational_grid_m),
            "continuous_resampling": "bilinear",
            "interpretation": grid_note,
        },
        "temporal_window": {
            "start_date_inclusive": str(start_date),
            "end_date_exclusive": str(end_date),
        },
        "covariates": {
            "NDVI": {
                "asset_ids": [
                    "COPERNICUS/S2_SR_HARMONIZED",
                    "GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED",
                ],
                "native_or_nominal_scale_m": 10.0,
                "effective_input_scale_m": 10.0,
                "temporal_aggregation": "median of cloud-masked scenes",
                "processing": (
                    "Cloud Score+ cs_cdf >= 0.60; surface reflectance divided by "
                    "10000; normalizedDifference(B8, B4)."
                ),
                "resampling_to_computational_grid": "bilinear",
                "spatial_interpretation": grid_note,
            },
            "DEM": {
                "asset_ids": ["USGS/SRTMGL1_003"],
                "native_or_nominal_scale_m": 30.0,
                "effective_input_scale_m": 30.0,
                "temporal_aggregation": "static elevation asset",
                "processing": "SRTM elevation band.",
                "resampling_to_computational_grid": "bilinear",
                "spatial_interpretation": grid_note,
            },
            "Slope": {
                "asset_ids": ["USGS/SRTMGL1_003"],
                "native_or_nominal_scale_m": 30.0,
                "effective_input_scale_m": 30.0,
                "temporal_aggregation": "static terrain derivative",
                "processing": "ee.Terrain.slope derived from SRTM DEM.",
                "resampling_to_computational_grid": "bilinear",
                "spatial_interpretation": grid_note,
            },
            "TWI": {
                "asset_ids": ["USGS/SRTMGL1_003", "MERIT/Hydro/v1_0_1"],
                "native_or_nominal_scale_m": {
                    "SRTM_slope": 30.0,
                    "MERIT_Hydro_upg": 92.77,
                },
                "effective_input_scale_m": 92.77,
                "temporal_aggregation": "static compound terrain/hydrology derivative",
                "processing": (
                    "log((MERIT upg * pixelArea) / tan(max(SRTM slope radians, "
                    "0.001))) as implemented by the project."
                ),
                "resampling_to_computational_grid": "bilinear",
                "spatial_interpretation": grid_note,
            },
            "CHIRPS": {
                "asset_ids": ["UCSB-CHG/CHIRPS/DAILY"],
                "native_or_nominal_scale_m": 5566.0,
                "effective_input_scale_m": 5566.0,
                "temporal_aggregation": "sum of daily precipitation in the date window",
                "processing": "Daily CHIRPS precipitation summed in Earth Engine.",
                "resampling_to_computational_grid": "bilinear",
                "spatial_interpretation": grid_note,
            },
        },
        "interpretation_warning": (
            "A 10 m output cell is not evidence of 10 m source detail for DEM, "
            "Slope, TWI or CHIRPS."
        ),
    }
