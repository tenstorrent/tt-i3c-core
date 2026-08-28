#######################################################################
# Company      : VNCHIP
# Project      : LPIOC
# IP           : smc_peripherals
# File         : Makefile
# Module       : N/A
#
# Description  : Unified Makefile for Synopsys VCS UVM Environment.
#                Supports the starter SMC peripherals UVM skeleton.
# Clock/Reset  : N/A
# Interfaces   : N/A
# Dependencies : GNU Make, Synopsys VCS, Verdi
# Parameters   : N/A
# Integration  : Execute from the smc_peripherals/sim directory.
# Notes        : Optimized for compilation speed and UVM package resolution.
# Revision     :
# Authors      : Huynh Pham Anh Duy, Thai Hai Dang
# Create Date  : 2026-03-02
# Last Modified: 2026-03-02
#######################################################################

# ==============================================================================
# 1. Infrastructure & Job Control
# ==============================================================================
CORE        := 4
RUN_CORE    ?= 1
# Architect Note: keep compilation multi-core for elaboration speed, but keep
# each simulation run single-core by default so large regression parallelism
# does not multiply farm core requests unexpectedly.
SRUN             ?= srun
COMPILE_SRUN_CMD := $(SRUN) --cpus-per-task=$(CORE)
RUN_SRUN_CMD     := $(SRUN) --cpus-per-task=$(RUN_CORE)
GUI_SRUN_CMD     := $(SRUN) --cpus-per-task=1 --X11

VCS         := vcs
SIMV        := ./simv
URG         := urg
VERDI       := verdi

# Resolve Verdi from the active tool environment. Do not pin an old Verdi
# release here: its PLI must match the selected 64-bit VCS installation.
VERDI_AUTO_HOME := $(shell bin="$$(command -v $(VERDI) 2>/dev/null)"; \
	if [ -n "$$bin" ]; then \
		bin="$$(readlink -f "$$bin" 2>/dev/null || printf '%s' "$$bin")"; \
		dirname "$$(dirname "$$bin")"; \
	fi)
VERDI_HOME := $(strip $(VERDI_HOME))
ifeq ($(VERDI_HOME),)
    ifneq ($(strip $(NOVAS_HOME)),)
        VERDI_HOME := $(strip $(NOVAS_HOME))
    else
        VERDI_HOME := $(strip $(VERDI_AUTO_HOME))
    endif
endif
NOVAS_HOME := $(VERDI_HOME)
FSDB_PLI_DIR ?= $(VERDI_HOME)/share/PLI/VCS/LINUX64

# ==============================================================================
# UVM Library Selection
# ==============================================================================
# USE_EXT_UVM=0: use the simulator built-in UVM library through VCS -ntb_opts uvm.
# USE_EXT_UVM=1: use an external Accellera UVM library from EXT_UVM_HOME.
# EXT_UVM_HOME can point to the UVM kit root or directly to its src directory.
#
# Example external UVM path:
#   EXT_UVM_HOME=/path/to/uvm-core-2020.3.1
#
# Default is 1: use the bundled Accellera UVM 2020.3.1 library.
# Set USE_EXT_UVM=0 only when intentionally using the simulator-provided UVM.
USE_EXT_UVM     ?= 1
EXT_UVM_HOME    ?= $(ROOT_DIR)/../third_party/uvm-core-2020.3.1
EXT_UVM_USE_DPI ?= 1

# VCS option required for UVM 1800.2-2020.3.1.
# This allows "char" to be used as an identifier instead of a SystemVerilog keyword.
VCS_CHAR_AS_IDENTIFIER_OPT := -Xcheck_p1800_2009=char

EXT_UVM_SRC_DIR = $(if $(wildcard $(EXT_UVM_HOME)/uvm_pkg.sv),$(EXT_UVM_HOME),$(EXT_UVM_HOME)/src)
EXT_UVM_DPI_DIR = $(EXT_UVM_SRC_DIR)/dpi

ifeq ($(USE_EXT_UVM),1)
    UVM_MODE             := EXTERNAL
    UVM_VCS_BUILTIN_OPT  :=
    UVM_COMPILE_OPTS     := +incdir+$(EXT_UVM_SRC_DIR) $(VCS_CHAR_AS_IDENTIFIER_OPT)
    UVM_SRC_FILES        := $(EXT_UVM_SRC_DIR)/uvm_pkg.sv

    ifeq ($(EXT_UVM_USE_DPI),1)
        UVM_DPI_OPTS      := -CFLAGS "-DVCS -I$(EXT_UVM_DPI_DIR)"
        UVM_DPI_SRC_FILES := $(EXT_UVM_DPI_DIR)/uvm_dpi.cc
    else
        UVM_DPI_OPTS      := +define+UVM_NO_DPI
        UVM_DPI_SRC_FILES :=
    endif
else
    UVM_MODE             := VCS_BUILTIN
    UVM_VCS_BUILTIN_OPT  := -ntb_opts uvm
    UVM_COMPILE_OPTS     :=
    UVM_SRC_FILES        :=
    UVM_DPI_OPTS         :=
    UVM_DPI_SRC_FILES    :=
endif

# Trace UVM config DB get/set operations.
CONN		?= 0
DUMP		?= 0
DUMP_EN		:=
FSDB_OPTS   :=
FSDB_COMPILE_OPTS :=
DO_CONN     :=

ifeq ($(CONN), 1)
    DO_CONN := +UVM_CONFIG_DB_TRACE
endif

# Run command
FSDB_FILE   ?= $(LOG_DIR)/$(TEST_NAME)_seed$(SEED).fsdb
ifeq ($(DUMP), 1)
    DUMP_EN = +DUMP
    FSDB_OPTS = +fsdb+autoflush +FSDB_FILE=$(FSDB_FILE_ABS)
    FSDB_COMPILE_OPTS = +define+SMC_FSDB_ENABLE \
                        -P $(FSDB_PLI_DIR)/novas.tab $(FSDB_PLI_DIR)/pli.a
endif
# ==============================================================================
# 2. Simulation Controls
# ==============================================================================
TEST_NAME   ?= smc_i3c_csr_smoke_test
SEED        ?= 1
VERB        ?= UVM_LOW

LOG_DIR     ?= logs
LOG         ?= $(LOG_DIR)/$(TEST_NAME)_seed$(SEED).log
UVM_REG_WIDTH ?= 128
EXTRA_RUN_OPTS ?=


# ==============================================================================
# 3. Generated paths, incdirs, and source lists
# ==============================================================================
SIM_MAKEFILE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
-include $(SIM_MAKEFILE_DIR)/mk/paths.mk
-include $(SIM_MAKEFILE_DIR)/mk/incdirs.mk
-include $(SIM_MAKEFILE_DIR)/mk/srcs.mk
-include $(SIM_MAKEFILE_DIR)/mk/i3c.mk

MK_DIR      ?= $(SIM_MAKEFILE_DIR)/mk
GEN_MK_OPTS ?= --mk
GEN_MK_SCRIPT := $(SIM_MAKEFILE_DIR)/scripts/gen_mk_files.sh
BUILD_DIR   ?= $(SIM_MAKEFILE_DIR)/out
ARTIFACT_ROOT ?= $(BUILD_DIR)
RUN_DIR     ?= $(BUILD_DIR)
WAVE_TOP    ?= tb_smc_peripherals_top
BUILD_DIR_ABS := $(abspath $(BUILD_DIR))
ARTIFACT_ROOT_ABS := $(abspath $(ARTIFACT_ROOT))
RUN_DIR_ABS := $(abspath $(RUN_DIR))
BUILD_RTL_FLIST_ABS := $(BUILD_DIR_ABS)/rtl_runtime.f
GEN_ROOT    := $(abspath $(SIM_MAKEFILE_DIR)/..)
LOG_DIR_ABS := $(ARTIFACT_ROOT_ABS)/$(LOG_DIR)
COMPILE_LOG_DIR ?= $(LOG_DIR)
COMPILE_LOG_DIR_ABS := $(ARTIFACT_ROOT_ABS)/$(COMPILE_LOG_DIR)
COMPILE_LOG_ABS := $(COMPILE_LOG_DIR_ABS)/compile.log
SIMV_ABS := $(BUILD_DIR_ABS)/simv
RUN_SIMV := ./simv
RUN_LOG_ABS := $(LOG_DIR_ABS)/$(TEST_NAME)_seed$(SEED).log
FSDB_FILE_ABS := $(LOG_DIR_ABS)/$(TEST_NAME)_seed$(SEED).fsdb
RTL_SRC_FILES := -f $(BUILD_RTL_FLIST_ABS)
SRC_FILES := \
    $(UVM_SRC_FILES) \
    $(TB_CORE_PKG_SRC_FILES) \
    $(VIP_IF_SRC_FILES) \
    $(I3C_RAL_SRC_FILES) \
    $(I3C_VIP_SRC_FILES) \
    $(ORDERED_PKG_SRC_FILES) \
    $(SVA_SRC_FILES) \
    $(TB_TOP_SRC_FILES) \
    $(RTL_SRC_FILES) \
    $(UVM_DPI_SRC_FILES)

WAVE_SRC_FILES := \
    $(TB_CORE_PKG_SRC_FILES) \
    $(VIP_IF_SRC_FILES) \
    $(I3C_VIP_SRC_FILES) \
    $(TB_TOP_SRC_FILES)


# ==============================================================================
# 4. Coverage Control
# ==============================================================================
COV              ?= 0
CM_COMPILE_FLAGS :=
CM_RUN_FLAGS     :=
CM_DIR           := $(LOG_DIR)/$(TEST_NAME)_seed$(SEED).vdb
CM_DIR_ABS       := $(ARTIFACT_ROOT_ABS)/$(CM_DIR)
CM_NAME          := $(TEST_NAME)_$(SEED)
COMPILE_CM_DIR   ?= $(CM_DIR)
COMPILE_CM_DIR_ABS := $(ARTIFACT_ROOT_ABS)/$(COMPILE_CM_DIR)
COMPILE_CM_NAME  ?= $(CM_NAME)
FCFG_NAME        := $(SCRIPTS_DIR)/cov_setup.cfg
ifeq ($(COV),1)
    # Keep hierarchy filtering at compile time only. Preserve the original
    # database naming/directory options during compile so VCS 2014 still
    # elaborates a full coverage database, but do not pass -cm_hier to simv.
    CM_COMPILE_FLAGS := -cm line+tgl+fsm+branch+cond -cm_hier $(FCFG_NAME) -cm_dir $(COMPILE_CM_DIR_ABS) -cm_name $(COMPILE_CM_NAME)
    CM_RUN_FLAGS     := -cm line+tgl+fsm+branch+cond -cm_dir $(CM_DIR_ABS) -cm_name $(CM_NAME)
endif

# ==============================================================================
# 5. VCS Compile Options (Elaboration)
# ==============================================================================
# ------------------------------------------------------------------------------
# Cosmetic warning suppression (benign, UVM-library-origin warnings).
# Default OFF so warnings stay visible while confirming the build is stable.
# Turn on once the compile is confirmed clean:   make comp WARN_SUPPRESS=1
# Add more tags as needed:  make comp WARN_SUPPRESS=1 WARN_SUPPRESS_TAGS="ENEIBSC FOO"
#   ENEIBSC : UVM 2020 reg seq (uvm_reg_mem_hdl_paths_seq.svh) does
#             $bits(<queue>.size()); VCS warns the fn is not evaluated. Harmless.
# ------------------------------------------------------------------------------
WARN_SUPPRESS      ?= 0
WARN_SUPPRESS_TAGS ?= ENEIBSC
ifeq ($(WARN_SUPPRESS),1)
    WARN_SUPPRESS_OPTS := $(addprefix -suppress=,$(WARN_SUPPRESS_TAGS))
else
    WARN_SUPPRESS_OPTS :=
endif

COMPILE_OPTS := -q \
                -lca \
                -full64 \
                -sverilog \
                $(WARN_SUPPRESS_OPTS) \
                $(UVM_VCS_BUILTIN_OPT) \
                $(UVM_COMPILE_OPTS) \
                $(UVM_DPI_OPTS) \
                -timescale=1ns/1ps \
                -debug_access+all \
                -error=noIOPCWM \
				+lint=TFIPC-L \
                +vcs+lic+wait \
				$(I3C_COMPILE_DEFINES) \
				$(INCDIRS) \
				$(I3C_RAL_INCDIRS) \
				$(I3C_VIP_INCDIRS) \
				$(CM_COMPILE_FLAGS) \
				$(FSDB_COMPILE_OPTS) \
                -l $(COMPILE_LOG_ABS) \
				+define+UVM_REG_DATA_WIDTH=$(UVM_REG_WIDTH)

# ==============================================================================
# 6. Simulation Run Options
# ==============================================================================
RUN_OPTS    := +UVM_TESTNAME=$(TEST_NAME) \
               +UVM_VERBOSITY=$(VERB) \
               $(DO_CONN) \
               +ntb_random_seed=$(SEED) \
                $(EXTRA_RUN_OPTS) \
                $(FSDB_OPTS) \
                $(CM_RUN_FLAGS) \
               -l $(RUN_LOG_ABS)\
               $(DUMP_EN)\
               -assert quiet

# ==============================================================================
# 7. Execution Targets
# ==============================================================================
.PHONY: all comp sim run clean help wave gen-mk reuse-check i3c-reuse-check \
        check-uvm-config check-dut-mode check-i3c-source check-vcs-version \
        check-fsdb-config

ifneq ($(strip $(VERDI_HOME)),)
export NOVAS_HOME := $(VERDI_HOME)
export VERDI_HOME
export PATH := $(VERDI_HOME)/bin:$(PATH)
export LD_LIBRARY_PATH := $(FSDB_PLI_DIR):$(LD_LIBRARY_PATH)
endif

all: comp run

comp: check-uvm-config check-dut-mode check-i3c-source check-vcs-version check-fsdb-config
	@mkdir -p $(BUILD_DIR_ABS) $(LOG_DIR_ABS) $(COMPILE_LOG_DIR_ABS) $(dir $(COMPILE_CM_DIR_ABS))
	@awk '{ \
		line=$$0; \
		if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$$/) { print line; next; } \
		if (line ~ /^-f[[:space:]]+\.\.\/\.\.\//) { sub(/\.\.\/\.\.\//, "$(ROOT_DIR)/", line); } \
		if (line ~ /^\.\.\/\.\.\//) { sub(/^\.\.\/\.\.\//, "$(ROOT_DIR)/", line); } \
		print line; \
	}' $(RTL_FLIST) > $(BUILD_RTL_FLIST_ABS)
	@pty_opt=""; \
	if [ -t 0 ] && [ -t 1 ]; then pty_opt="--pty"; fi; \
	cd $(BUILD_DIR_ABS) && $(COMPILE_SRUN_CMD) $$pty_opt $(VCS) $(COMPILE_OPTS) $(SRC_FILES)

check-fsdb-config:
ifeq ($(DUMP),1)
	@if [ -z "$(VERDI_HOME)" ]; then \
		echo "[ERROR] --dump requires VERDI_HOME or a verdi executable in PATH"; \
		exit 1; \
	fi
	@if [ ! -f "$(FSDB_PLI_DIR)/novas.tab" ] || [ ! -f "$(FSDB_PLI_DIR)/pli.a" ]; then \
		echo "[ERROR] FSDB PLI files were not found under: $(FSDB_PLI_DIR)"; \
		echo "[ERROR] Load a Verdi release compatible with the active 64-bit VCS, then retry"; \
		exit 1; \
	fi
	@echo "[PASS] FSDB PLI : $(FSDB_PLI_DIR)"
else
	@true
endif

run:
	@mkdir -p $(LOG_DIR_ABS) $(RUN_DIR_ABS)
	@build_dir_phys="$$(cd "$(BUILD_DIR_ABS)" && pwd -P)"; \
	run_dir_phys="$$(cd "$(RUN_DIR_ABS)" && pwd -P)"; \
	if [ ! -x "$$build_dir_phys/simv" ]; then \
		echo "[ERROR] simv executable not found: $$build_dir_phys/simv"; \
		echo "[ERROR] Run 'make comp' or './run.sh ...' compile flow before make run."; \
		exit 127; \
	fi; \
	if [ "$$run_dir_phys" != "$$build_dir_phys" ]; then \
		if command -v realpath >/dev/null 2>&1; then \
			simv_link="$$(realpath --relative-to="$$run_dir_phys" "$$build_dir_phys/simv" 2>/dev/null || printf '%s' "$$build_dir_phys/simv")"; \
			daidir_link="$$(realpath --relative-to="$$run_dir_phys" "$$build_dir_phys/simv.daidir" 2>/dev/null || printf '%s' "$$build_dir_phys/simv.daidir")"; \
		else \
			simv_link="$$build_dir_phys/simv"; \
			daidir_link="$$build_dir_phys/simv.daidir"; \
		fi; \
		ln -sfn "$$simv_link" "$$run_dir_phys/simv"; \
		ln -sfn "$$daidir_link" "$$run_dir_phys/simv.daidir"; \
	fi
	@pty_opt=""; \
	if [ -t 0 ] && [ -t 1 ]; then pty_opt="--pty"; fi; \
	cd $(RUN_DIR_ABS) && { \
		build_dir_phys="$$(cd "$(BUILD_DIR_ABS)" && pwd -P)"; \
		run_dir_phys="$$(pwd -P)"; \
		echo "======================================================================"; \
		echo "--- [PRE-RUN] Simulation Parameters Configuration                  ---"; \
		echo "======================================================================"; \
		echo " TEST_NAME   : $(TEST_NAME)"; \
		echo " SEED        : $(SEED)"; \
		echo " VERBOSITY   : $(VERB)"; \
		echo " COVERAGE    : $(if $(filter 1,$(COV)),ON,OFF)"; \
		echo " UVM_MODE    : $(UVM_MODE)"; \
		echo " CONN_TRACE  : $(if $(filter 1,$(CONN)),ON,OFF)"; \
		echo " CORE_COMP   : $(CORE)"; \
		echo " CORE_RUN    : $(RUN_CORE)"; \
		echo " RUN_DIR     : $$run_dir_phys"; \
		echo " SIMV        : $$build_dir_phys/simv"; \
		echo " LOG_FILE    : $(LOG)"; \
		echo " DUMP_EN     : $(if $(DUMP_EN),ON,OFF)"; \
		echo "======================================================================"; \
		echo "--- [RUN] Running Simulation ---"; \
		$(RUN_SRUN_CMD) $$pty_opt sh -c 'if [ ! -x ./simv ]; then echo "[ERROR] simv is not executable from RUN_DIR=$$(pwd -P)"; echo "[ERROR] ./simv link:"; ls -l ./simv 2>/dev/null || true; exit 127; fi; exec ./simv "$$@"' sh $(RUN_OPTS); \
	}

check-uvm-config:
	@echo "======================================================================"
	@echo "--- [UVM] UVM Library Configuration                                ---"
	@echo "======================================================================"
	@echo " USE_EXT_UVM       : $(USE_EXT_UVM)"
	@echo " UVM_MODE          : $(UVM_MODE)"
	@echo " EXT_UVM_HOME      : $(EXT_UVM_HOME)"
	@echo " EXT_UVM_SRC_DIR   : $(EXT_UVM_SRC_DIR)"
	@echo " EXT_UVM_USE_DPI   : $(EXT_UVM_USE_DPI)"
	@echo " VCS_UVM_OPTION    : $(UVM_VCS_BUILTIN_OPT)"
	@echo " VCS_CHAR_OPTION   : $(if $(filter 1,$(USE_EXT_UVM)),$(VCS_CHAR_AS_IDENTIFIER_OPT),N/A)"
	@if [ "$(USE_EXT_UVM)" != "0" ] && [ "$(USE_EXT_UVM)" != "1" ]; then \
		echo "[ERROR] USE_EXT_UVM must be 0 or 1."; \
		exit 1; \
	fi
	@if [ "$(USE_EXT_UVM)" = "1" ]; then \
		if [ -z "$(EXT_UVM_HOME)" ]; then \
			echo "[ERROR] USE_EXT_UVM=1 requires EXT_UVM_HOME=/path/to/uvm."; \
			exit 1; \
		fi; \
		if [ ! -f "$(EXT_UVM_SRC_DIR)/uvm_pkg.sv" ]; then \
			echo "[ERROR] Cannot find external UVM package: $(EXT_UVM_SRC_DIR)/uvm_pkg.sv"; \
			echo "[ERROR] EXT_UVM_HOME must point to the UVM kit root or directly to its src directory."; \
			exit 1; \
		fi; \
		if [ ! -f "$(EXT_UVM_SRC_DIR)/uvm_macros.svh" ]; then \
			echo "[ERROR] Cannot find external UVM macros: $(EXT_UVM_SRC_DIR)/uvm_macros.svh"; \
			exit 1; \
		fi; \
		if [ "$(EXT_UVM_USE_DPI)" = "1" ] && [ ! -f "$(EXT_UVM_DPI_DIR)/uvm_dpi.cc" ]; then \
			echo "[ERROR] Cannot find external UVM DPI source: $(EXT_UVM_DPI_DIR)/uvm_dpi.cc"; \
			exit 1; \
		fi; \
	fi
	@echo "======================================================================"

check-dut-mode:
	@if [ "$(DUT_MODE)" != "rtl" ] && [ "$(DUT_MODE)" != "stub" ]; then \
		echo "[ERROR] DUT_MODE must be rtl or stub (got: $(DUT_MODE))"; \
		exit 1; \
	fi
	@echo " DUT_MODE          : $(DUT_MODE)"
	@echo " SOURCE_MODE       : $(SOURCE_MODE)"

check-i3c-source:
	@if [ "$(DUT_MODE)" = "rtl" ]; then \
		bash $(SCRIPTS_DIR)/check_i3c_source.sh \
			--root "$(I3C_ROOT_DIR)" \
			--caliptra-root "$(CALIPTRA_ROOT)" \
			--layout "$(I3C_SOURCE_LAYOUT)" \
			--mode "$(SOURCE_MODE)" \
			--expected-branch "$(I3C_EXPECTED_BRANCH)" \
			--expected-commit "$(I3C_EXPECTED_COMMIT)" \
			--expected-caliptra-commit "$(CALIPTRA_EXPECTED_COMMIT)"; \
	else \
		echo "[INFO] DUT_MODE=stub: upstream I3C source check skipped"; \
	fi

check-vcs-version:
	@if [ "$(DUT_MODE)" = "rtl" ]; then \
		VCS_BIN="$(VCS)" MINIMUM="$(I3C_MIN_VCS_VERSION)" \
			bash $(SCRIPTS_DIR)/check_vcs_version.sh; \
	else \
		echo "[INFO] DUT_MODE=stub: I3C VCS version gate skipped"; \
	fi

i3c-reuse-check:
	@bash $(SCRIPTS_DIR)/check_i3c_reuse.sh

sim: comp run

gen-mk:
	@bash $(GEN_MK_SCRIPT) $(GEN_MK_OPTS) --root $(GEN_ROOT)

reuse-check:
	@bash $(SIM_MAKEFILE_DIR)/scripts/check_core_vseq_reuse.sh

wave:
	@echo "--- [DEBUG] Opening Verdi ---"
	@if [ ! -f "$(FSDB_FILE_ABS)" ]; then \
		echo "[ERROR] FSDB file not found: $(FSDB_FILE_ABS)"; \
		exit 1; \
	fi
	@cd $(BUILD_DIR_ABS) && { \
		pty_opt=""; \
		if [ -t 0 ] && [ -t 1 ]; then pty_opt="--pty"; fi; \
		verdi_rtl_opt=""; \
		rtl_flist="$(BUILD_RTL_FLIST_ABS)"; \
		if [ ! -f "$$rtl_flist" ]; then \
			rtl_flist="$(RTL_FLIST)"; \
		fi; \
		if [ -f "$$rtl_flist" ]; then \
			verdi_rtl_opt="-f $$rtl_flist"; \
			echo " RTL_FLIST : $$rtl_flist"; \
		else \
			echo "[WARNING] RTL filelist not found; opening FSDB without source map"; \
		fi; \
		echo " WAVE_TOP  : $(WAVE_TOP)"; \
		echo " FSDB      : $(FSDB_FILE_ABS)"; \
		$(GUI_SRUN_CMD) $$pty_opt $(VERDI) -sv $(INCDIRS) \
			+define+VERDI_WAVE_ONLY \
			$(WAVE_SRC_FILES) $$verdi_rtl_opt \
			-top $(WAVE_TOP) -ssf "$(FSDB_FILE_ABS)" & \
	}

clean:
	@echo "--- [CLEAN] Removing temporary files ---"
	rm -rf $(BUILD_DIR_ABS)/csrc $(BUILD_DIR_ABS)/simv* $(BUILD_DIR_ABS)/*.daidir $(BUILD_DIR_ABS)/*.log $(BUILD_DIR_ABS)/*.vpd $(BUILD_DIR_ABS)/*.fsdb $(BUILD_DIR_ABS)/*.key \
           vc_hdrs.h ucli.key urgReport .vlogans setup.env \
           $(ARTIFACT_ROOT_ABS)/$(LOG_DIR) $(BUILD_DIR_ABS)/verdiLog $(BUILD_DIR_ABS)/novas.* $(BUILD_DIR_ABS)/DVEfiles $(BUILD_DIR_ABS)/stack.info

help:
	@echo "======================================================================"
	@echo "--- Synopsys VCS UVM Makefile Help                                 ---"
	@echo "======================================================================"
	@echo " Targets:"
	@echo "  make all / sim                    : Compile and Run (Recommended)"
	@echo "  make comp                         : Compile RTL and TB only"
	@echo "  make run                          : Run simulation (requires compiled simv)"
	@echo "  make wave                         : Open Waveform (Verdi)"
	@echo "  make check-uvm-config             : Print and validate current UVM library selection"
	@echo "  make reuse-check                  : Check blackbox-safe vseqs have no direct APB/RAL/HDL dependency"
	@echo "  make clean                        : Lightweight local clean for direct make usage"
	@echo "  make help                         : Print this help message"
	@echo ""
	@echo " Script-owned flows:"
	@echo "  ./run.sh cov_rep                  : Merge/generate coverage report"
	@echo "  ./run.sh view cov_view            : View merged coverage report"
	@echo "  ./run.sh clean ...                : Manifest-aware clean helpers"
	@echo ""
	@echo " Execution Parameters (Command Line Overrides):"
	@echo "  TEST_NAME=<name>                  : UVM test name (Default: smc_i3c_csr_smoke_test)"
	@echo "  SEED=<number> / random            : Simulation random seed (Default: 1)"
	@echo "  COV=1                             : Enable coverage collection (Default: OFF)"
	@echo "  VERB=<UVM_NONE|UVM_LOW|...>       : UVM verbosity level (Default: UVM_LOW)"
	@echo "  CONN=1                            : Enable UVM config DB trace (Default: 0)"
	@echo "  USE_EXT_UVM=0                     : Use simulator built-in UVM through -ntb_opts uvm (Default)"
	@echo "  USE_EXT_UVM=1                     : Use external UVM from EXT_UVM_HOME"
	@echo "  EXT_UVM_HOME=<path>               : External UVM kit root or src directory"
	@echo "  EXT_UVM_USE_DPI=1                 : Compile external UVM DPI source (Default: 1)"
	@echo "  EXT_UVM_USE_DPI=0                 : Compile external UVM with +define+UVM_NO_DPI"
	@echo "  CORE=<number>                     : Number of compile cores (Default: 4)"
	@echo "  RUN_CORE=<number>                 : Number of run cores per simulation job (Default: 1)"
	@echo "  GEN_MK_OPTS=<opts>                : Generator options for gen-mk (Default: --mk)"
	@echo "  See ../../docs/README.md or sim/filelists/test.f for the current test list"
	@echo ""
	@echo " Examples:"
	@echo "  make sim"
	@echo "  make sim USE_EXT_UVM=1 EXT_UVM_HOME=/path/to/uvm-core-2020.3.1"
	@echo "  make sim USE_EXT_UVM=1 EXT_UVM_HOME=/path/to/uvm-core-2020.3.1 EXT_UVM_USE_DPI=0"
	@echo "======================================================================"
