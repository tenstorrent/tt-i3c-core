# Manual child export. Parent environments include this fragment explicitly.
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
# File        : i3c_child_srcs.mk
# Description : TT UVM I3C simulation support file.
# Authors     : Duy Huynh, Dang Thai
# Date        : 2026-08-11
#
# *****************************************************************************

SMC_I3C_CHILD_ROOT := $(ROOT_DIR)/verify/tb/children/i3c

SMC_I3C_CHILD_INCDIRS := \
    +incdir+$(SMC_I3C_CHILD_ROOT)/env/apis \
    +incdir+$(SMC_I3C_CHILD_ROOT)/env/analysis \
    +incdir+$(SMC_I3C_CHILD_ROOT)/env/core \
    +incdir+$(SMC_I3C_CHILD_ROOT)/env/services \
    +incdir+$(SMC_I3C_CHILD_ROOT)/env/utils \
    +incdir+$(SMC_I3C_CHILD_ROOT)/vseq/core \
    +incdir+$(SMC_I3C_CHILD_ROOT)/vseq/integration/portable

SMC_I3C_CHILD_SRC_FILES := \
    $(SMC_I3C_CHILD_ROOT)/env/smc_i3c_child_pkg.sv \
    $(SMC_I3C_CHILD_ROOT)/blackbox/i3c_child_vseq_pkg.sv

# Leaf RAL is exported for parent integration but is not inserted into the SMC
# top model until the six-instance address map is approved.
SMC_I3C_LEAF_RAL_SRC := \
    $(I3C_ROOT_DIR)/src/csr/I3CCSR_uvm.sv
