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
// File        : i3c_ibi_recovery_checker.sv
// Description : Passive checker for IBI cleanup and forward progress.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

`ifndef I3C_IBI_RECOVERY_CHECKER_SV
`define I3C_IBI_RECOVERY_CHECKER_SV

`uvm_analysis_imp_decl(_ibi_recovery_event)
`uvm_analysis_imp_decl(_ibi_recovery_axi)

class i3c_ibi_recovery_checker extends uvm_component;
  `uvm_component_utils(i3c_ibi_recovery_checker)

  uvm_analysis_imp_ibi_recovery_event #(
    i3c_ibi_item, i3c_ibi_recovery_checker
  ) event_export;
  uvm_analysis_imp_ibi_recovery_axi #(
    axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH),
    i3c_ibi_recovery_checker
  ) axi_export;
  uvm_analysis_port #(i3c_ibi_item) recovery_port;

  i3c_env_cfg cfg;

  protected bit active;
  protected bit role;
  protected ibi_error_kind_e cause;
  protected bit require_followup;
  protected bit trigger_seen;
  protected bit queue_empty;
  protected bit irq_low;
  protected bit bus_idle;
  protected bit forward_progress;
  protected bit last_recovered;
  protected longint unsigned next_transaction_id = 1;
  protected uvm_event result_event;

  function new(string name = "i3c_ibi_recovery_checker",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    event_export = new("event_export", this);
    axi_export = new("axi_export", this);
    recovery_port = new("recovery_port", this);
    result_event = new("result_event");
    if ((cfg == null) || (cfg.vif == null) || (cfg.ral_model == null))
      `uvm_fatal("IBI_RECOVERY_CFG",
                 "Recovery checker requires cfg, vif and I3C RAL model")
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

  function void arm_recovery(ibi_error_kind_e recovery_cause,
                             bit dut_controller_role,
                             bit expect_followup = 1'b1);
    if (active)
      `uvm_fatal("IBI_RECOVERY_REARM",
                 "A recovery observation is already active")
    if (recovery_cause == IBI_ERR_NONE)
      `uvm_fatal("IBI_RECOVERY_CAUSE",
                 "Recovery checker cannot be armed with IBI_ERR_NONE")

    active = 1'b1;
    role = dut_controller_role;
    cause = recovery_cause;
    require_followup = expect_followup;
    trigger_seen = 1'b0;
    queue_empty = 1'b0;
    irq_low = 1'b0;
    bus_idle = 1'b0;
    forward_progress = 1'b0;
    last_recovered = 1'b0;
    result_event.reset();
  endfunction

  protected function void publish_result(bit recovered);
    i3c_ibi_item item;

    if (!active)
      return;
    item = i3c_ibi_item::type_id::create("recovery_result");
    item.evt_kind = IBI_EVT_RECOVERY;
    item.transaction_id = next_transaction_id++;
    item.role = role;
    item.reset_error_kind = cause;
    item.recovery_result = recovered ? IBI_RECOVERED : IBI_NOT_RECOVERED;
    item.recovery_trigger_seen = trigger_seen;
    item.recovery_queue_empty = queue_empty;
    item.recovery_irq_low = irq_low;
    item.recovery_bus_idle = bus_idle;
    item.recovery_followup_expected = require_followup;
    item.recovery_forward_progress = forward_progress;
    recovery_port.write(item);
    cfg.ibi_cov_recovery_samples++;
    last_recovered = recovered;
    active = 1'b0;
    result_event.trigger();
  endfunction

  protected function void try_complete();
    if (active && trigger_seen && queue_empty && irq_low && bus_idle &&
        (!require_followup || forward_progress))
      publish_result(1'b1);
  endfunction

  virtual function void write_ibi_recovery_event(i3c_ibi_item item);
    if (!active || !trigger_seen || (item == null) ||
        (item.evt_kind != IBI_EVT_COMPLETION))
      return;
    if (item.ack && (item.terminal_status == IBI_STATUS_SUCCESS) &&
        (item.reset_error_kind == IBI_ERR_NONE))
      forward_progress = 1'b1;
    try_complete();
  endfunction

  virtual function void write_ibi_recovery_axi(
      axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH) item);
    uvm_reg_data_t field_value;

    if (!active || (item == null) || (item.resp != 2'b00))
      return;

    if (item.write) begin
      if (!role &&
          matches_reg(item, cfg.ral_model.I3C_EC.TTI.RESET_CONTROL)) begin
        field_value = extract_field(
          item.data,
          cfg.ral_model.I3C_EC.TTI.RESET_CONTROL.IBI_QUEUE_RST);
        if (field_value[0])
          trigger_seen = 1'b1;
      end else if (role &&
                   matches_reg(item, cfg.ral_model.I3CBase.RESET_CONTROL)) begin
        field_value = extract_field(
          item.data, cfg.ral_model.I3CBase.RESET_CONTROL.IBI_QUEUE_RST);
        if (field_value[0])
          trigger_seen = 1'b1;
      end
      return;
    end

    if (!trigger_seen)
      return;
    if (!role &&
        matches_reg(item, cfg.ral_model.I3C_EC.TTI.QUEUE_STATUS)) begin
      field_value = extract_field(
        item.rdata,
        cfg.ral_model.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY);
      if (field_value[0])
        queue_empty = 1'b1;
    end else if (role &&
                 matches_reg(item, cfg.ral_model.I3CBase.RESET_CONTROL)) begin
      field_value = extract_field(
        item.rdata, cfg.ral_model.I3CBase.RESET_CONTROL.IBI_QUEUE_RST);
      if (!field_value[0])
        queue_empty = 1'b1;
    end
    try_complete();
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      @(posedge cfg.vif.clk);
      if (!cfg.vif.rst_n) begin
        active = 1'b0;
      end else if (active && trigger_seen) begin
        if (cfg.vif.i3c_irq === 1'b0)
          irq_low = 1'b1;
`ifdef I3C_DV_NATIVE_RTL
        if ((cfg.i3c_vif != null) &&
            (cfg.i3c_vif.scl_i === 1'b1) &&
            (cfg.i3c_vif.sda_i === 1'b1))
          bus_idle = 1'b1;
`endif
        try_complete();
      end
    end
  endtask

  task wait_for_result(int unsigned timeout_cycles,
                       output bit completed,
                       output bit recovered);
    completed = 1'b0;
    recovered = 1'b0;
    fork : recovery_result_guard
      begin
        result_event.wait_on();
        completed = 1'b1;
      end
      begin
        repeat (timeout_cycles)
          @(posedge cfg.vif.clk);
      end
    join_any
    disable recovery_result_guard;

    if (!completed) begin
      `uvm_error("IBI_RECOVERY_TIMEOUT",
                 $sformatf("Recovery did not complete: cause=%s trigger=%0b queue_empty=%0b irq_low=%0b bus_idle=%0b forward_progress=%0b",
                           cause.name(), trigger_seen, queue_empty, irq_low,
                           bus_idle, forward_progress))
      publish_result(1'b0);
      completed = 1'b1;
    end
    recovered = last_recovered;
  endtask
endclass : i3c_ibi_recovery_checker

`endif // I3C_IBI_RECOVERY_CHECKER_SV
