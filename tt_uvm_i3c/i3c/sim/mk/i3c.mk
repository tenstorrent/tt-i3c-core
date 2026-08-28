# Manual I3C integration settings. Include after generated paths.mk.
I3C_LOCAL_CONFIG    := $(ROOT_DIR)/sim/project/i3c_source.local.mk
-include $(I3C_LOCAL_CONFIG)
DUT_MODE            ?= rtl
SOURCE_MODE         ?= $(if $(I3C_LOCAL_SOURCE_MODE),$(I3C_LOCAL_SOURCE_MODE),pinned)
I3C_SOURCE_LAYOUT   ?= auto
I3C_ROOT_DIR        ?= $(I3C_LOCAL_ROOT_DIR)
CALIPTRA_ROOT       ?= $(if $(I3C_LOCAL_CALIPTRA_ROOT),$(I3C_LOCAL_CALIPTRA_ROOT),$(I3C_ROOT_DIR)/third_party/caliptra-rtl)
I3C_VIP_ROOT        := $(ROOT_DIR)/verify/vip/i3c_vip
I3C_MANIFEST        := $(ROOT_DIR)/rtl/external/i3c_manifest.mk

include $(I3C_MANIFEST)
include $(I3C_VIP_ROOT)/i3c_vip.mk

ifeq ($(DUT_MODE),rtl)
RTL_FLIST           := $(FILELIST_DIR)/rtl_i3c.f
I3C_COMPILE_DEFINES := +define+SMC_USE_I3C_RTL +define+SMC_USE_I3C_RAL
I3C_RAL_SRC_FILES   := $(I3C_ROOT_DIR)/src/csr/I3CCSR_uvm.sv
I3C_RAL_INCDIRS     := +incdir+$(I3C_ROOT_DIR)/src/csr
else ifeq ($(DUT_MODE),stub)
I3C_COMPILE_DEFINES :=
I3C_RAL_SRC_FILES   :=
I3C_RAL_INCDIRS     :=
I3C_VIP_INCDIRS     :=
I3C_VIP_SRC_FILES   :=
else
$(error DUT_MODE must be 'rtl' or 'stub', got '$(DUT_MODE)')
endif

export I3C_ROOT_DIR
export CALIPTRA_ROOT
export DUT_MODE
export SOURCE_MODE
export I3C_SOURCE_LAYOUT
export I3C_EXPECTED_BRANCH
export I3C_EXPECTED_COMMIT
export CALIPTRA_EXPECTED_COMMIT
