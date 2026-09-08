# Native I3C integration settings for the generic DV runner.
# The preferred layout is a native I3C repository containing src/i3c.f and
# this DV tree. I3C_ROOT_DIR is an explicit native-source root override.

I3C_ROOT_DIR       ?=
ifeq ($(strip $(I3C_ROOT_DIR)),)
I3C_ROOT_DIR       := $(abspath $(ROOT_DIR)/../..)
endif
CALIPTRA_ROOT      ?= $(I3C_ROOT_DIR)/third_party/caliptra-rtl
I3C_VIP_ROOT        := $(ROOT_DIR)/verify/vip/i3c_vip
I3C_NATIVE_FILELIST := $(I3C_ROOT_DIR)/src/i3c.f

include $(I3C_VIP_ROOT)/i3c_vip.mk

I3C_COMPILE_DEFINES := +define+I3C_DV_NATIVE_RTL +define+I3C_DV_NATIVE_RAL
I3C_RAL_SRC_FILES   := $(I3C_ROOT_DIR)/src/csr/I3CCSR_uvm.sv
I3C_RAL_INCDIRS     := +incdir+$(I3C_ROOT_DIR)/src/csr

export I3C_ROOT_DIR
export CALIPTRA_ROOT
