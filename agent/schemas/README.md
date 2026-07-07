# Agent JSON Schemas

This project uses lightweight schema validation in `scripts/agent_validate_decision.R` instead of a full JSON Schema dependency.

Important rules:

- `decision` must be one of `ACCEPT`, `RERUN`, `MANUAL_REVIEW`, `REJECT`.
- `confidence` must be one of `low`, `medium`, `high`.
- `next_parameters` may contain only whitelisted parameters from `scripts/agent_utils.R`.
- Protected settings such as `POINT_FILE`, `RASTER_DIR`, `UTM_EPSG`, `EXPORT_EPSG`, coordinate columns and source scripts require human review.
- Cross-validation must not be disabled in agent workflow.