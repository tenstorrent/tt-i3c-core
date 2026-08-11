SHELL := /bin/bash
# *****************************************************************************
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 VNCHIP LABS
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# File        : i3c_inputs.mk
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************


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
	@if [[ "$(DUT_MODE)" == "rtl" ]]; then \
		printf '%s\n' '-f $${I3C_ROOT_DIR}/src/i3c.f'; \
		printf '%s\n' '$(PROJECT_ROOT)/rtl/wrappers/smc_i3c_axi_adapter.sv'; \
		printf '%s\n' '$(PROJECT_ROOT)/rtl/wrappers/smc_i3c_wrapper.sv'; \
		printf '%s\n' '$(PROJECT_ROOT)/rtl/smc_peripherals_top.sv'; \
	else \
		printf '%s\n' '$(PROJECT_ROOT)/rtl/smc_peripherals_stub.sv'; \
	fi
