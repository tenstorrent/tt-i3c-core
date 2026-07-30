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
// File        : smc_i3c_ibi_controller_observer.sv
// Description : Passive observer for I3C IBI controller.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_CONTROLLER_OBSERVER_SV
`define SMC_I3C_IBI_CONTROLLER_OBSERVER_SV

`uvm_analysis_imp_decl(_ibi_ctrl_observer_target)
`uvm_analysis_imp_decl(_ibi_ctrl_observer_bus)
`uvm_analysis_imp_decl(_ibi_ctrl_observer_axi)

class smc_i3c_ibi_controller_observer extends uvm_component;
  `uvm_component_utils(smc_i3c_ibi_controller_observer)

  uvm_analysis_imp_ibi_ctrl_observer_target #(
    smc_i3c_target_ibi_observation,
    smc_i3c_ibi_controller_observer
  ) target_export;
  uvm_analysis_imp_ibi_ctrl_observer_bus #(
    i3c_item, smc_i3c_ibi_controller_observer
  ) bus_export;
  uvm_analysis_imp_ibi_ctrl_observer_axi #(
    axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH),
    smc_i3c_ibi_controller_observer
  ) axi_export;
  uvm_analysis_port #(smc_i3c_ibi_controller_actual_item) actual_port;

  smc_peripherals_env_cfg cfg;

  protected smc_i3c_target_ibi_observation target_q[$];
  protected smc_i3c_ibi_passive_item passive_q[$];
  protected smc_i3c_ibi_controller_actual_item completed_q[$];
  protected smc_i3c_ibi_controller_actual_item active_hci;
  protected int unsigned hci_words_remaining;
  protected int unsigned pending_irq_credits;
  protected bit previous_irq;
  protected longint unsigned next_transaction_id = 1;
  protected longint unsigned next_hci_sequence_by_addr[bit [6:0]];
  protected longint unsigned next_passive_sequence_by_addr[bit [6:0]];

  protected function bit decode_ibi_addr(bit [7:0] ibi_id,
                                         output bit [6:0] addr);
    foreach (cfg.ibi_controller_dat_valid_by_addr[candidate]) begin
      if (cfg.ibi_controller_dat_valid_by_addr[candidate] &&
          ((ibi_id == {1'b0, candidate}) ||
           (ibi_id == {candidate, 1'b1}))) begin
        addr = candidate;
        return 1'b1;
      end
    end
    addr = ibi_id[6:0];
    return 1'b0;
  endfunction

  function new(string name = "smc_i3c_ibi_controller_observer",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    target_export = new("target_export", this);
    bus_export = new("bus_export", this);
    axi_export = new("axi_export", this);
    actual_port = new("actual_port", this);
    if ((cfg == null) || (cfg.ral_model == null))
      `uvm_fatal("IBI_CTRL_OBSERVER_CFG",
                 "Controller observer requires config and RAL model")
  endfunction

  protected function bit matches_ibi_port(
      axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH) item);
    return item.addr ==
      cfg.ral_model.PIOControl.IBI_PORT.get_address(
        cfg.ral_model.default_map);
  endfunction

  protected function int find_target_index(
      bit [6:0] addr,
      longint unsigned source_sequence);
    foreach (target_q[index]) begin
      if ((target_q[index].addr == addr) &&
          (target_q[index].source_sequence == source_sequence))
        return index;
    end
    return -1;
  endfunction

  protected function int find_passive_index(
      bit [6:0] addr,
      longint unsigned source_sequence);
    foreach (passive_q[index]) begin
      if ((passive_q[index].addr == addr) &&
          (passive_q[index].source_sequence == source_sequence))
        return index;
    end
    return -1;
  endfunction

  protected function int find_completed_index(
      bit [6:0] addr,
      longint unsigned source_sequence);
    foreach (completed_q[index]) begin
      if ((completed_q[index].addr == addr) &&
          (completed_q[index].source_sequence == source_sequence))
        return index;
    end
    return -1;
  endfunction

  protected function void attach_target(
      smc_i3c_ibi_controller_actual_item actual,
      smc_i3c_target_ibi_observation target);
    actual.target_seen = 1'b1;
    actual.ack = target.ack;
    actual.arbitration_won = target.arbitration_won;
  endfunction

  protected function void attach_passive(
      smc_i3c_ibi_controller_actual_item actual,
      smc_i3c_ibi_passive_item passive);
    actual.passive_seen = 1'b1;
    actual.passive_ack = passive.ack;
    foreach (passive.data[index])
      actual.passive_data.push_back(passive.data[index]);
  endfunction

  protected function void try_publish(int index);
    smc_i3c_ibi_controller_actual_item actual;

    if ((index < 0) || (index >= completed_q.size()))
      return;
    actual = completed_q[index];
    if (!actual.hci_complete || !actual.target_seen || !actual.irq_seen)
      return;
    if (cfg.require_ibi_passive_monitor_match && !actual.passive_seen)
      return;
    actual_port.write(actual);
    cfg.ibi_controller_actual_events++;
    completed_q.delete(index);
  endfunction

  protected function void complete_hci_item();
    int target_index;
    int passive_index;

    active_hci.hci_complete = 1'b1;
    target_index = find_target_index(active_hci.addr,
                                     active_hci.source_sequence);
    if (target_index >= 0) begin
      attach_target(active_hci, target_q[target_index]);
      target_q.delete(target_index);
    end
    passive_index = find_passive_index(active_hci.addr,
                                       active_hci.source_sequence);
    if (passive_index >= 0) begin
      attach_passive(active_hci, passive_q[passive_index]);
      passive_q.delete(passive_index);
    end
    completed_q.push_back(active_hci);
    active_hci = null;
    hci_words_remaining = 0;
    try_publish(completed_q.size() - 1);
  endfunction

  virtual function void write_ibi_ctrl_observer_target(
      smc_i3c_target_ibi_observation observation);
    int completed_index;

    if (observation == null)
      return;
    if (!observation.arbitration_won) begin
      cfg.ibi_controller_arbitration_losses++;
      cfg.ibi_controller_loser_release_checks++;
      if (!observation.released_after_loss) begin
        cfg.ibi_controller_loser_release_failures++;
        `uvm_error("IBI_CTRL_LOSER_RELEASE",
                   $sformatf("Target 0x%02h retained SDA after losing arbitration",
                             observation.addr))
      end
      return;
    end
    completed_index = find_completed_index(observation.addr,
                                            observation.source_sequence);
    if (completed_index >= 0) begin
      attach_target(completed_q[completed_index], observation);
      try_publish(completed_index);
    end else begin
      target_q.push_back(observation);
    end
  endfunction

  virtual function void write_ibi_ctrl_observer_bus(i3c_item item);
    smc_i3c_ibi_passive_item passive;
    int completed_index;

    if ((item == null) || !item.i3c ||
        (item.bus_op != BusOpRead) ||
        (item.addr != cfg.ibi_target_addr))
      return;
    passive = new();
    passive.addr = item.addr;
    if (!next_passive_sequence_by_addr.exists(item.addr))
      next_passive_sequence_by_addr[item.addr] = 1;
    passive.source_sequence =
      next_passive_sequence_by_addr[item.addr]++;
    passive.ack = item.addr_ack;
    foreach (item.data_q[index])
      passive.data.push_back(item.data_q[index]);

    completed_index = find_completed_index(
      passive.addr, passive.source_sequence);
    if (completed_index >= 0) begin
      attach_passive(completed_q[completed_index], passive);
      try_publish(completed_index);
    end else begin
      passive_q.push_back(passive);
    end
  endfunction

  virtual function void write_ibi_ctrl_observer_axi(
      axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH) item);
    bit [31:0] word;

    if ((item == null) || item.write || (item.resp != 2'b00) ||
        !matches_ibi_port(item))
      return;
    word = item.rdata[31:0];
    if (active_hci == null) begin
      active_hci = smc_i3c_ibi_controller_actual_item::type_id::create(
        "actual");
      active_hci.transaction_id = next_transaction_id++;
      active_hci.descriptor = word;
      active_hci.data_length = word[7:0];
      active_hci.ibi_id = word[15:8];
      // A Regular IBI status descriptor carries the target's seven-bit
      // dynamic address zero-extended in IBI_ID. Retain compatibility parsing
      // for a shifted address so the scoreboard reports a field mismatch
      // instead of degrading into a correlation timeout.
      void'(decode_ibi_addr(word[15:8], active_hci.addr));
      active_hci.chunks = word[23:16];
      active_hci.last_status = word[24];
      active_hci.timestamp = word[25];
      active_hci.status_type = word[29:27];
      active_hci.error = word[30];
      active_hci.ibi_status = word[31];
      active_hci.source_instance =
        cfg.resolve_ibi_source_instance(active_hci.addr);
      if (!next_hci_sequence_by_addr.exists(active_hci.addr))
        next_hci_sequence_by_addr[active_hci.addr] = 1;
      active_hci.source_sequence =
        next_hci_sequence_by_addr[active_hci.addr]++;
      if (pending_irq_credits != 0) begin
        active_hci.irq_seen = 1'b1;
        pending_irq_credits--;
      end
      hci_words_remaining = (active_hci.data_length + 3) / 4;
      if (hci_words_remaining == 0)
        complete_hci_item();
      return;
    end

    for (int unsigned byte_index = 0; byte_index < 4; byte_index++) begin
      if (active_hci.hci_data.size() < active_hci.data_length)
        active_hci.hci_data.push_back(word[8*byte_index +: 8]);
    end
    hci_words_remaining--;
    if (hci_words_remaining == 0)
      complete_hci_item();
  endfunction

  virtual task run_phase(uvm_phase phase);
    previous_irq = 1'b0;
    forever begin
      @(posedge cfg.vif.clk);
      if (!cfg.vif.rst_n) begin
        target_q.delete();
        passive_q.delete();
        completed_q.delete();
        active_hci = null;
        hci_words_remaining = 0;
        pending_irq_credits = 0;
        previous_irq = 1'b0;
        next_hci_sequence_by_addr.delete();
        next_passive_sequence_by_addr.delete();
      end else begin
        if (!previous_irq && (cfg.vif.i3c_irq === 1'b1)) begin
          bit attached;

          attached = 1'b0;
          if ((active_hci != null) && !active_hci.irq_seen) begin
            active_hci.irq_seen = 1'b1;
            attached = 1'b1;
          end else begin
            for (int index = 0; index < completed_q.size(); index++) begin
              if (!completed_q[index].irq_seen) begin
                completed_q[index].irq_seen = 1'b1;
                attached = 1'b1;
                try_publish(index);
                break;
              end
            end
          end
          if (!attached)
            pending_irq_credits++;
          cfg.ibi_controller_irq_events++;
        end
        previous_irq = (cfg.vif.i3c_irq === 1'b1);
      end
    end
  endtask

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (active_hci != null)
      `uvm_error("IBI_CTRL_OBSERVER_PARTIAL",
                 "HCI IBI record ended with missing data DWORDs")
    if (completed_q.size() != 0)
      `uvm_error("IBI_CTRL_OBSERVER_PENDING",
                 $sformatf("%0d completed HCI record(s) lack target/IRQ/passive evidence",
                           completed_q.size()))
    if (target_q.size() != 0)
      `uvm_error("IBI_CTRL_OBSERVER_TARGET",
                 $sformatf("%0d target IBI observation(s) lack HCI records",
                           target_q.size()))
    if (cfg.require_ibi_passive_monitor_match &&
        (passive_q.size() != 0))
      `uvm_error("IBI_CTRL_OBSERVER_PASSIVE",
                 $sformatf("%0d passive IBI observation(s) were not correlated",
                           passive_q.size()))
  endfunction
endclass : smc_i3c_ibi_controller_observer

`endif // SMC_I3C_IBI_CONTROLLER_OBSERVER_SV
