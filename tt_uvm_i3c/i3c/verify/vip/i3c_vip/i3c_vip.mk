I3C_VIP_MK_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
I3C_VIP_DIR := $(I3C_VIP_MK_DIR)

I3C_VIP_INCDIRS := \
    +incdir+$(I3C_VIP_DIR) \
    +incdir+$(I3C_VIP_DIR)/agent \
    +incdir+$(I3C_VIP_DIR)/core \
    +incdir+$(I3C_VIP_DIR)/if \
    +incdir+$(I3C_VIP_DIR)/include \
    +incdir+$(I3C_VIP_DIR)/sequences

I3C_VIP_TYPES_SRC_FILES := \
    $(I3C_VIP_DIR)/core/i3c_vip_types_pkg.sv

I3C_VIP_IF_SRC_FILES := \
    $(I3C_VIP_DIR)/if/i3c_if.sv

I3C_VIP_PKG_SRC_FILES := \
    $(I3C_VIP_DIR)/i3c_vip_pkg.sv

I3C_VIP_SRC_FILES := \
    $(I3C_VIP_TYPES_SRC_FILES) \
    $(I3C_VIP_IF_SRC_FILES) \
    $(I3C_VIP_PKG_SRC_FILES)

I3C_VIP_SVA_SRC_FILES :=
