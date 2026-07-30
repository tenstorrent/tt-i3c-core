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
// File        : smc_i3c_ibi_observer.sv
// Description : Passive observer for I3C IBI.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-29
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_OBSERVER_SV
`define SMC_I3C_IBI_OBSERVER_SV

`uvm_analysis_imp_decl(_ibi_actual_axi)
`uvm_analysis_imp_decl(_ibi_actual_bus)
`uvm_analysis_imp_decl(_ibi_actual_host)

// Builds actual IBI transactions exclusively from host, passive-bus, IRQ and
// architectural STATUS observations. Descriptor prediction is intentionally
// owned by smc_i3c_ibi_predictor so checking and observation cannot share a
// descriptor correlation state-machine.
class smc_i3c_ibi_observer extends uvm_component;
  `uvm_component_utils(smc_i3c_ibi_observer)

  uvm_analysis_imp_ibi_actual_axi #(
    axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH), smc_i3c_ibi_observer
  ) axi_export;
  uvm_analysis_imp_ibi_actual_bus #(
    i3c_item, smc_i3c_ibi_observer
  ) bus_export;
  uvm_analysis_imp_ibi_actual_host #(
    smc_i3c_host_ibi_observation, smc_i3c_ibi_observer
  ) host_export;
  uvm_analysis_port #(smc_i3c_ibi_actual_item) actual_port;
  uvm_analysis_port #(smc_i3c_ibi_item) coverage_port;
  uvm_analysis_port #(smc_i3c_ibi_item) sva_port;

  smc_peripherals_env_cfg cfg;

  protected smc_i3c_ibi_actual_item actual_q[$];
  protected smc_i3c_ibi_passive_item passive_q[$];
  protected ibi_terminal_status_e pending_terminal_status_q[$];
  protected longint unsigned next_transaction_id = 1;
  protected longint unsigned next_source_sequence_by_addr[bit [6:0]];
  protected longint unsigned next_passive_sequence_by_addr[bit [6:0]];
  protected bit ibi_enabled_at_start_q[$];
  protected bit ibi_enabled;
  protected bit ibi_done_status_accounted;
  protected int unsigned pending_ibi_done_credits;

  function new(string name = "smc_i3c_ibi_observer",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    axi_export = new("axi_export", this);
    bus_export = new("bus_export", this);
    host_export = new("host_export", this);
    actual_port = new("actual_port", this);
    coverage_port = new("coverage_port", this);
    sva_port = new("sva_port", this);
    if ((cfg == null) || (cfg.ral_model == null))
      `uvm_fatal("IBI_OBSERVER_CFG",
                 "IBI observer requires env cfg and the I3C RAL model")
  endfunction

  protected function bit matches_reg(
      axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH) item,
      uvm_reg register_handle);
    return item.addr == register_handle.get_address(cfg.ral_model.default_map);
  endfunction

  protected function uvm_reg_data_t extract_field(
      uvm_reg_data_t register_value,
      uvm_reg_field field_handle);
    uvm_reg_data_t field_value;

    field_value = '0;
    for (int unsigned bit_index = 0;
         bit_index < field_handle.get_n_bits(); bit_index++) begin
      field_value[bit_index] =
        register_value[field_handle.get_lsb_pos() + bit_index];
    end
    return field_value;
  endfunction

  protected function int first_ibi_done_pending_index();
    foreach (actual_q[i]) begin
      if (!actual_q[i].irq_seen)
        return i;
    end
    return -1;
  endfunction

  protected function int first_status_ready_index();
    foreach (actual_q[i]) begin
      if (actual_q[i].irq_seen && !actual_q[i].status_seen)
        return i;
    end
    return -1;
  endfunction

  protected function bit capture_pending_ibi_done();
    int completion_index;

    completion_index = first_ibi_done_pending_index();
    if (completion_index < 0)
      return 1'b0;
    actual_q[completion_index].irq_seen = 1'b1;
    return 1'b1;
  endfunction

  protected function int find_actual_for_passive(
      bit [6:0] addr,
      longint unsigned source_sequence);
    foreach (actual_q[i]) begin
      if (!actual_q[i].passive_seen && (actual_q[i].addr == addr) &&
          (actual_q[i].source_sequence == source_sequence))
        return i;
    end
    return -1;
  endfunction

  protected function int find_passive_for_actual(
      bit [6:0] addr,
      longint unsigned source_sequence);
    foreach (passive_q[i]) begin
      if ((passive_q[i].addr == addr) &&
          (passive_q[i].source_sequence == source_sequence))
        return i;
    end
    return -1;
  endfunction

  protected function void attach_passive(
      smc_i3c_ibi_actual_item actual,
      smc_i3c_ibi_passive_item passive);
    actual.passive_seen = 1'b1;
    actual.passive_ack = passive.ack;
    foreach (passive.data[i])
      actual.passive_data.push_back(passive.data[i]);
  endfunction

  protected function void emit_attempt(smc_i3c_ibi_actual_item actual);
    smc_i3c_ibi_item item;

    if (!cfg.ibi_bcr_valid) begin
      `uvm_warning("IBI_OBSERVER_BCR",
                   "Skipping ATTEMPT coverage because the target BCR snapshot is invalid")
      return;
    end

    item = smc_i3c_ibi_item::type_id::create("attempt_item");
    item.evt_kind = IBI_EVT_ATTEMPT;
    item.transaction_id = actual.transaction_id;
    item.role = 1'b0;
    item.src_instance = actual.source_instance;
    item.ibi_addr = actual.addr;
    item.addr_class = cfg.ibi_addr_class;
    item.addr_class_valid = cfg.ibi_addr_class_valid;
    item.bcr = cfg.ibi_bcr;
    item.ibi_enabled = actual.ibi_enabled_at_attempt;
    item.requester_count = cfg.ibi_requester_count;
    item.arb_outcome = cfg.ibi_arb_outcome;
    item.bus_state = cfg.ibi_bus_state;
    coverage_port.write(item);
    sva_port.write(item);
    cfg.ibi_cov_attempt_samples++;
    actual.attempt_context_valid = 1'b1;
  endfunction

  protected function void emit_completion(smc_i3c_ibi_actual_item actual);
    smc_i3c_ibi_item item;

    item = smc_i3c_ibi_item::type_id::create("completion_item");
    item.evt_kind = IBI_EVT_COMPLETION;
    item.transaction_id = actual.transaction_id;
    item.attempt_context_valid = actual.attempt_context_valid;
    item.role = 1'b0;
    item.ack = actual.ack;
    item.retry_count = cfg.ibi_retry_count;
    item.terminal_status = actual.terminal_status;
    item.mdb_present = actual.data.size() > 0;
    if (item.mdb_present)
      item.mdb = actual.data[0];
    item.payload_len = item.mdb_present ? actual.data.size() - 1 : 0;
    item.dat_match = 1'b0;
    item.payload_policy = 2'd0;
    item.reset_error_kind = IBI_ERR_NONE;
    item.recovery_result = IBI_RECOVERY_NA;
    item.arb_outcome = cfg.ibi_arb_outcome;
    item.ibi_enabled = actual.ibi_enabled_at_attempt;
    coverage_port.write(item);
    cfg.ibi_cov_completion_samples++;
  endfunction

  protected function void try_complete_actual(int actual_index);
    smc_i3c_ibi_actual_item actual;

    actual = actual_q[actual_index];
    if (!actual.irq_seen || !actual.status_seen)
      return;
    if (cfg.require_ibi_passive_monitor_match && !actual.passive_seen)
      return;
    emit_completion(actual);
    actual_port.write(actual);
    actual_q.delete(actual_index);
  endfunction

  virtual function void write_ibi_actual_axi(
      axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH) item);
    int completion_index;
    uvm_reg_data_t field_value;

    if ((item == null) || (item.resp != 2'b00))
      return;

    if (item.write && matches_reg(item, cfg.ral_model.I3C_EC.TTI.CONTROL)) begin
      field_value = extract_field(
        item.data, cfg.ral_model.I3C_EC.TTI.CONTROL.IBI_EN);
      ibi_enabled = field_value[0];
      return;
    end

    // The external IRQ line is a wired summary of all enabled TTI interrupt
    // sources. Only architectural IBI_DONE status is valid completion
    // evidence; a threshold IRQ must never be correlated to an IBI.
    if (matches_reg(item, cfg.ral_model.I3C_EC.TTI.INTERRUPT_STATUS)) begin
      if (item.write) begin
        field_value = extract_field(
          item.data, cfg.ral_model.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE);
        if (field_value[0])
          ibi_done_status_accounted = 1'b0;
        return;
      end

      field_value = extract_field(
        item.rdata, cfg.ral_model.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE);
      if (field_value[0] && !ibi_done_status_accounted) begin
        if (!capture_pending_ibi_done())
          pending_ibi_done_credits++;
        ibi_done_status_accounted = 1'b1;
      end else if (!field_value[0]) begin
        ibi_done_status_accounted = 1'b0;
      end
      return;
    end

    if (item.write || !matches_reg(item, cfg.ral_model.I3C_EC.TTI.STATUS))
      return;

    completion_index = first_status_ready_index();
    field_value = extract_field(
      item.rdata, cfg.ral_model.I3C_EC.TTI.STATUS.LAST_IBI_STATUS);
    // Reading LAST_IBI_STATUS clears IBI_DONE in hardware.
    ibi_done_status_accounted = 1'b0;
    if (completion_index < 0) begin
      // STATUS can be observed in the same IRQ boundary before the host
      // driver publishes its completed IBI response. Preserve both pieces of
      // evidence and correlate them when the host observation arrives.
      if (pending_terminal_status_q.size() < pending_ibi_done_credits) begin
        pending_terminal_status_q.push_back(
          ibi_terminal_status_e'(field_value[2:0]));
        `uvm_info("IBI_OBSERVER_DEFERRED_STATUS",
                  "Deferred TTI.STATUS until the matching host IBI observation arrives",
                  UVM_HIGH)
      end else begin
        `uvm_warning("IBI_OBSERVER_EARLY_STATUS",
                     "Ignoring TTI.STATUS read without observed IBI_DONE status")
      end
      return;
    end

    actual_q[completion_index].terminal_status =
      ibi_terminal_status_e'(field_value[2:0]);
    actual_q[completion_index].status_seen = 1'b1;
    try_complete_actual(completion_index);
  endfunction

  virtual function void write_ibi_actual_host(
      smc_i3c_host_ibi_observation item);
    smc_i3c_ibi_actual_item actual;
    int passive_index;

    if (item == null)
      return;

    actual = smc_i3c_ibi_actual_item::type_id::create("actual_item");
    actual.transaction_id = next_transaction_id++;
    actual.addr = item.addr;
    actual.source_instance = cfg.resolve_ibi_source_instance(item.addr);
    if (!next_source_sequence_by_addr.exists(item.addr))
      next_source_sequence_by_addr[item.addr] = 1;
    actual.source_sequence = next_source_sequence_by_addr[item.addr]++;
    actual.ack = item.ack;
    if (ibi_enabled_at_start_q.size() != 0)
      actual.ibi_enabled_at_attempt = ibi_enabled_at_start_q.pop_front();
    else begin
      actual.ibi_enabled_at_attempt = ibi_enabled;
      `uvm_warning(
        "IBI_OBSERVER_START",
        "Host observed an IBI without a matching DUT-driven START snapshot")
    end
    foreach (item.data[i])
      actual.data.push_back(item.data[i]);

    if (pending_ibi_done_credits != 0) begin
      actual.irq_seen = 1'b1;
      pending_ibi_done_credits--;
    end

    passive_index = find_passive_for_actual(actual.addr,
                                             actual.source_sequence);
    if (passive_index >= 0) begin
      attach_passive(actual, passive_q[passive_index]);
      passive_q.delete(passive_index);
    end

    actual_q.push_back(actual);
    emit_attempt(actual);
    if (actual.irq_seen && (pending_terminal_status_q.size() != 0)) begin
      actual_q[actual_q.size() - 1].terminal_status =
        pending_terminal_status_q.pop_front();
      actual_q[actual_q.size() - 1].status_seen = 1'b1;
    end
    try_complete_actual(actual_q.size() - 1);
  endfunction

  virtual function void write_ibi_actual_bus(i3c_item item);
    smc_i3c_ibi_passive_item passive;
    int actual_index;

    if ((item == null) || !item.i3c || (item.bus_op != BusOpRead))
      return;

    passive = new();
    passive.addr = item.addr;
    if (!next_passive_sequence_by_addr.exists(item.addr))
      next_passive_sequence_by_addr[item.addr] = 1;
    passive.source_sequence = next_passive_sequence_by_addr[item.addr]++;
    passive.ack = item.addr_ack;
    foreach (item.data_q[i])
      passive.data.push_back(item.data_q[i]);

    actual_index = find_actual_for_passive(passive.addr,
                                           passive.source_sequence);
    if (actual_index >= 0) begin
      attach_passive(actual_q[actual_index], passive);
      try_complete_actual(actual_index);
    end else
      passive_q.push_back(passive);
  endfunction

  virtual task run_phase(uvm_phase phase);
    ibi_done_status_accounted = 1'b0;
    pending_ibi_done_credits = 0;
    fork
      forever begin
        @(posedge cfg.vif.clk);
        if (!cfg.vif.rst_n) begin
          actual_q.delete();
          passive_q.delete();
          pending_terminal_status_q.delete();
          next_source_sequence_by_addr.delete();
          next_passive_sequence_by_addr.delete();
          ibi_enabled_at_start_q.delete();
          ibi_enabled = 1'b0;
          ibi_done_status_accounted = 1'b0;
          pending_ibi_done_credits = 0;
        end
      end
      forever begin
        @(negedge cfg.i3c_vif.sda_i);
        if (cfg.vif.rst_n && (cfg.i3c_vif.scl_i === 1'b1) &&
            (cfg.vif.i3c_sda_oe === 1'b1))
          ibi_enabled_at_start_q.push_back(ibi_enabled);
      end
    join
  endtask

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (actual_q.size() != 0)
      `uvm_error("IBI_OBSERVER_PENDING",
                 $sformatf("%0d host-observed IBI transaction(s) lack IRQ/STATUS completion",
                           actual_q.size()))
    if (pending_ibi_done_credits != 0)
      `uvm_error("IBI_OBSERVER_IRQ",
                  $sformatf("%0d IBI_DONE status observation(s) lack a host transaction",
                             pending_ibi_done_credits))
    if (pending_terminal_status_q.size() != 0)
      `uvm_error("IBI_OBSERVER_STATUS",
                 $sformatf("%0d deferred IBI status observation(s) lack a host transaction",
                           pending_terminal_status_q.size()))
    if (cfg.require_ibi_passive_monitor_match && (passive_q.size() != 0))
      `uvm_error("IBI_OBSERVER_PASSIVE",
                 $sformatf("%0d passive I3C observation(s) were not correlated",
                           passive_q.size()))
  endfunction
endclass : smc_i3c_ibi_observer

`endif // SMC_I3C_IBI_OBSERVER_SV
