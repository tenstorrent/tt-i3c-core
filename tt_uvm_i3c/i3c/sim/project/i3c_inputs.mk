SHELL := /bin/bash

PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
SIM_MAKEFILE_DIR := $(PROJECT_ROOT)/sim

include $(PROJECT_ROOT)/sim/mk/paths.mk
include $(PROJECT_ROOT)/sim/mk/incdirs.mk
include $(PROJECT_ROOT)/sim/mk/srcs.mk
include $(PROJECT_ROOT)/sim/mk/i3c.mk

.PHONY: emit-compile-filelist

emit-compile-filelist:
	@$(foreach item,$(INCDIRS),printf '%s\n' '$(item)';)
	@$(foreach item,$(I3C_RAL_INCDIRS),printf '%s\n' '$(item)';)
	@$(foreach item,$(I3C_VIP_INCDIRS),printf '%s\n' '$(item)';)
	@$(foreach item,$(TB_CORE_PKG_SRC_FILES),printf '%s\n' '$(item)';)
	@$(foreach item,$(VIP_IF_SRC_FILES),printf '%s\n' '$(item)';)
	@$(foreach item,$(I3C_RAL_SRC_FILES),printf '%s\n' '$(item)';)
	@$(foreach item,$(I3C_VIP_SRC_FILES),printf '%s\n' '$(item)';)
	@$(foreach item,$(ORDERED_PKG_SRC_FILES),printf '%s\n' '$(item)';)
	@$(foreach item,$(SVA_SRC_FILES),printf '%s\n' '$(item)';)
	@$(foreach item,$(TB_TOP_SRC_FILES),printf '%s\n' '$(item)';)
	printf '%s\n' '-f $${I3C_ROOT_DIR}/src/i3c.f'; \
	printf '%s\n' '$(PROJECT_ROOT)/verify/tb/adapters/i3c_dv_axi_adapter.sv'; \
	printf '%s\n' '$(PROJECT_ROOT)/verify/tb/wrappers/i3c_dv_wrapper.sv'
