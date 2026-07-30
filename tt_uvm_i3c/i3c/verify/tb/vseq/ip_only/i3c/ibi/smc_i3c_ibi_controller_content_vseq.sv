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
// File        : smc_i3c_ibi_controller_content_vseq.sv
// Description : Virtual sequence for I3C IBI controller content.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_CONTENT_VSEQ_SV
`define SMC_I3C_IBI_CONTROLLER_CONTENT_VSEQ_SV

// Exercises Controller HCI content packing with five accepted IBI bytes. The
// MDB plus four payload bytes cross a DWORD boundary, so the observer and
// scoreboard must consume two IBI_PORT data words while honoring DATA_LENGTH.
class smc_i3c_ibi_controller_content_vseq extends
    smc_i3c_ibi_controller_receive_vseq;
  `uvm_object_utils(smc_i3c_ibi_controller_content_vseq)

  function new(string name = "smc_i3c_ibi_controller_content_vseq");
    super.new(name);
  endfunction

  protected virtual function void configure_target_ibi(
      smc_i3c_target_send_ibi_seq target_seq);
    super.configure_target_ibi(target_seq);
    target_seq.payload.push_back(8'h11);
    target_seq.payload.push_back(8'h22);
    target_seq.payload.push_back(8'h33);
    target_seq.payload.push_back(8'h44);
  endfunction

  protected virtual function string scenario_name();
    return "Controller MDB-plus-payload receive";
  endfunction
endclass : smc_i3c_ibi_controller_content_vseq

`endif // SMC_I3C_IBI_CONTROLLER_CONTENT_VSEQ_SV
