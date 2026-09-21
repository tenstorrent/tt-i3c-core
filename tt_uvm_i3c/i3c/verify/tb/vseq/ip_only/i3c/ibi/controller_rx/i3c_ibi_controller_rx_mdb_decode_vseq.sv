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
// File        : i3c_ibi_controller_rx_mdb_decode_vseq.sv
// Description : Controller-RX MDB group decode virtual sequence.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-05
//
// *****************************************************************************

`ifndef I3C_IBI_CONTROLLER_RX_MDB_DECODE_VSEQ_SV
`define I3C_IBI_CONTROLLER_RX_MDB_DECODE_VSEQ_SV

typedef enum bit [2:0] {
  I3C_MDB_USER_DEFINED = 3'b000,
  I3C_MDB_ERROR        = 3'b001,
  I3C_MDB_MIPI         = 3'b010,
  I3C_MDB_NON_MIPI     = 3'b011,
  I3C_MDB_TIMING       = 3'b100,
  I3C_MDB_PENDING_READ = 3'b101,
  I3C_MDB_RESERVED_110 = 3'b110,
  I3C_MDB_RESERVED_111 = 3'b111
} i3c_mdb_group_e;

// Common Controller-RX MDB machinery used by the decode and pending-read
// scenarios. Expected content comes from UVM Target stimulus; the HCI record
// is observed independently through AXI and correlated by the scoreboard.
class i3c_ibi_controller_mdb_base_vseq extends i3c_ibi_base_vseq;
  `uvm_object_utils(i3c_ibi_controller_mdb_base_vseq)

  function new(string name = "i3c_ibi_controller_mdb_base_vseq");
    super.new(name);
  endfunction

`ifdef I3C_DV_NATIVE_RTL
`ifdef I3C_DV_NATIVE_RAL
  protected function i3c_mdb_group_e classify_mdb(bit [7:0] mdb);
    return i3c_mdb_group_e'(mdb[7:5]);
  endfunction

  protected function string mdb_group_name(i3c_mdb_group_e group);
    case (group)
      I3C_MDB_USER_DEFINED: return "user-defined/generic";
      I3C_MDB_ERROR:        return "error";
      I3C_MDB_MIPI:         return "MIPI-defined";
      I3C_MDB_NON_MIPI:     return "non-MIPI";
      I3C_MDB_TIMING:       return "timing/vendor";
      I3C_MDB_PENDING_READ: return "pending-read notification";
      default:                  return "reserved";
    endcase
  endfunction

  protected task wait_target_operation_done(ref bit done,
                                             input string operation);
    if (done)
      return;
    repeat (vseq_ctx.cfg.ibi_timeout_cycles) begin
      @(posedge vseq_ctx.cfg.vif.clk);
      if (done)
        return;
    end
    `uvm_fatal("IBI_MDB_BUS_TIMEOUT",
               $sformatf("%s: UVM Target operation did not complete",
                         operation))
  endtask

  protected task run_software_pending_read(
      input int unsigned transaction_id,
      input byte unsigned expected_data[$],
      input i3c_controller_hci_helper #(
        TB_ADDR_WIDTH, TB_DATA_WIDTH) hci_helper,
      input string operation);
    i3c_target_private_read_seq target_read_seq;
    byte unsigned actual_data[$];
    bit target_done;
    bit content_mismatch;

    if (expected_data.size() == 0)
      `uvm_fatal("IBI_PRN_SW_DATA",
                 $sformatf("%s: software follow-up needs response data",
                           operation))
    wait_bus_idle({operation, ": wait for Private Read bus idle"});
    target_read_seq = i3c_target_private_read_seq::type_id::create(
      $sformatf("software_pending_read_%0d", transaction_id));
    target_read_seq.target_addr = vseq_ctx.cfg.ibi_target_addr;
    foreach (expected_data[index])
      target_read_seq.response_data.push_back(expected_data[index]);

    target_done = 1'b0;
    fork : software_pending_read_target
      begin
        target_read_seq.start(vseq_ctx.i3c_sqr);
        target_done = target_read_seq.transfer_done;
      end
    join_none
    // Let the Device sequencer deliver its address-wait item before the HCI
    // command can create START; this avoids a testbench scheduling race.
    @(posedge vseq_ctx.cfg.vif.clk);
    hci_helper.issue_dat_private_read(
      vseq_ctx.cfg.ibi_controller_dat_index, expected_data.size(),
      transaction_id[3:0], this);
    wait_target_operation_done(target_done, operation);
    disable software_pending_read_target;

    if (!target_read_seq.address_matched)
      `uvm_error("IBI_PRN_SW_ADDRESS",
                 $sformatf("%s: expected DA=0x%02h/RnW=1, observed DA=0x%02h/RnW=%0b",
                           operation, vseq_ctx.cfg.ibi_target_addr,
                           target_read_seq.observed_addr,
                           target_read_seq.observed_dir))
    hci_helper.read_rx_data(expected_data.size(), actual_data, this);
    content_mismatch = actual_data.size() != expected_data.size();
    if (!content_mismatch) begin
      foreach (expected_data[index]) begin
        if (actual_data[index] !== expected_data[index]) begin
          content_mismatch = 1'b1;
          break;
        end
      end
    end
    if (content_mismatch)
      `uvm_error("IBI_PRN_SW_CONTENT",
                 $sformatf("%s: expected/read RX byte count=%0d/%0d",
                           operation, expected_data.size(),
                           actual_data.size()))
  endtask

  protected function void check_hci_record(
      input string operation,
      input bit [7:0] expected_mdb,
      input byte unsigned expected_payload[$],
      input bit [2:0] expected_status_type,
      input bit [31:0] descriptor,
      input byte unsigned actual_data[$]);
    int unsigned expected_length;
    bit content_mismatch;

    expected_length = 1 + expected_payload.size();
    if (descriptor[15:8] !== {vseq_ctx.cfg.ibi_target_addr, 1'b1})
      `uvm_error("IBI_MDB_HCI_ID",
                 $sformatf("%s: expected {DA,RnW} IBI_ID=0x%02h actual=0x%02h",
                           operation,
                           {vseq_ctx.cfg.ibi_target_addr, 1'b1},
                           descriptor[15:8]))
    if ((descriptor[31] !== 1'b0) ||
        (descriptor[30] !== 1'b0) ||
        (descriptor[29:27] !== expected_status_type) ||
        (descriptor[25] !== 1'b0) ||
        (descriptor[24] !== 1'b1) ||
        (descriptor[23:16] !== 8'h00))
      `uvm_error("IBI_MDB_HCI_STATUS",
                 $sformatf("%s: expected ACK/no-error type=%03b final descriptor, actual=0x%08h",
                           operation, expected_status_type, descriptor))
    if ((descriptor[7:0] !== expected_length[7:0]) ||
        (actual_data.size() != expected_length))
      `uvm_error("IBI_MDB_HCI_LENGTH",
                 $sformatf("%s: expected length=%0d descriptor=%0d data=%0d",
                           operation, expected_length, descriptor[7:0],
                           actual_data.size()))

    content_mismatch = actual_data.size() != expected_length;
    if (!content_mismatch && (actual_data[0] !== expected_mdb))
      content_mismatch = 1'b1;
    if (!content_mismatch) begin
      foreach (expected_payload[index]) begin
        if (actual_data[index + 1] !== expected_payload[index]) begin
          content_mismatch = 1'b1;
          break;
        end
      end
    end
    if (content_mismatch)
      `uvm_error("IBI_MDB_HCI_CONTENT",
                 $sformatf("%s: expected MDB=0x%02h payload=%0d bytes; actual=%0d bytes",
                           operation, expected_mdb,
                           expected_payload.size(), actual_data.size()))
  endfunction

  protected task run_mdb_case(
      input int unsigned case_index,
      input bit [7:0] mdb,
      input i3c_mdb_group_e expected_group,
      input i3c_controller_hci_helper #(
        TB_ADDR_WIDTH, TB_DATA_WIDTH) hci_helper);
    i3c_target_send_ibi_seq target_seq;
    byte unsigned no_payload[$];
    byte unsigned pending_read_data[$];
    byte unsigned hci_data[$];
    bit [31:0] descriptor;
    bit [31:0] interrupt_status;
    bit target_done;
    string operation;

    operation = $sformatf("MDB case[%0d] %s (0x%02h)", case_index,
                          mdb_group_name(expected_group), mdb);
    if (classify_mdb(mdb) != expected_group)
      `uvm_fatal("IBI_MDB_VECTOR",
                 $sformatf("%s has group %03b, not expected %03b",
                           operation, mdb[7:5], expected_group))

    wait_bus_idle({operation, ": wait for idle bus"});
    hci_helper.wait_bus_available(this);
    target_seq = i3c_target_send_ibi_seq::type_id::create(
      $sformatf("mdb_target_seq_%0d", case_index));
    target_seq.target_addr = vseq_ctx.cfg.ibi_target_addr;
    target_seq.mdb_present = 1'b1;
    target_seq.mdb = mdb;
    target_seq.payload.delete();
    // A real Target-initiated IBI owns START. The DUT Controller must detect
    // SDA falling during bus-available, take ownership of SCL and ACK/NACK the
    // Target address; no unrelated Controller command is used as a trigger.
    target_seq.start_on_idle = 1'b1;

    target_done = 1'b0;
    vseq_ctx.cfg.ibi_controller_attempt_cases++;
    vseq_ctx.cfg.ibi_bus_state = 2'd0;
    vseq_ctx.cfg.vif.i3c_controller_expected_ack = 1'b1;
    fork : mdb_target_driver
      begin
        target_seq.start(vseq_ctx.i3c_sqr);
        target_done = 1'b1;
      end
    join_none

    wait_target_operation_done(target_done, operation);
    disable mdb_target_driver;
    if (!target_seq.observed_ack)
      `uvm_fatal("IBI_MDB_NACK",
                 $sformatf("%s: DUT Controller NACKed the IBI", operation))

    wait_irq(1'b1, {operation, ": wait for HCI IBI IRQ"});
    hci_helper.read_ibi_status(interrupt_status, this);
    if (!interrupt_status[2])
      `uvm_error("IBI_MDB_IRQ_STATUS",
                 $sformatf("%s: IRQ asserted without IBI threshold status: 0x%08h",
                           operation, interrupt_status))
    hci_helper.read_ibi_record(descriptor, hci_data, this);
    check_hci_record(operation, mdb, no_payload, 3'b000,
                     descriptor, hci_data);
    wait_scoreboard_completion(
      case_index + 1,
      {operation, ": wait for Controller scoreboard correlation"});
    wait_irq(1'b0, {operation, ": wait for IRQ clear after drain"});
    hci_helper.read_ibi_status(interrupt_status, this);
    if (interrupt_status[2])
      `uvm_error("IBI_MDB_IRQ_CLEAR",
                 $sformatf("%s: threshold status remained set after drain: 0x%08h",
                           operation, interrupt_status))

    // ACKing group 101 creates a Pending Read contract. Auto-Command is kept
    // disabled in this decode-only test, so the UVM host software explicitly
    // performs the required Private Read after consuming the regular IBI.
    if (expected_group == I3C_MDB_PENDING_READ) begin
      pending_read_data.push_back(8'hd3);
      run_software_pending_read(case_index, pending_read_data, hci_helper,
                                {operation, ": software follow-up"});
    end
  endtask
`endif
`endif
endclass : i3c_ibi_controller_mdb_base_vseq

class i3c_ibi_controller_rx_mdb_decode_vseq extends
    i3c_ibi_controller_mdb_base_vseq;
  `uvm_object_utils(i3c_ibi_controller_rx_mdb_decode_vseq)

  localparam int unsigned MDB_CASE_COUNT = 4;

  function new(string name = "i3c_ibi_controller_rx_mdb_decode_vseq");
    super.new(name);
  endfunction

  virtual task body();
    super.body();
    if (!vseq_ctx.cfg.has_rtl)
      `uvm_fatal("IBI_MDB_MODE",
                 "MDB decode test requires native I3C RTL mode")
    if (vseq_ctx.cfg.ibi_dut_role != I3C_IBI_DUT_CONTROLLER)
      `uvm_fatal("IBI_MDB_ROLE",
                 "MDB decode test requires DUT-controller role")

`ifdef I3C_DV_NATIVE_RTL
`ifdef I3C_DV_NATIVE_RAL
    begin
      i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
        hci_helper;

      hci_helper = vseq_ctx.i3c_controller_hci_helper;
      if (hci_helper == null)
        `uvm_fatal("IBI_MDB_HELPER",
                   "Controller HCI helper is not available")

      // Auto-Command is deliberately disabled here (mask=0/value=1 by the
      // helper default) so this test isolates MDB decode and HCI recording.
      // The group-101 case performs its required software follow-up Read after
      // the regular IBI record has been checked.
      hci_helper.initialize_controller_ibi(
        vseq_ctx.cfg.ibi_target_addr,
        vseq_ctx.cfg.ibi_controller_dat_index, this);
      wait_irq(1'b0, "verify MDB decode IRQ initially low");

      // Values follow the public MIPI MDB registry. Pending Read is last so no
      // later IBI can overtake its software follow-up transaction.
      run_mdb_case(0, 8'h00, I3C_MDB_USER_DEFINED, hci_helper);
      run_mdb_case(1, 8'h2e, I3C_MDB_ERROR, hci_helper);
      run_mdb_case(2, 8'h80, I3C_MDB_TIMING, hci_helper);
      run_mdb_case(3, 8'hb0, I3C_MDB_PENDING_READ, hci_helper);

      if ((vseq_ctx.cfg.ibi_controller_expected_events != MDB_CASE_COUNT) ||
          (vseq_ctx.cfg.ibi_controller_actual_events != MDB_CASE_COUNT))
        `uvm_fatal("IBI_MDB_EVENT_COUNT",
                   $sformatf("expected/actual Controller events must be %0d/%0d, got %0d/%0d",
                             MDB_CASE_COUNT, MDB_CASE_COUNT,
                             vseq_ctx.cfg.ibi_controller_expected_events,
                             vseq_ctx.cfg.ibi_controller_actual_events))
      if (vseq_ctx.cfg.ibi_sb_mismatch_count != 0)
        `uvm_error("IBI_MDB_SCOREBOARD",
                   $sformatf("Controller MDB scoreboard mismatches=%0d",
                             vseq_ctx.cfg.ibi_sb_mismatch_count))
      if (vseq_ctx.cfg.ibi_cov_completion_samples < MDB_CASE_COUNT)
        `uvm_fatal("IBI_MDB_COVERAGE",
                   $sformatf("expected at least %0d completion samples, got %0d",
                             MDB_CASE_COUNT,
                             vseq_ctx.cfg.ibi_cov_completion_samples))

      `uvm_info("IBI_MDB_DECODE",
                "PASS: user-defined, error, timing/vendor and pending-read MDB groups matched their HCI records",
                UVM_LOW)
    end
`else
    `uvm_fatal("IBI_MDB_RAL_BUILD",
               "MDB decode test requires I3C_DV_NATIVE_RAL")
`endif
`else
    `uvm_fatal("IBI_MDB_RTL_BUILD",
               "MDB decode test requires I3C_DV_NATIVE_RTL")
`endif
  endtask
endclass : i3c_ibi_controller_rx_mdb_decode_vseq

`endif // I3C_IBI_CONTROLLER_RX_MDB_DECODE_VSEQ_SV
