// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// File        : smc_i3c_portable_constants.sv
// Description : Constants for the portable I3C child environment.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-14
//
// *****************************************************************************

localparam longint unsigned SMC_I3C_HCI_VERSION_OFFSET = 'h000;
localparam longint unsigned SMC_I3C_INTR_ENABLE_OFFSET = 'h024;
localparam bit [31:0] SMC_I3C_HCI_VERSION_RESET = 32'h0000_0120;
