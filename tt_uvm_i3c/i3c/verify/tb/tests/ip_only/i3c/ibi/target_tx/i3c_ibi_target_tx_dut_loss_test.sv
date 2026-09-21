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
// File        : i3c_ibi_target_tx_dut_loss_test.sv
// Description : DUT-Target loses IBI arbitration and retries its descriptor.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-12
//
// *****************************************************************************

`ifndef I3C_IBI_TARGET_TX_DUT_LOSS_TEST_SV
`define I3C_IBI_TARGET_TX_DUT_LOSS_TEST_SV

class i3c_ibi_target_tx_dut_loss_test extends i3c_ibi_base_test;
  `uvm_component_utils(i3c_ibi_target_tx_dut_loss_test)

  function new(string name = "i3c_ibi_target_tx_dut_loss_test",
               uvm_component parent = null);
    super.new(name, parent);
    // Keep all three external Target agents available so per-entry stimulus
    // can run two-, three-, or four-requester arbitration without changing
    // the compiled topology.
    controller_target_count = 4;
  endfunction

  protected function bit [6:0] select_nth_lower_target_addr(
      bit [6:0] dut_addr, int unsigned ordinal);
    bit [6:0] candidate;
    int unsigned legal_index;

    legal_index = 0;
    for (int raw = int'(dut_addr) - 1; raw >= 8; raw--) begin
      candidate = raw[6:0];
      if (!is_reserved_dynamic_addr(candidate)) begin
        legal_index++;
        if (legal_index == ordinal)
          return candidate;
      end
    end
    `uvm_fatal("IBI_DUT_LOSS_ADDR",
               $sformatf("No legal lower Target address ordinal %0d below DUT 0x%02h",
                         ordinal, dut_addr))
    return dut_addr;
  endfunction

  protected function bit [6:0] select_lower_target_addr(bit [6:0] dut_addr);
    bit [6:0] candidate;

    for (int raw = int'(dut_addr) - 1; raw >= 8; raw--) begin
      candidate = raw[6:0];
      if (!is_reserved_dynamic_addr(candidate))
        return candidate;
    end
    `uvm_fatal("IBI_DUT_LOSS_ADDR",
               $sformatf("No legal competing Target address exists below DUT address 0x%02h",
                         dut_addr))
    return dut_addr;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    int unsigned competitor_plusarg;
    int unsigned requester_count_plusarg;
    string arbitration_context;

    super.build_phase(phase);
    if (cfg.ibi_dut_role != I3C_IBI_DUT_TARGET)
      `uvm_fatal("IBI_DUT_LOSS_ROLE",
                 "DUT-loss test requires DUT-Target role")
    requester_count_plusarg = 2;
    void'($value$plusargs("IBI_DUT_LOSS_REQUESTERS=%0d",
                          requester_count_plusarg));
    if (!(requester_count_plusarg inside {[2:4]}))
      `uvm_fatal("IBI_DUT_LOSS_REQUESTERS",
                 "IBI_DUT_LOSS_REQUESTERS must be in [2:4]")
    cfg.ibi_requester_count = requester_count_plusarg;
    arbitration_context = "bus_available";
    void'($value$plusargs("IBI_DUT_ARB_CONTEXT=%s", arbitration_context));
    case (arbitration_context)
      "bus_available": cfg.ibi_bus_state = 2'd0;
      "bus_start":     cfg.ibi_bus_state = 2'd1;
      "after_xfer":    cfg.ibi_bus_state = 2'd2;
      default:
        `uvm_fatal("IBI_DUT_ARB_CONTEXT",
                   $sformatf("Unsupported IBI_DUT_ARB_CONTEXT=%s",
                             arbitration_context))
    endcase
    if ($test$plusargs("IBI_ARB_PRECEDE_PRIVATE_WRITE") &&
        (cfg.ibi_bus_state != 2'd0))
      `uvm_fatal("IBI_DUT_ARB_PRECURSOR",
                 "IBI_ARB_PRECEDE_PRIVATE_WRITE publishes its own checked after-transfer attempt; the following arbitration must use bus_available context")
    if ($test$plusargs("IBI_ARB_DURING_PRIVATE_WRITE") &&
        (arbitration_context != "bus_available"))
      `uvm_fatal("IBI_DUT_ARB_DURING_TRANSFER",
                 "IBI_ARB_DURING_PRIVATE_WRITE derives after-transfer context from the observed Private Write; do not override IBI_DUT_ARB_CONTEXT")
    // A contested DUT winner can be NACKed before the retained descriptor
    // succeeds on its retry. Enable transaction-preserving observer tracking
    // only for that per-entry mode so the intermediate FAILURE_NACK closes
    // coverage without being compared as the terminal scoreboard result.
    if ($test$plusargs("IBI_DUT_WIN_NACK_RETRY")) begin
      cfg.ibi_retry_tracking = 1'b1;
      cfg.ibi_retry_count = 1;
    end
    if ($test$plusargs("IBI_CORRELATE_FAILURE_ADDR_ARB")) begin
      cfg.ibi_retry_tracking = 1'b1;
      cfg.ibi_retry_count = 1;
      cfg.ibi_address_arb_status_correlation = 1'b1;
    end
    // Slot 1 is deliberately the lowest external address and therefore the
    // real winner. Remaining slots are ordered below the DUT but above slot 1.
    cfg.ibi_secondary_target_addr = select_nth_lower_target_addr(
      cfg.ibi_target_addr, requester_count_plusarg - 1);
    if (requester_count_plusarg >= 3)
      cfg.ibi_target_addr_by_slot[2] = select_nth_lower_target_addr(
        cfg.ibi_target_addr, requester_count_plusarg - 2);
    if (requester_count_plusarg >= 4)
      cfg.ibi_target_addr_by_slot[3] = select_nth_lower_target_addr(
        cfg.ibi_target_addr, 1);
    if ($value$plusargs("IBI_LOWER_TARGET_ADDR=%h", competitor_plusarg)) begin
      if ((competitor_plusarg > 7'h77) ||
          is_reserved_dynamic_addr(competitor_plusarg[6:0]) ||
          (competitor_plusarg[6:0] >= cfg.ibi_target_addr) ||
          ((requester_count_plusarg >= 3) &&
           (competitor_plusarg[6:0] >= cfg.ibi_target_addr_by_slot[2])))
        `uvm_fatal("IBI_LOWER_TARGET_ADDR",
                   $sformatf("Competing Target 0x%0h must be legal, below DUT 0x%02h, and remain the lowest requester",
                             competitor_plusarg, cfg.ibi_target_addr))
      cfg.ibi_secondary_target_addr = competitor_plusarg[6:0];
    end
    cfg.ibi_source_instance_by_addr[cfg.ibi_secondary_target_addr] = 3'd1;
    if (requester_count_plusarg >= 3)
      cfg.ibi_source_instance_by_addr[cfg.ibi_target_addr_by_slot[2]] = 3'd2;
    if (requester_count_plusarg >= 4)
      cfg.ibi_source_instance_by_addr[cfg.ibi_target_addr_by_slot[3]] = 3'd3;
    cfg.ibi_filter_external_target_observations = 1'b1;
  endfunction

  virtual function i3c_base_vseq create_vseq();
    return i3c_ibi_target_tx_dut_loss_vseq::type_id::create("vseq");
  endfunction
endclass : i3c_ibi_target_tx_dut_loss_test

`endif
