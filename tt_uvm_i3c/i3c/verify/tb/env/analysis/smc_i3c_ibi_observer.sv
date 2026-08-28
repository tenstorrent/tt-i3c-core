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
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
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
  protected int unsigned retry_count_by_addr[bit [6:0]];
  protected bit ibi_enabled_at_start_q[$];
  protected bit ibi_enabled;
  protected bit ibi_done_status_accounted;
  protected int unsigned pending_ibi_done_credits;
  protected bit pending_descriptor_valid;
  protected bit [7:0] pending_descriptor_mdb;
  protected int unsigned pending_descriptor_payload_len;

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
    item.retry_count = actual.retry_count;
    item.terminal_status = actual.terminal_status;
    item.mdb_present = actual.data.size() > 0;
    if (item.mdb_present)
      item.mdb = actual.data[0];
    item.payload_len = item.mdb_present ? actual.data.size() - 1 : 0;
    item.dat_match = 1'b0;
    item.payload_policy = 2'd0;
    item.reset_error_kind =
      (actual.terminal_status == IBI_STATUS_FAILURE_PARTIAL_DATA) ?
        IBI_ERR_PROTOCOL : IBI_ERR_NONE;
    item.recovery_result =
      (actual.terminal_status == IBI_STATUS_FAILURE_PARTIAL_DATA) ?
        IBI_NOT_RECOVERED : IBI_RECOVERY_NA;
    item.arb_outcome = cfg.ibi_arb_outcome;
    item.ibi_enabled = actual.ibi_enabled_at_attempt;
    coverage_port.write(item);
    cfg.ibi_cov_completion_samples++;
  endfunction

  // Address-arbitration loss is architectural completion evidence for the
  // current descriptor, but it intentionally has no Host observation for the
  // losing DUT address. Correlate that one intermediate result to the AXI-
  // observed descriptor without publishing an actual scoreboard completion:
  // the descriptor remains queued and the later successful retry is the sole
  // terminal scoreboard transaction.
  protected function void complete_address_arb_loss();
    smc_i3c_ibi_actual_item actual;

    if (!pending_descriptor_valid) begin
      `uvm_error("IBI_OBSERVER_ADDR_ARB_ORPHAN",
                 "FAILURE_ADDRESS_ARB has no pending IBI_PORT descriptor")
      return;
    end

    actual = smc_i3c_ibi_actual_item::type_id::create(
      "address_arb_loss_actual");
    actual.transaction_id = next_transaction_id++;
    actual.addr = cfg.ibi_target_addr;
    actual.source_instance =
      cfg.resolve_ibi_source_instance(cfg.ibi_target_addr);
    if (!next_source_sequence_by_addr.exists(actual.addr))
      next_source_sequence_by_addr[actual.addr] = 1;
    actual.source_sequence = next_source_sequence_by_addr[actual.addr];
    actual.ack = 1'b0;
    actual.irq_seen = 1'b1;
    actual.status_seen = 1'b1;
    actual.terminal_status = IBI_STATUS_FAILURE_ADDRESS_ARB;
    actual.ibi_enabled_at_attempt = ibi_enabled;
    actual.data.push_back(pending_descriptor_mdb);
    repeat (pending_descriptor_payload_len)
      actual.data.push_back(8'h00);

    // Consume the START snapshot belonging to the losing attempt so the next
    // Host-observed retry receives its own enable-state snapshot.
    if (ibi_enabled_at_start_q.size() != 0)
      actual.ibi_enabled_at_attempt = ibi_enabled_at_start_q.pop_front();

    emit_attempt(actual);
    actual.retry_count = 1;
    emit_completion(actual);
    retry_count_by_addr[actual.addr] = 1;
    cfg.ibi_observed_retry_count++;
    cfg.ibi_observed_attempt_count++;
    if (pending_ibi_done_credits != 0)
      pending_ibi_done_credits--;
    // The STATUS read has now consumed and cleared the architectural
    // IBI_DONE source for this losing attempt. Close that completion boundary
    // explicitly so the retained descriptor's later retry can establish a
    // fresh IBI_DONE credit instead of having its SUCCESS status classified
    // as an uncorrelated early read.
    ibi_done_status_accounted = 1'b0;

    `uvm_info(
      "IBI_FAILURE_ADDR_ARB_CORRELATION",
      $sformatf("descriptor DA=0x%02h MDB=0x%02h payload_len=%0d correlated IBI_DONE=1 LAST_IBI_STATUS=0x%0h; descriptor retained for retry",
                actual.addr, pending_descriptor_mdb,
                pending_descriptor_payload_len,
                IBI_STATUS_FAILURE_ADDRESS_ARB),
      UVM_LOW)
  endfunction

  protected function void complete_retry_exhaustion();
    smc_i3c_ibi_actual_item actual;
    bit [6:0] addr;
    int actual_index;
    int unsigned candidate_count;

    addr = cfg.ibi_target_addr;
    actual_index = -1;
    candidate_count = 0;
    // Retry completion is correlated to the authoritative unresolved Host
    // observation. The per-address source sequence is deliberately not used
    // here: it is mutable retry bookkeeping and can advance independently of
    // the AXI STATUS observation path.
    foreach (actual_q[index]) begin
      `uvm_info(
        "IBI_OBSERVER_RETRY_CANDIDATE",
        $sformatf("actual_q[%0d]: transaction_id=%0d addr=0x%02h source_sequence=%0d ack=%0b irq_seen=%0b status_seen=%0b",
                  index, actual_q[index].transaction_id,
                  actual_q[index].addr, actual_q[index].source_sequence,
                  actual_q[index].ack, actual_q[index].irq_seen,
                  actual_q[index].status_seen),
        UVM_HIGH)
      if ((actual_q[index].addr == addr) &&
          !actual_q[index].status_seen) begin
        actual_index = index;
        candidate_count++;
      end
    end

    if (candidate_count > 1) begin
      `uvm_error(
        "IBI_OBSERVER_RETRY_AMBIGUOUS",
        $sformatf("FAILURE_RETRY matches %0d unresolved Host observations at DA=0x%02h",
                  candidate_count, addr))
      return;
    end

    if (actual_index < 0) begin
      // STATUS and Host observations use independent analysis paths. Retain
      // the architectural completion and bind it when the Host item arrives;
      // never manufacture a second transaction that can hide an orphan.
      if (pending_ibi_done_credits == 0)
        pending_ibi_done_credits = 1;
      if (pending_terminal_status_q.size() < pending_ibi_done_credits)
        pending_terminal_status_q.push_back(IBI_STATUS_FAILURE_RETRY);
      `uvm_info(
        "IBI_OBSERVER_DEFERRED_RETRY",
        $sformatf("Deferred FAILURE_RETRY until the Host observation for DA=0x%02h arrives",
                  addr),
        UVM_HIGH)
      return;
    end

    actual = actual_q[actual_index];
    actual.retry_count = retry_count_by_addr.exists(addr) ?
      retry_count_by_addr[addr] : 0;
    actual.irq_seen = 1'b1;
    actual.status_seen = 1'b1;
    actual.terminal_status = IBI_STATUS_FAILURE_RETRY;
    actual.ibi_enabled_at_attempt = ibi_enabled;
    // The terminal status belongs to the descriptor whose preceding NACK
    // attempts established the ATTEMPT context. It is not a new bus attempt.
    actual.attempt_context_valid = 1'b1;
    emit_completion(actual);
    actual_port.write(actual);
    actual_q.delete(actual_index);
    retry_count_by_addr[addr] = 0;
    next_source_sequence_by_addr[addr] = actual.source_sequence + 1;
    if (pending_ibi_done_credits != 0)
      pending_ibi_done_credits--;
  endfunction

  protected function void try_complete_actual(int actual_index);
    smc_i3c_ibi_actual_item actual;

    actual = actual_q[actual_index];
    if (!actual.irq_seen || !actual.status_seen)
      return;
    if (cfg.require_ibi_passive_monitor_match && !actual.passive_seen)
      return;

    if (cfg.ibi_retry_tracking &&
        (actual.terminal_status inside {
          IBI_STATUS_FAILURE_NACK, IBI_STATUS_FAILURE_ADDRESS_ARB})) begin
      if (!retry_count_by_addr.exists(actual.addr))
        retry_count_by_addr[actual.addr] = 0;
      retry_count_by_addr[actual.addr]++;
      actual.retry_count = retry_count_by_addr[actual.addr];
      cfg.ibi_observed_retry_count++;
      // A retryable result leaves the DUT descriptor queued. Preserve its
      // source sequence and do not create a second scoreboard transaction.
      emit_completion(actual);
      actual_q.delete(actual_index);
      return;
    end

    if (cfg.ibi_retry_tracking) begin
      if (!retry_count_by_addr.exists(actual.addr))
        retry_count_by_addr[actual.addr] = 0;
      actual.retry_count = retry_count_by_addr[actual.addr];
      retry_count_by_addr[actual.addr] = 0;
      next_source_sequence_by_addr[actual.addr] = actual.source_sequence + 1;
    end else begin
      actual.retry_count = cfg.ibi_retry_count;
    end
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

    if (item.write &&
        matches_reg(item, cfg.ral_model.I3C_EC.TTI.IBI_PORT) &&
        cfg.ibi_address_arb_status_correlation &&
        !pending_descriptor_valid) begin
      pending_descriptor_valid = 1'b1;
      pending_descriptor_mdb = item.data[31:24];
      pending_descriptor_payload_len = item.data[7:0];
      `uvm_info(
        "IBI_FAILURE_ADDR_ARB_DESCRIPTOR",
        $sformatf("tracking pending descriptor DA=0x%02h MDB=0x%02h payload_len=%0d",
                  cfg.ibi_target_addr, item.data[31:24], item.data[7:0]),
        UVM_LOW)
    end

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
    // AXI and IRQ observations arrive through independent analysis paths.
    // A STATUS read may therefore be delivered one delta before the IRQ edge
    // sampler even though the architectural IRQ pin is already high. Use the
    // pin as valid back-fill evidence rather than dropping terminal status.
    if ((completion_index < 0) && (cfg.vif.i3c_irq === 1'b1) &&
        capture_pending_ibi_done()) begin
      completion_index = first_status_ready_index();
      ibi_done_status_accounted = 1'b1;
    end
    field_value = extract_field(
      item.rdata, cfg.ral_model.I3C_EC.TTI.STATUS.LAST_IBI_STATUS);
    // Reading LAST_IBI_STATUS clears IBI_DONE in hardware, but an AXI
    // observation of INTERRUPT_STATUS can still report the old value in the
    // same completion boundary. Keep this event accounted until a zero read
    // or an explicit W1C write proves that the source has been cleared.
    if (completion_index < 0) begin
      if (cfg.ibi_address_arb_status_correlation &&
          (field_value[2:0] == IBI_STATUS_FAILURE_ADDRESS_ARB)) begin
        complete_address_arb_loss();
        return;
      end
      if (cfg.ibi_retry_exhaustion &&
          (field_value[2:0] == IBI_STATUS_FAILURE_RETRY)) begin
        complete_retry_exhaustion();
        return;
      end
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

    if (cfg.ibi_filter_external_target_observations &&
        (item.addr != cfg.ibi_target_addr)) begin
      `uvm_info("IBI_OBSERVER_EXTERNAL_TARGET",
                $sformatf("Ignoring external Target IBI at DA=0x%02h in the DUT-Target descriptor scoreboard",
                          item.addr),
                UVM_HIGH)
      return;
    end

    actual = smc_i3c_ibi_actual_item::type_id::create("actual_item");
    actual.transaction_id = next_transaction_id++;
    actual.addr = item.addr;
    actual.source_instance = cfg.resolve_ibi_source_instance(item.addr);
    if (!next_source_sequence_by_addr.exists(item.addr))
      next_source_sequence_by_addr[item.addr] = 1;
    if (cfg.ibi_retry_tracking)
      actual.source_sequence = next_source_sequence_by_addr[item.addr];
    else
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
    if (cfg.ibi_retry_tracking)
      cfg.ibi_observed_attempt_count++;

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
    if (cfg.ibi_address_arb_status_correlation &&
        (actual_q.size() == 0))
      pending_descriptor_valid = 1'b0;
  endfunction

  virtual function void write_ibi_actual_bus(i3c_item item);
    smc_i3c_ibi_passive_item passive;
    int actual_index;

    if ((item == null) || !item.i3c || (item.bus_op != BusOpRead))
      return;

    // The passive monitor has no descriptor-attempt identifier. Reusing a
    // source sequence across retries could bind an earlier NACK to the final
    // ACK, so retry closure uses the authoritative host-driver observation.
    if (cfg.ibi_retry_tracking)
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
          retry_count_by_addr.delete();
          ibi_enabled_at_start_q.delete();
          ibi_enabled = 1'b0;
          ibi_done_status_accounted = 1'b0;
          pending_ibi_done_credits = 0;
          pending_descriptor_valid = 1'b0;
          pending_descriptor_mdb = '0;
          pending_descriptor_payload_len = 0;
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
