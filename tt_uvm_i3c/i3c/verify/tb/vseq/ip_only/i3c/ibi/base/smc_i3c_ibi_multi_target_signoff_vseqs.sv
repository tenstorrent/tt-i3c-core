// ****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
//
// File        : smc_i3c_ibi_multi_target_signoff_vseqs.sv
// Description : Focused multi-target sign-off virtual-sequence identities.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-12
// ****************************************************************************

`ifndef SMC_I3C_IBI_MULTI_TARGET_SIGNOFF_VSEQS_SV
`define SMC_I3C_IBI_MULTI_TARGET_SIGNOFF_VSEQS_SV

// These focused identities deliberately reuse the checked transaction engines
// below. They keep result databases, waivers and defect triage separated while
// preserving the same passive scoreboard, SVA and coverage paths.
class smc_i3c_ibi_target_tx_multi_target_addr_matrix_vseq extends
    smc_i3c_ibi_target_tx_multi_target_vseq;
  `uvm_object_utils(smc_i3c_ibi_target_tx_multi_target_addr_matrix_vseq)
  function new(string name = "smc_i3c_ibi_target_tx_multi_target_addr_matrix_vseq");
    super.new(name);
  endfunction
  virtual task body();
    super.body();
    `uvm_info("IBI_MULTI_ADDR_MATRIX",
              "Completed three-requester address ordering, winner and loser-release matrix",
              UVM_LOW)
  endtask
endclass

class smc_i3c_ibi_target_tx_multi_target_retry_limit_vseq extends
    smc_i3c_ibi_target_tx_retry_arbitration_vseq;
  `uvm_object_utils(smc_i3c_ibi_target_tx_multi_target_retry_limit_vseq)
  function new(string name = "smc_i3c_ibi_target_tx_multi_target_retry_limit_vseq");
    super.new(name);
  endfunction
  virtual task body();
    super.body();
    `uvm_info("IBI_MULTI_RETRY_LIMIT",
              $sformatf("Completed bounded Target retry-limit scenario with %0d retries",
                        vseq_ctx.cfg.ibi_retry_count),
              UVM_LOW)
  endtask
endclass

class smc_i3c_ibi_target_tx_multi_target_timing_vseq extends
    smc_i3c_ibi_target_tx_multi_target_vseq;
  `uvm_object_utils(smc_i3c_ibi_target_tx_multi_target_timing_vseq)
  function new(string name = "smc_i3c_ibi_target_tx_multi_target_timing_vseq");
    super.new(name);
  endfunction
  virtual task body();
    super.body();
    `uvm_info("IBI_MULTI_TIMING",
              "Completed concurrent and staggered requester START/handoff timing checks",
              UVM_LOW)
  endtask
endclass

class smc_i3c_ibi_target_tx_multi_target_content_vseq extends
    smc_i3c_ibi_target_tx_multi_target_vseq;
  `uvm_object_utils(smc_i3c_ibi_target_tx_multi_target_content_vseq)
  function new(string name = "smc_i3c_ibi_target_tx_multi_target_content_vseq");
    super.new(name);
  endfunction
  virtual task body();
    smc_i3c_ibi_target_tx_mdb_payload_vseq content_vseq;

    super.body();
    content_vseq = smc_i3c_ibi_target_tx_mdb_payload_vseq::type_id::create(
      "content_vseq");
    content_vseq.vseq_ctx = vseq_ctx;
    content_vseq.start(null);
    `uvm_info("IBI_MULTI_CONTENT",
              "Completed multi-requester arbitration followed by MDB/payload boundary content checks",
              UVM_LOW)
  endtask
endclass

class smc_i3c_ibi_controller_rx_multi_target_ordering_vseq extends
    smc_i3c_ibi_controller_rx_multi_target_vseq;
  `uvm_object_utils(smc_i3c_ibi_controller_rx_multi_target_ordering_vseq)
  function new(string name = "smc_i3c_ibi_controller_rx_multi_target_ordering_vseq");
    super.new(name);
  endfunction
  virtual task body();
    super.body();
    `uvm_info("IBI_CTRL_MULTI_ORDERING",
              "Completed winner-first FIFO ordering and deferred loser service checks",
              UVM_LOW)
  endtask
endclass

class smc_i3c_ibi_controller_rx_multi_target_ack_nack_vseq extends
    smc_i3c_ibi_controller_rx_multi_target_vseq;
  `uvm_object_utils(smc_i3c_ibi_controller_rx_multi_target_ack_nack_vseq)
  function new(string name = "smc_i3c_ibi_controller_rx_multi_target_ack_nack_vseq");
    super.new(name);
  endfunction
  virtual task body();
    smc_i3c_ibi_controller_rx_policy_vseq policy_vseq;

    super.body();
    // The multi-target engine leaves this probe on the final serviced loser.
    // The following single-target policy engine uses the primary requester.
    vseq_ctx.cfg.vif.i3c_controller_expected_addr =
      vseq_ctx.cfg.ibi_target_addr;
    policy_vseq = smc_i3c_ibi_controller_rx_policy_vseq::type_id::create(
      "policy_vseq");
    policy_vseq.vseq_ctx = vseq_ctx;
    policy_vseq.start(null);
    `uvm_info("IBI_CTRL_MULTI_ACK_NACK",
              "Completed multi-requester ordering followed by DAT ACK/NACK policy checks",
              UVM_LOW)
  endtask
endclass

class smc_i3c_ibi_controller_rx_multi_target_queue_pressure_vseq extends
    smc_i3c_ibi_controller_rx_multi_target_vseq;
  `uvm_object_utils(smc_i3c_ibi_controller_rx_multi_target_queue_pressure_vseq)
  function new(string name = "smc_i3c_ibi_controller_rx_multi_target_queue_pressure_vseq");
    super.new(name);
  endfunction
  virtual task body();
    smc_i3c_ibi_controller_rx_fifo_irq_vseq queue_vseq;

    super.body();
    // Restore the single-target SVA expectation before queue-pressure traffic.
    vseq_ctx.cfg.vif.i3c_controller_expected_addr =
      vseq_ctx.cfg.ibi_target_addr;
    queue_vseq = smc_i3c_ibi_controller_rx_fifo_irq_vseq::type_id::create(
      "queue_vseq");
    queue_vseq.vseq_ctx = vseq_ctx;
    queue_vseq.start(null);
    `uvm_info("IBI_CTRL_MULTI_QUEUE",
              "Completed multi-requester ordering followed by threshold/full/NACK queue pressure checks",
              UVM_LOW)
  endtask
endclass

class smc_i3c_ibi_multi_target_recovery_vseq extends
    smc_i3c_ibi_controller_rx_multi_target_vseq;
  `uvm_object_utils(smc_i3c_ibi_multi_target_recovery_vseq)
  function new(string name = "smc_i3c_ibi_multi_target_recovery_vseq");
    super.new(name);
  endfunction
  virtual task body();
    smc_i3c_ibi_controller_rx_recovery_cleanup_vseq recovery_vseq;

    super.body();
    // Recovery cleanup returns to the primary Target after multi-target
    // arbitration has updated the expected address for each serviced loser.
    vseq_ctx.cfg.vif.i3c_controller_expected_addr =
      vseq_ctx.cfg.ibi_target_addr;
    recovery_vseq =
      smc_i3c_ibi_controller_rx_recovery_cleanup_vseq::type_id::create(
        "recovery_vseq");
    recovery_vseq.vseq_ctx = vseq_ctx;
    recovery_vseq.start(null);
    `uvm_info("IBI_MULTI_RECOVERY",
              "Completed multi-requester arbitration, reset/flush cleanup and forward progress",
              UVM_LOW)
  endtask
endclass

`endif
