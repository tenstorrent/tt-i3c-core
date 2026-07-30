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
// File        : smc_i3c_ibi_controller_predictor.sv
// Description : Reference predictor for I3C IBI controller.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_PREDICTOR_SV
`define SMC_I3C_IBI_CONTROLLER_PREDICTOR_SV

`uvm_analysis_imp_decl(_ibi_ctrl_predictor_target)

class smc_i3c_ibi_controller_predictor extends uvm_component;
  `uvm_component_utils(smc_i3c_ibi_controller_predictor)

  uvm_analysis_imp_ibi_ctrl_predictor_target #(
    smc_i3c_target_ibi_observation,
    smc_i3c_ibi_controller_predictor
  ) target_export;
  uvm_analysis_port #(smc_i3c_ibi_expected_item) expected_port;

  smc_peripherals_env_cfg cfg;

  function new(string name = "smc_i3c_ibi_controller_predictor",
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
      smc_i3c_target_ibi_observation observation);
    smc_i3c_ibi_expected_item expected;

    if (observation == null)
      return;
    if (!observation.arbitration_won)
      return;
    expected = smc_i3c_ibi_expected_item::type_id::create("expected");
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
    expected.ibi_enabled =
      expected.dat_match &&
      !cfg.ibi_controller_dat_reject_by_addr[observation.addr] &&
      cfg.ibi_controller_dat_payload_by_addr[observation.addr];
    expected.expected_ack = expected.ibi_enabled;
    expected.expected_terminal_status = expected.expected_ack ?
      IBI_STATUS_SUCCESS : IBI_STATUS_FAILURE_NACK;
    expected.mdb_present = observation.data.size() != 0;
    if (observation.data.size() != 0) begin
      expected.mdb = observation.data[0];
      expected.payload_len = observation.data.size() - 1;
      for (int unsigned index = 1;
           index < observation.data.size(); index++)
        expected.payload.push_back(observation.data[index]);
    end
    expected_port.write(expected);
    cfg.ibi_controller_expected_events++;
  endfunction
endclass : smc_i3c_ibi_controller_predictor

`endif // SMC_I3C_IBI_CONTROLLER_PREDICTOR_SV
