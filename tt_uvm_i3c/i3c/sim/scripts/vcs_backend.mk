SHELL := /bin/bash
.DEFAULT_GOAL := help

RUNNER_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)

SIMULATOR ?= $(or $(DV_SIMULATOR),vcs)
TOP ?= $(or $(DV_TOP),tb_top)
FILELIST ?= $(or $(DV_FILELIST),filelist.f)
TEST_LIST_FILE ?= $(or $(DV_TESTPLAN),testplan.dv)
OUT_DIR ?= $(RUNNER_ROOT)/out
BUILD_DIR ?= $(OUT_DIR)/build
LOG_DIR ?= $(OUT_DIR)/logs
COV_DIR ?= $(OUT_DIR)/coverage
DUMP_DIR ?= $(OUT_DIR)/dumps
STATE_DIR ?= $(OUT_DIR)/state
RUNS_DIR ?= $(OUT_DIR)/runs
SIMV ?= $(BUILD_DIR)/simv
COMPILE_WORK_DIR ?= $(RUNNER_ROOT)
RUN_WORK_DIR ?= $(BUILD_DIR)

VCS ?= vcs
URG ?= urg
TEST ?= $(or $(DV_TEST),basic_test)
SEED ?= $(or $(DV_SEED),1)
ATTEMPT ?= $(or $(DV_ATTEMPT),1)
COV ?= 0
DUMP_FORMAT ?= none
UVM_VERBOSITY ?= UVM_LOW
CONFIG_DB_TRACE ?= 0
PLUSARGS ?=
EXTRA_COMPILE_OPTS ?=
EXTRA_RUN_OPTS ?=
COMPILE_JOBS ?= 4
FSDB_PLI_DIR ?= $(DV_FSDB_PLI_DIR)
DV_FSDB_DEFINE ?= DV_FSDB_ENABLE
DV_FSDB_COMPILE_STYLE ?= integrated
DV_VCD_DEFINE ?= DV_VCD_ENABLE
DV_VPD_DEFINE ?= DV_VPD_ENABLE
DV_DUMP_RUN_STYLE ?= generic

UVM_MODE ?= builtin
UVM_HOME ?=
UVM_USE_DPI ?= 1
UVM_CUSTOM_OPTS ?=
UVM_CHAR_COMPAT_OPT ?= -Xcheck_p1800_2009=char
UVM_SRC_DIR = $(if $(wildcard $(UVM_HOME)/uvm_pkg.sv),$(UVM_HOME),$(UVM_HOME)/src)
UVM_DPI_DIR = $(UVM_SRC_DIR)/dpi

ifeq ($(UVM_MODE),external)
    UVM_COMPILE_OPTS := +incdir+$(UVM_SRC_DIR) $(UVM_CHAR_COMPAT_OPT)
    UVM_SRC_FILES := $(UVM_SRC_DIR)/uvm_pkg.sv
    ifeq ($(UVM_USE_DPI),1)
        UVM_DPI_OPTS := -CFLAGS "-DVCS -I$(UVM_DPI_DIR)"
        UVM_DPI_SRC_FILES := $(UVM_DPI_DIR)/uvm_dpi.cc
    else
        UVM_DPI_OPTS := +define+UVM_NO_DPI
        UVM_DPI_SRC_FILES :=
    endif
else ifeq ($(UVM_MODE),custom)
    UVM_COMPILE_OPTS := $(UVM_CUSTOM_OPTS)
    UVM_SRC_FILES :=
    UVM_DPI_OPTS :=
    UVM_DPI_SRC_FILES :=
else
    UVM_COMPILE_OPTS := -ntb_opts uvm
    UVM_SRC_FILES :=
    UVM_DPI_OPTS :=
    UVM_DPI_SRC_FILES :=
endif

COMPILE_COV_DIR ?= $(COV_DIR)/compile.vdb
COMPILE_COV_NAME ?= compile_design
COV_HIER_FILE ?= $(RUNNER_ROOT)/sim/scripts/cov_setup.cfg
COV_GROUP_DB_EDIT_FILE ?= $(RUNNER_ROOT)/sim/scripts/ibi_group_db_edit.cfg
# IBI closure collects only SVA assertion/cover-property and functional
# covergroup data. RTL code metrics are intentionally disabled. Hierarchy
# filtering is compile-time only; simv receives the matching assertion metric
# without -cm_hier.
COMPILE_COV_OPTS ?= -cm assert -cm_assert_hier $(COV_HIER_FILE) -cm_dir $(COMPILE_COV_DIR) -cm_name $(COMPILE_COV_NAME)
RUN_COV_OPTS ?= -cm assert -cm_dir $(COV_DIR)/$(TEST)_$(SEED)_attempt_$(ATTEMPT).vdb -cm_name $(TEST)_$(SEED)_A$(ATTEMPT)
DUMP_FILE ?= $(DUMP_DIR)/$(TEST)_seed_$(SEED)_attempt_$(ATTEMPT).$(DUMP_FORMAT)
DUMP_RUN_OPTS ?= $(if $(filter legacy_fsdb,$(DV_DUMP_RUN_STYLE)),$(if $(filter fsdb,$(DUMP_FORMAT)),+DUMP +fsdb+autoflush +FSDB_FILE=$(DUMP_FILE),),$(if $(filter fsdb,$(DUMP_FORMAT)),+fsdb+autoflush,) +DV_DUMP_FORMAT=$(DUMP_FORMAT) +DV_DUMP_DIR=$(DUMP_DIR) +DV_DUMP_FILE=$(DUMP_FILE))
TRACE_RUN_OPTS ?= $(if $(filter 1,$(CONFIG_DB_TRACE)),+UVM_CONFIG_DB_TRACE,)
ASSERT_RUN_OPTS ?= -assert quiet
FSDB_INTEGRATION_OPTS = $(if $(filter legacy,$(DV_FSDB_COMPILE_STYLE)),-P $(FSDB_PLI_DIR)/novas.tab $(FSDB_PLI_DIR)/pli.a,-kdb -debug_access+all)
FSDB_COMPILE_OPTS ?= $(if $(filter fsdb,$(DUMP_FORMAT)),+define+$(DV_FSDB_DEFINE) $(FSDB_INTEGRATION_OPTS),)
VCD_COMPILE_OPTS ?= $(if $(filter vcd,$(DUMP_FORMAT)),+define+$(DV_VCD_DEFINE),)
VPD_COMPILE_OPTS ?= $(if $(filter vpd,$(DUMP_FORMAT)),+define+$(DV_VPD_DEFINE) -debug_access+all,)
VCS_PARALLEL_COMPILE_OPTS = $(if $(filter 1,$(COMPILE_JOBS)),,-j$(COMPILE_JOBS))

COMPILE_CMD ?= $(VCS) -full64 $(VCS_PARALLEL_COMPILE_OPTS) -sverilog $(UVM_COMPILE_OPTS) $(UVM_DPI_OPTS) $(UVM_SRC_FILES) $(UVM_DPI_SRC_FILES) -f "$(FILELIST)" -top "$(TOP)" -Mdir="$(BUILD_DIR)/csrc" -o "$(SIMV)" $(if $(filter 1,$(COV)),$(COMPILE_COV_OPTS),) $(VCD_COMPILE_OPTS) $(FSDB_COMPILE_OPTS) $(VPD_COMPILE_OPTS) $(EXTRA_COMPILE_OPTS)
RUN_CMD ?= "$(SIMV)" +UVM_TESTNAME="$(TEST)" +UVM_VERBOSITY=$(UVM_VERBOSITY) +ntb_random_seed="$(SEED)" $(if $(filter 1,$(COV)),$(RUN_COV_OPTS),) $(DUMP_RUN_OPTS) $(TRACE_RUN_OPTS) $(ASSERT_RUN_OPTS) $(PLUSARGS) $(EXTRA_RUN_OPTS)
COV_INPUTS ?= $(COV_DIR)/*.vdb
COV_WAIVER_FILE ?=
COV_WAIVER_OPTS = $(if $(strip $(COV_WAIVER_FILE)),-elfile "$(COV_WAIVER_FILE)",)
COV_REPORT_HIER_OPTS ?= -hier "$(COV_HIER_FILE)"
COV_GROUP_DB_EDIT_OPTS ?= -group db_edit_file "$(COV_GROUP_DB_EDIT_FILE)"
MERGE_COV_CMD ?= $(URG) -dir $(COV_INPUTS) -dbname "$(COV_DIR)/merged" -report "$(COV_DIR)/report" $(COV_REPORT_HIER_OPTS) $(COV_GROUP_DB_EDIT_OPTS) $(COV_WAIVER_OPTS)
COVERAGE_VALUE_CMD ?=
COVERAGE_METRIC ?= score

.PHONY: help comp run merge-cov coverage-value clean print-config print-test-list

help:
	@./run.sh help

comp:
	@mkdir -p "$(BUILD_DIR)" "$(LOG_DIR)" "$(COV_DIR)" "$(STATE_DIR)" "$(RUNS_DIR)"
	@if [[ "$(UVM_MODE)" == "external" && ! -f "$(UVM_SRC_DIR)/uvm_pkg.sv" ]]; then \
		echo "[ERROR] External UVM package not found: $(UVM_SRC_DIR)/uvm_pkg.sv" >&2; exit 2; \
	fi
	@if [[ "$(DUMP_FORMAT)" == "fsdb" && "$(DV_FSDB_COMPILE_STYLE)" != "integrated" && "$(DV_FSDB_COMPILE_STYLE)" != "legacy" ]]; then \
		echo "[ERROR] DV_FSDB_COMPILE_STYLE must be integrated or legacy" >&2; exit 2; \
	fi
	@if [[ "$(DUMP_FORMAT)" == "fsdb" && "$(DV_FSDB_COMPILE_STYLE)" == "integrated" && ( -z "$(VERDI_HOME)" || ! -d "$(VERDI_HOME)" ) && "$(DRY_RUN)" != "1" ]]; then \
		echo "[ERROR] Integrated FSDB requires a valid VERDI_HOME" >&2; exit 2; \
	fi
	@if [[ "$(DUMP_FORMAT)" == "fsdb" && "$(DV_FSDB_COMPILE_STYLE)" == "legacy" && ( ! -f "$(FSDB_PLI_DIR)/novas.tab" || ! -f "$(FSDB_PLI_DIR)/pli.a" ) && "$(DRY_RUN)" != "1" ]]; then \
		echo "[ERROR] Legacy FSDB requires DV_FSDB_PLI_DIR with novas.tab and pli.a" >&2; exit 2; \
	fi
	@if [[ "$(DRY_RUN)" == "1" ]]; then \
		printf '[DRY-RUN] %s\n' '$(COMPILE_CMD)'; \
	else \
		cd "$(COMPILE_WORK_DIR)" && eval '$(COMPILE_CMD)'; \
	fi

run:
	@mkdir -p "$(BUILD_DIR)" "$(LOG_DIR)" "$(COV_DIR)" "$(DUMP_DIR)" "$(STATE_DIR)" "$(RUNS_DIR)"
	@if [[ "$(DRY_RUN)" == "1" ]]; then \
		printf '[DRY-RUN] %s\n' '$(RUN_CMD)'; \
	else \
		cd "$(RUN_WORK_DIR)" && eval '$(RUN_CMD)'; \
	fi

merge-cov:
	@mkdir -p "$(COV_DIR)"
	@if [[ "$(DRY_RUN)" == "1" ]]; then \
		printf '[DRY-RUN] %s\n' '$(MERGE_COV_CMD)'; \
	elif [[ -z "$(strip $(COV_INPUTS))" ]]; then \
		echo "[ERROR] COV_INPUTS is empty" >&2; exit 2; \
	else \
		eval '$(MERGE_COV_CMD)'; \
	fi

coverage-value:
	@if [[ -z "$(strip $(COVERAGE_VALUE_CMD))" ]]; then \
		echo "[ERROR] COVERAGE_VALUE_CMD is not configured" >&2; exit 2; \
	else \
		eval '$(COVERAGE_VALUE_CMD)'; \
	fi

print-config:
	@printf '%-22s %s\n' \
		PROJECT "$(DV_PROJECT_NAME)" SIMULATOR "$(SIMULATOR)" TOP "$(TOP)" FILELIST "$(FILELIST)" \
		UVM_MODE "$(UVM_MODE)" UVM_HOME "$(UVM_HOME)" \
		TEST_LIST_FILE "$(TEST_LIST_FILE)" BUILD_DIR "$(BUILD_DIR)" \
		OUT_DIR "$(OUT_DIR)" LOG_DIR "$(LOG_DIR)" COV_DIR "$(COV_DIR)" \
		DUMP_DIR "$(DUMP_DIR)" STATE_DIR "$(STATE_DIR)" RUNS_DIR "$(RUNS_DIR)"

print-test-list:
	@printf '%s\n' "$(TEST_LIST_FILE)"

clean:
	@echo "[ERROR] Use './run.sh clean <explicit-action>'; Makefile clean is intentionally disabled" >&2
	@exit 2
