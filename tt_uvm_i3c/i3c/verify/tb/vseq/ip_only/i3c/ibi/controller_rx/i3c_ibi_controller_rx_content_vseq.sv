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
// File        : i3c_ibi_controller_rx_content_vseq.sv
// Description : Virtual sequence for I3C IBI controller content.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef I3C_IBI_CONTROLLER_RX_CONTENT_VSEQ_SV
`define I3C_IBI_CONTROLLER_RX_CONTENT_VSEQ_SV

// Exercises Controller HCI content packing with five accepted IBI bytes. The
// MDB plus four payload bytes cross a DWORD boundary, so the observer and
// scoreboard must consume two IBI_PORT data words while honoring DATA_LENGTH.
class i3c_ibi_controller_rx_content_vseq extends
    i3c_ibi_controller_rx_basic_vseq;
  `uvm_object_utils(i3c_ibi_controller_rx_content_vseq)

  function new(string name = "i3c_ibi_controller_rx_content_vseq");
    super.new(name);
  endfunction

  protected virtual function void configure_target_ibi(
      i3c_target_send_ibi_seq target_seq);
    int unsigned payload_len = 4;

    super.configure_target_ibi(target_seq);
    void'($value$plusargs("IBI_CONTENT_PAYLOAD_LEN=%0d", payload_len));
    if (payload_len > 63)
      `uvm_fatal("IBI_CONTENT_PAYLOAD_LEN",
                 $sformatf("IBI_CONTENT_PAYLOAD_LEN must be 0..63, got %0d",
                           payload_len))
    for (int unsigned index = 0; index < payload_len; index++)
      target_seq.payload.push_back(byte'(8'h11 + index));
  endfunction

  protected virtual function string scenario_name();
    return "Controller parameterized MDB-plus-payload receive";
  endfunction
endclass : i3c_ibi_controller_rx_content_vseq

`endif // I3C_IBI_CONTROLLER_RX_CONTENT_VSEQ_SV
