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
// File        : i3c_ibi_controller_predictor.sv
// Description : Reference predictor for I3C IBI controller.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef I3C_IBI_CONTROLLER_PREDICTOR_SV
`define I3C_IBI_CONTROLLER_PREDICTOR_SV

`uvm_analysis_imp_decl(_ibi_ctrl_predictor_target)

class i3c_ibi_controller_predictor extends uvm_component;
  `uvm_component_utils(i3c_ibi_controller_predictor)

  uvm_analysis_imp_ibi_ctrl_predictor_target #(
    i3c_target_ibi_observation,
    i3c_ibi_controller_predictor
  ) target_export;
  uvm_analysis_port #(i3c_ibi_expected_item) expected_port;

  i3c_env_cfg cfg;

  function new(string name = "i3c_ibi_controller_predictor",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    target_export = new("target_export", this);
    expected_port = new("expected_port", this);
    if (cfg == null)
      `uvm_fatal("IBI_CTRL_PREDICTOR_CFG",
                 "Controller predictor requires environment config")
  endfunction

  virtual function void write_ibi_ctrl_predictor_target(
      i3c_target_ibi_observation observation);
    i3c_ibi_expected_item expected;
    bit autocmd_match;

    if (observation == null)
      return;
    if (!observation.arbitration_won)
      return;
    expected = i3c_ibi_expected_item::type_id::create("expected");
    expected.transaction_id = observation.transaction_id;
    expected.source_instance =
      cfg.resolve_ibi_source_instance(observation.addr);
    expected.target_addr = observation.addr;
    expected.source_sequence = observation.source_sequence;
    expected.dat_match =
      cfg.ibi_controller_dat_valid_by_addr.exists(observation.addr) &&
      cfg.ibi_controller_dat_valid_by_addr[observation.addr];
    expected.payload_policy = !expected.dat_match ? 2'd0 :
      (cfg.ibi_controller_dat_payload_by_addr[observation.addr] ?
         2'd2 : 2'd1);
    // DAT IBI_PAYLOAD governs permission to transfer an MDB/additional data
    // after an accepted IBI header.  A Target that advertises BCR[2]=0 sends
    // neither, so a matching non-rejecting DAT entry must still accept the
    // legal address-only request.  Keep the payload permission mandatory for
    // all existing MDB-bearing scenarios.
    expected.ibi_enabled =
      expected.dat_match &&
      !cfg.ibi_controller_dat_reject_by_addr[observation.addr] &&
      (cfg.ibi_controller_dat_payload_by_addr[observation.addr] ||
       !cfg.ibi_bcr[I3C_BCR_MDB_CAPABLE_BIT]);
    expected.expected_ack = expected.ibi_enabled &&
      !cfg.ibi_controller_fifo_full_expected_nack;
    // Snapshot controls at the bus attempt. Queue records may be drained and
    // correlated only after software changes the interrupt mask.
    expected.irq_enabled_at_attempt =
      cfg.ral_model.PIOControl.PIO_INTR_SIGNAL_ENABLE.
        IBI_STATUS_THLD_SIGNAL_EN.get_mirrored_value() != 0;
    expected.irq_asserted_at_attempt = (cfg.vif.i3c_irq === 1'b1);
    expected.queue_full_reject =
      cfg.ibi_controller_fifo_full_expected_nack;
    expected.expected_terminal_status = expected.expected_ack ?
      IBI_STATUS_SUCCESS : IBI_STATUS_FAILURE_NACK;
    expected.mdb_present = observation.data.size() != 0;
    expected.expected_status_type = 3'b000;
    if (observation.data.size() != 0) begin
      expected.mdb = observation.data[0];
      expected.payload_len = observation.data.size() - 1;
      for (int unsigned index = 1;
           index < observation.data.size(); index++)
        expected.payload.push_back(observation.data[index]);

      autocmd_match = expected.dat_match && expected.expected_ack &&
        cfg.ibi_controller_dat_autocmd_mask_by_addr.exists(observation.addr) &&
        cfg.ibi_controller_dat_autocmd_value_by_addr.exists(observation.addr) &&
        ((expected.mdb &
          cfg.ibi_controller_dat_autocmd_mask_by_addr[observation.addr]) ==
         cfg.ibi_controller_dat_autocmd_value_by_addr[observation.addr]);
      if (autocmd_match) begin
        // AUTOCMD_DATA_RPT is fixed to coalesced reporting in the reviewed
        // native HCI:
        // the Private Read bytes follow the IBI MDB/additional data in the
        // same status record, whose status type is AutoCmd IBI (3'b100).
        expected.expected_status_type = 3'b100;
        foreach (cfg.ibi_controller_autocmd_expected_data[index])
          expected.payload.push_back(
            cfg.ibi_controller_autocmd_expected_data[index]);
        expected.payload_len +=
          cfg.ibi_controller_autocmd_expected_data.size();
      end
    end
    expected_port.write(expected);
    cfg.ibi_controller_expected_events++;
  endfunction
endclass : i3c_ibi_controller_predictor

`endif // I3C_IBI_CONTROLLER_PREDICTOR_SV
