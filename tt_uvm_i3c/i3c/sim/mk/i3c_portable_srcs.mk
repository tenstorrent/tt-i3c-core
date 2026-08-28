# Manual portable export. Parent environments include this fragment explicitly.
SMC_I3C_PORTABLE_ROOT := $(ROOT_DIR)/verify/tb/portable/i3c

SMC_I3C_PORTABLE_INCDIRS := \
    +incdir+$(SMC_I3C_PORTABLE_ROOT)/env/apis \
    +incdir+$(SMC_I3C_PORTABLE_ROOT)/env/analysis \
    +incdir+$(SMC_I3C_PORTABLE_ROOT)/env/core \
    +incdir+$(SMC_I3C_PORTABLE_ROOT)/env/services \
    +incdir+$(SMC_I3C_PORTABLE_ROOT)/env/utils \
    +incdir+$(SMC_I3C_PORTABLE_ROOT)/vseq/core \
    +incdir+$(SMC_I3C_PORTABLE_ROOT)/vseq/integration/portable

SMC_I3C_PORTABLE_SRC_FILES := \
    $(SMC_I3C_PORTABLE_ROOT)/env/smc_i3c_portable_pkg.sv \
    $(SMC_I3C_PORTABLE_ROOT)/blackbox/i3c_portable_vseq_pkg.sv

# Leaf RAL is exported for parent integration but is not inserted into the SMC
# top model until the six-instance address map is approved.
SMC_I3C_LEAF_RAL_SRC := \
    $(I3C_ROOT_DIR)/src/csr/I3CCSR_uvm.sv
