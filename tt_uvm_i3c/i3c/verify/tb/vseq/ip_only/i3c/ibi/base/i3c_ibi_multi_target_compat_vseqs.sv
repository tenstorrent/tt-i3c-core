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
// File        : i3c_ibi_multi_target_compat_vseqs.sv
// Description : Customer regression compatibility virtual-sequence identities.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-12
//
// *****************************************************************************

`ifndef I3C_IBI_MULTI_TARGET_COMPAT_VSEQS_SV
`define I3C_IBI_MULTI_TARGET_COMPAT_VSEQS_SV

// These customer compatibility identities preserve historical testcase and
// result-database names while delegating behavior to canonical IBI engines.
// They do not make independent closure claims unless explicit checks exist in
// the wrapper itself.
class i3c_ibi_target_tx_multi_target_addr_matrix_vseq extends
    i3c_ibi_target_tx_multi_target_vseq;
  `uvm_object_utils(i3c_ibi_target_tx_multi_target_addr_matrix_vseq)
  function new(string name = "i3c_ibi_target_tx_multi_target_addr_matrix_vseq");
    super.new(name);
  endfunction
  virtual task body();
    super.body();
    `uvm_info("IBI_MULTI_ADDR_MATRIX",
              "Customer compatibility identity completed using canonical Target-TX multi-target behavior",
              UVM_LOW)
  endtask
endclass

class i3c_ibi_target_tx_multi_target_timing_vseq extends
    i3c_ibi_target_tx_multi_target_vseq;
  `uvm_object_utils(i3c_ibi_target_tx_multi_target_timing_vseq)
  function new(string name = "i3c_ibi_target_tx_multi_target_timing_vseq");
    super.new(name);
  endfunction
  virtual task body();
    super.body();
    `uvm_info("IBI_MULTI_TIMING",
              "Customer compatibility identity completed using canonical Target-TX multi-target timing behavior",
              UVM_LOW)
  endtask
endclass

class i3c_ibi_target_tx_multi_target_content_vseq extends
    i3c_ibi_target_tx_multi_target_vseq;
  `uvm_object_utils(i3c_ibi_target_tx_multi_target_content_vseq)
  function new(string name = "i3c_ibi_target_tx_multi_target_content_vseq");
    super.new(name);
  endfunction
  virtual task body();
    i3c_ibi_target_tx_mdb_payload_vseq content_vseq;

    super.body();
    content_vseq = i3c_ibi_target_tx_mdb_payload_vseq::type_id::create(
      "content_vseq");
    content_vseq.vseq_ctx = vseq_ctx;
    content_vseq.start(null);
    `uvm_info("IBI_MULTI_CONTENT",
              "Customer compatibility identity completed using canonical Target-TX multi-target then MDB/payload behavior",
              UVM_LOW)
  endtask
endclass

class i3c_ibi_controller_rx_multi_target_ordering_vseq extends
    i3c_ibi_controller_rx_multi_target_vseq;
  `uvm_object_utils(i3c_ibi_controller_rx_multi_target_ordering_vseq)
  function new(string name = "i3c_ibi_controller_rx_multi_target_ordering_vseq");
    super.new(name);
  endfunction
  virtual task body();
    super.body();
    `uvm_info("IBI_CTRL_MULTI_ORDERING",
              "Customer compatibility identity completed using canonical Controller-RX multi-target behavior",
              UVM_LOW)
  endtask
endclass

class i3c_ibi_controller_rx_multi_target_ack_nack_vseq extends
    i3c_ibi_controller_rx_multi_target_vseq;
  `uvm_object_utils(i3c_ibi_controller_rx_multi_target_ack_nack_vseq)
  function new(string name = "i3c_ibi_controller_rx_multi_target_ack_nack_vseq");
    super.new(name);
  endfunction
  virtual task body();
    i3c_ibi_controller_rx_policy_vseq policy_vseq;

    super.body();
    // The multi-target engine leaves this probe on the final serviced loser.
    // The following single-target policy engine uses the primary requester.
    vseq_ctx.cfg.vif.i3c_controller_expected_addr =
      vseq_ctx.cfg.ibi_target_addr;
    policy_vseq = i3c_ibi_controller_rx_policy_vseq::type_id::create(
      "policy_vseq");
    policy_vseq.vseq_ctx = vseq_ctx;
    policy_vseq.start(null);
    `uvm_info("IBI_CTRL_MULTI_ACK_NACK",
              "Customer compatibility identity completed using canonical Controller-RX multi-target then policy behavior",
              UVM_LOW)
  endtask
endclass

class i3c_ibi_controller_rx_multi_target_queue_pressure_vseq extends
    i3c_ibi_controller_rx_multi_target_vseq;
  `uvm_object_utils(i3c_ibi_controller_rx_multi_target_queue_pressure_vseq)
  function new(string name = "i3c_ibi_controller_rx_multi_target_queue_pressure_vseq");
    super.new(name);
  endfunction
  virtual task body();
    i3c_ibi_controller_rx_fifo_irq_vseq queue_vseq;

    super.body();
    // Restore the single-target SVA expectation before queue-pressure traffic.
    vseq_ctx.cfg.vif.i3c_controller_expected_addr =
      vseq_ctx.cfg.ibi_target_addr;
    queue_vseq = i3c_ibi_controller_rx_fifo_irq_vseq::type_id::create(
      "queue_vseq");
    queue_vseq.vseq_ctx = vseq_ctx;
    queue_vseq.start(null);
    `uvm_info("IBI_CTRL_MULTI_QUEUE",
              "Customer compatibility identity completed using canonical Controller-RX multi-target then FIFO/IRQ behavior",
              UVM_LOW)
  endtask
endclass

class i3c_ibi_multi_target_recovery_vseq extends
    i3c_ibi_controller_rx_multi_target_vseq;
  `uvm_object_utils(i3c_ibi_multi_target_recovery_vseq)
  function new(string name = "i3c_ibi_multi_target_recovery_vseq");
    super.new(name);
  endfunction
  virtual task body();
    i3c_ibi_controller_rx_recovery_cleanup_vseq recovery_vseq;

    super.body();
    // Recovery cleanup returns to the primary Target after multi-target
    // arbitration has updated the expected address for each serviced loser.
    vseq_ctx.cfg.vif.i3c_controller_expected_addr =
      vseq_ctx.cfg.ibi_target_addr;
    recovery_vseq =
      i3c_ibi_controller_rx_recovery_cleanup_vseq::type_id::create(
        "recovery_vseq");
    recovery_vseq.vseq_ctx = vseq_ctx;
    recovery_vseq.start(null);
    `uvm_info("IBI_MULTI_RECOVERY",
              "Customer compatibility identity completed using canonical Controller-RX multi-target then recovery-cleanup behavior",
              UVM_LOW)
  endtask
endclass

`endif
