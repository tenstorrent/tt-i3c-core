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
// File        : smc_i3c_ibi_predictor.sv
// Description : Reference predictor for I3C IBI.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_PREDICTOR_SV
`define SMC_I3C_IBI_PREDICTOR_SV

`uvm_analysis_imp_decl(_ibi_predictor_axi)

class smc_i3c_ibi_predictor extends uvm_component;
  `uvm_component_utils(smc_i3c_ibi_predictor)

  uvm_analysis_imp_ibi_predictor_axi #(
    axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH), smc_i3c_ibi_predictor
  ) axi_export;
  uvm_analysis_port #(smc_i3c_ibi_expected_item) expected_port;

  smc_peripherals_env_cfg cfg;

  protected smc_i3c_ibi_expected_item payload_fill_item;
  protected int unsigned payload_words_remaining;
  protected longint unsigned next_transaction_id = 1;
  protected longint unsigned next_source_sequence = 1;

  function new(string name = "smc_i3c_ibi_predictor",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    axi_export = new("axi_export", this);
    expected_port = new("expected_port", this);
    if ((cfg == null) || (cfg.ral_model == null))
      `uvm_fatal("IBI_PREDICTOR_CFG",
                 "IBI predictor requires env cfg and the I3C RAL model")
  endfunction

  protected function bit matches_reg(
      axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH) item,
      uvm_reg register_handle);
    return item.addr == register_handle.get_address(cfg.ral_model.default_map);
  endfunction

  protected function void publish_expected();
    expected_port.write(payload_fill_item);
    payload_fill_item = null;
  endfunction

  virtual function void write_ibi_predictor_axi(
      axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH) item);
    int byte_index;

    if ((item == null) || (item.resp != 2'b00) || !item.write ||
        !matches_reg(item, cfg.ral_model.I3C_EC.TTI.IBI_PORT))
      return;

    if (payload_words_remaining == 0) begin
      payload_fill_item = smc_i3c_ibi_expected_item::type_id::create(
        "expected_item");
      payload_fill_item.transaction_id = next_transaction_id++;
      payload_fill_item.source_instance =
        cfg.resolve_ibi_source_instance(cfg.ibi_target_addr);
      payload_fill_item.target_addr = cfg.ibi_target_addr;
      payload_fill_item.source_sequence = next_source_sequence++;
      // Snapshot the planned controller response with the descriptor. Keeping
      // response and architectural result transaction-local prevents a later
      // phase from changing an expected item that is awaiting completion.
      payload_fill_item.expected_ack = cfg.ibi_expected_ack;
      payload_fill_item.expected_terminal_status =
        cfg.ibi_expected_terminal_status;
      payload_fill_item.mdb_present = 1'b1;
      payload_fill_item.mdb = item.data[31:24];
      // TT descriptor_ibi consumes the payload length from IBI_PORT[7:0].
      payload_fill_item.payload_len = item.data[7:0];
      payload_words_remaining = (payload_fill_item.payload_len + 3) / 4;
      if (payload_words_remaining == 0)
        publish_expected();
      return;
    end

    for (byte_index = 0; byte_index < 4; byte_index++) begin
      if (payload_fill_item.payload.size() < payload_fill_item.payload_len)
        payload_fill_item.payload.push_back(item.data[8*byte_index +: 8]);
    end
    payload_words_remaining--;
    if (payload_words_remaining == 0)
      publish_expected();
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      @(negedge cfg.vif.rst_n);
      payload_fill_item = null;
      payload_words_remaining = 0;
      next_source_sequence = 1;
    end
  endtask

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (payload_words_remaining != 0)
      `uvm_error("IBI_PREDICTOR_PAYLOAD",
                 $sformatf("Descriptor is missing %0d payload word(s)",
                           payload_words_remaining))
  endfunction
endclass : smc_i3c_ibi_predictor

`endif // SMC_I3C_IBI_PREDICTOR_SV
