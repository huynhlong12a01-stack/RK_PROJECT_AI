# Runtime-only wrapper used by run_sensitivity_workflow.ps1.
# It sources an existing PC_ONLY or PC_PLUS_SOIL configuration and replaces
# only the point file/output root for a declared sensitivity scenario.

base_config <- Sys.getenv("RK_SENSITIVITY_BASE_CONFIG", unset = "")
scenario_point_file <- Sys.getenv("RK_SENSITIVITY_POINT_FILE", unset = "")
scenario_output_root <- Sys.getenv("RK_SENSITIVITY_OUTPUT_ROOT", unset = "")
if (!nzchar(base_config) || !file.exists(base_config)) {
  stop("RK_SENSITIVITY_BASE_CONFIG is missing or invalid.")
}
if (!nzchar(scenario_point_file) || !file.exists(scenario_point_file)) {
  stop("RK_SENSITIVITY_POINT_FILE is missing or invalid.")
}
if (!nzchar(scenario_output_root)) {
  stop("RK_SENSITIVITY_OUTPUT_ROOT is required.")
}

source(base_config)
POINT_FILE <- scenario_point_file
OUTPUT_ROOT <- scenario_output_root
RUN_NAME_OVERRIDE <- Sys.getenv("RK_RUN_NAME", unset = "")
ASK_OUTPUT_FOLDER <- FALSE
