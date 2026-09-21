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
// File        : i3c_ibi_target_tx_random_vseq.sv
// Description : Coverage-directed constrained-random Target IBI sequence.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-07
//
// *****************************************************************************

`ifndef I3C_IBI_TARGET_TX_RANDOM_VSEQ_SV
`define I3C_IBI_TARGET_TX_RANDOM_VSEQ_SV

class i3c_ibi_target_tx_random_vseq extends i3c_ibi_random_base_vseq;
  `uvm_object_utils(i3c_ibi_target_tx_random_vseq)

  function new(string name = "i3c_ibi_target_tx_random_vseq");
    super.new(name);
  endfunction
endclass : i3c_ibi_target_tx_random_vseq

`endif // I3C_IBI_TARGET_TX_RANDOM_VSEQ_SV
