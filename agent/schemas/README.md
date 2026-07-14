# Agent JSON Schemas

This project uses lightweight schema validation in `scripts/agent_validate_decision.R` instead of a full JSON Schema dependency.

Important rules:

- `decision` must be one of `ACCEPT`, `RERUN`, `MANUAL_REVIEW`, `REJECT`.
- `confidence` must be one of `low`, `medium`, `high`.
- `next_parameters` may contain only whitelisted parameters from `scripts/agent_utils.R`.
- Protected settings such as `POINT_FILE`, `RASTER_DIR`, `UTM_EPSG`, `EXPORT_EPSG`, coordinate columns and source scripts require human review.
- Cross-validation must not be disabled in agent workflow.

Run result separates:

- `messages`: normal scientific context; never count as warnings.
- `warnings`: risks that may support rerun/manual review.
- `hard_failures`: acceptance blockers.

`cross_validation.strict_outer_cv` must be true for `ACCEPT`. The agent must also inspect `cross_validation.stability`, `variogram.singular`, `extrapolation`, `clipping`, and `uncertainty.calibrated`. Residual-only uncertainty must not influence the quality score.

`prediction_method` records the actual final predictor. When it is `regression_only_pure_nugget_fallback`, `uncertainty.available` must be false and the run cannot be described as successful residual kriging.
