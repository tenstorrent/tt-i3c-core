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
// File        : smc_i3c_ibi_base_vseq.sv
// Description : Base virtual sequence for I3C IBI scenarios.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_BASE_VSEQ_SV
`define SMC_I3C_IBI_BASE_VSEQ_SV

class smc_i3c_ibi_base_vseq extends smc_peripherals_base_vseq;
  `uvm_object_utils(smc_i3c_ibi_base_vseq)

  localparam bit [1:0] STBY_CR_TARGET_MODE = 2'b10;
  localparam int unsigned BCR_IBI_CAPABLE_BIT = 1;
  localparam int unsigned BCR_MDB_CAPABLE_BIT = 2;

  function new(string name = "smc_i3c_ibi_base_vseq");
    super.new(name);
  endfunction

`ifdef SMC_USE_I3C_RAL
  protected task write_register_bytes(
      input uvm_reg register_handle,
      input uvm_reg_data_t value,
      input bit [(TB_DATA_WIDTH/8)-1:0] strobe,
      input string operation);
    smc_i3c_csr_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH) csr_helper;
    longint unsigned address;
    longint unsigned offset;
    bit [1:0] response;

    csr_helper = get_i3c_csr_helper();
    address = register_handle.get_address(get_i3c_ral_model().default_map);
    if (address < csr_helper.base_address)
      `uvm_fatal("IBI_RAL_ADDRESS",
                 $sformatf("%s: register address 0x%0h is below I3C base 0x%0h",
                           operation, address, csr_helper.base_address))
    offset = address - csr_helper.base_address;
    csr_helper.write_csr(offset, value[TB_DATA_WIDTH-1:0], strobe,
                         response, this);
    if (response != 2'b00)
      `uvm_fatal("IBI_RAL_WRITE",
                 $sformatf("%s failed at address 0x%0h with AXI response=%0b",
                           operation, address, response))
  endtask

  // Avoid UVM field-RMW when the generated model marks a field as not
  // individually accessible. Only byte lanes containing the field are
  // written, and unsafe write-triggered siblings in those lanes are rejected.
  protected task update_rw_field_bytes(
      input uvm_reg_field field_handle,
      input uvm_reg_data_t value,
      input string operation);
    uvm_reg register_handle;
    uvm_reg_data_t register_value;
    uvm_reg_field sibling_fields[$];
    uvm_status_e status;
    bit [(TB_DATA_WIDTH/8)-1:0] strobe;
    int unsigned lsb;
    int unsigned width;

    if (field_handle.get_access(get_i3c_ral_model().default_map) != "RW")
      `uvm_fatal("IBI_RAL_ACCESS",
                 $sformatf("%s requires an RW field, got %s",
                           operation,
                           field_handle.get_access(
                             get_i3c_ral_model().default_map)))
    register_handle = field_handle.get_parent();
    lsb = field_handle.get_lsb_pos();
    width = field_handle.get_n_bits();
    if ((lsb + width) > TB_DATA_WIDTH)
      `uvm_fatal("IBI_RAL_WIDTH",
                 $sformatf("%s: field [%0d +: %0d] exceeds TB data width %0d",
                           operation, lsb, width, TB_DATA_WIDTH))

    register_handle.read(status, register_value, UVM_FRONTDOOR,
                         get_i3c_ral_model().default_map, this);
    if (status != UVM_IS_OK)
      `uvm_fatal("IBI_RAL_READ",
                 $sformatf("%s parent-register read failed with status=%s",
                           operation, status.name()))

    strobe = '0;
    for (int unsigned bit_index = 0; bit_index < width; bit_index++) begin
      register_value[lsb + bit_index] = value[bit_index];
      strobe[(lsb + bit_index) / 8] = 1'b1;
    end

    register_handle.get_fields(sibling_fields);
    foreach (sibling_fields[field_index]) begin
      string sibling_access;
      int unsigned sibling_lsb;
      int unsigned sibling_width;
      bit shares_written_lane;

      if (sibling_fields[field_index] == field_handle)
        continue;
      sibling_access = sibling_fields[field_index].get_access(
        get_i3c_ral_model().default_map);
      sibling_lsb = sibling_fields[field_index].get_lsb_pos();
      sibling_width = sibling_fields[field_index].get_n_bits();
      shares_written_lane = 1'b0;
      for (int unsigned bit_index = 0;
           bit_index < sibling_width; bit_index++) begin
        if (strobe[(sibling_lsb + bit_index) / 8])
          shares_written_lane = 1'b1;
      end
      if (shares_written_lane &&
          (sibling_access != "RW") && (sibling_access != "RO"))
        `uvm_fatal("IBI_RAL_SIDE_EFFECT",
                   $sformatf("%s shares a written byte lane with %s field %s",
                             operation, sibling_access,
                             sibling_fields[field_index].get_full_name()))
    end
    write_register_bytes(register_handle, register_value, strobe, operation);
  endtask

  // W1C must be a direct one-write operation. uvm_reg_field::write() may
  // implement field access as parent-register RMW and clear unrelated status
  // bits that happened to read as one.
  protected task clear_w1c_field(
      input uvm_reg_field field_handle,
      input uvm_reg_data_t clear_value,
      input string operation);
    uvm_reg_data_t write_value;
    bit [(TB_DATA_WIDTH/8)-1:0] strobe;
    int unsigned lsb;
    int unsigned width;

    if (field_handle.get_access(get_i3c_ral_model().default_map) != "W1C")
      `uvm_fatal("IBI_RAL_ACCESS",
                 $sformatf("%s requires a W1C field, got %s",
                           operation,
                           field_handle.get_access(
                             get_i3c_ral_model().default_map)))
    lsb = field_handle.get_lsb_pos();
    width = field_handle.get_n_bits();
    if ((lsb + width) > TB_DATA_WIDTH)
      `uvm_fatal("IBI_RAL_WIDTH",
                 $sformatf("%s: field [%0d +: %0d] exceeds TB data width %0d",
                           operation, lsb, width, TB_DATA_WIDTH))

    write_value = '0;
    strobe = '0;
    for (int unsigned bit_index = 0; bit_index < width; bit_index++) begin
      write_value[lsb + bit_index] = clear_value[bit_index];
      strobe[(lsb + bit_index) / 8] = 1'b1;
    end
    write_register_bytes(field_handle.get_parent(), write_value, strobe,
                         operation);
  endtask

  // Some command/reset fields share a register with other write-triggered
  // fields. Write only the requested value and byte lanes so a parent RMW
  // cannot replay a neighboring trigger. Callers must use this only where
  // zero is the documented inactive value for the other fields in the lane.
  protected task write_action_field(
      input uvm_reg_field field_handle,
      input uvm_reg_data_t value,
      input string operation);
    uvm_reg_data_t write_value;
    bit [(TB_DATA_WIDTH/8)-1:0] strobe;
    int unsigned lsb;
    int unsigned width;

    lsb = field_handle.get_lsb_pos();
    width = field_handle.get_n_bits();
    if ((lsb + width) > TB_DATA_WIDTH)
      `uvm_fatal("IBI_RAL_WIDTH",
                 $sformatf("%s: field [%0d +: %0d] exceeds TB data width %0d",
                           operation, lsb, width, TB_DATA_WIDTH))

    write_value = '0;
    strobe = '0;
    for (int unsigned bit_index = 0; bit_index < width; bit_index++) begin
      write_value[lsb + bit_index] = value[bit_index];
      strobe[(lsb + bit_index) / 8] = 1'b1;
    end
    write_register_bytes(field_handle.get_parent(), write_value, strobe,
                         operation);
  endtask

  protected task write_field(uvm_reg_field field_handle,
                             uvm_reg_data_t value,
                             string operation);
    string access;

    access = field_handle.get_access(get_i3c_ral_model().default_map);
    case (access)
      "RW":  update_rw_field_bytes(field_handle, value, operation);
      "W1C": clear_w1c_field(field_handle, value, operation);
      "WO":  write_action_field(field_handle, value, operation);
      default:
        `uvm_fatal("IBI_RAL_ACCESS",
                   $sformatf("%s does not support field access %s",
                             operation, access))
    endcase
  endtask

  protected task write_register(uvm_reg register_handle,
                                uvm_reg_data_t value,
                                string operation);
    uvm_status_e status;

    register_handle.write(status, value, UVM_FRONTDOOR,
                          get_i3c_ral_model().default_map, this);
    if (status != UVM_IS_OK)
      `uvm_fatal("IBI_RAL_WRITE",
                 $sformatf("%s failed with status=%s", operation, status.name()))
  endtask

  protected task read_field(input uvm_reg_field field_handle,
                            output uvm_reg_data_t value,
                            input string operation);
    uvm_reg register_handle;
    uvm_reg_data_t register_value;
    uvm_status_e status;
    int unsigned lsb;
    int unsigned width;

    register_handle = field_handle.get_parent();
    lsb = field_handle.get_lsb_pos();
    width = field_handle.get_n_bits();
    if ((lsb + width) > $bits(uvm_reg_data_t))
      `uvm_fatal("IBI_RAL_WIDTH",
                 $sformatf("%s: field [%0d +: %0d] exceeds RAL data width %0d",
                           operation, lsb, width, $bits(uvm_reg_data_t)))

    register_handle.read(status, register_value, UVM_FRONTDOOR,
                         get_i3c_ral_model().default_map, this);
    if (status != UVM_IS_OK)
      `uvm_fatal("IBI_RAL_READ",
                 $sformatf("%s failed with status=%s", operation, status.name()))

    value = '0;
    for (int unsigned bit_index = 0; bit_index < width; bit_index++)
      value[bit_index] = register_value[lsb + bit_index];
  endtask

  protected task expect_field(uvm_reg_field field_handle,
                              uvm_reg_data_t expected,
                              string operation);
    uvm_reg_data_t actual;

    read_field(field_handle, actual, operation);
    if (actual != expected)
      `uvm_fatal("IBI_FIELD_CHECK",
                 $sformatf("%s: expected=0x%0h actual=0x%0h",
                           operation, expected, actual))
  endtask

  protected task wait_field_value(uvm_reg_field field_handle,
                                  uvm_reg_data_t expected,
                                  string operation);
    uvm_reg_data_t actual;

    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      read_field(field_handle, actual, operation);
      if (actual == expected)
        return;
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_fatal("IBI_FIELD_TIMEOUT",
               $sformatf("%s: %s did not become 0x%0h",
                         operation, field_handle.get_full_name(), expected))
  endtask

`ifdef SMC_USE_I3C_RTL
  protected task initialize_target_ibi(smc_i3c_ral_model ral);
    smc_i3c_host_bus_idle_seq bus_idle_seq;
    smc_i3c_csr_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH) csr_helper;
    bit [TB_DATA_WIDTH-1:0] saved_host_control;
    bit [1:0] bus_enable_read_response;
    bit [1:0] bus_enable_write_response;
    uvm_reg_data_t bcr_var;
    uvm_reg_data_t bcr_fixed;
    uvm_reg_data_t queue_size;

    // The core gates START/STOP detection and bus-available timing with
    // HC_CONTROL.BUS_ENABLE, including while operating as a standby target.
    csr_helper = get_i3c_csr_helper();
    csr_helper.set_bus_enable(1'b1, saved_host_control,
                              bus_enable_read_response,
                              bus_enable_write_response, this);
    if ((bus_enable_read_response != 2'b00) ||
        (bus_enable_write_response != 2'b00))
      `uvm_fatal("IBI_BUS_ENABLE",
                 $sformatf("Failed to enable I3C bus monitor: read_resp=%0b write_resp=%0b",
                           bus_enable_read_response,
                           bus_enable_write_response))
    expect_field(ral.I3CBase.HC_CONTROL.BUS_ENABLE, 1,
                 "verify I3C bus monitor enable");

    update_rw_field_bytes(
      ral.I3C_EC.StdbyCtrlMode.STBY_CR_CONTROL.STBY_CR_ENABLE_INIT,
      STBY_CR_TARGET_MODE, "select standby-controller target mode");
    update_rw_field_bytes(
      ral.I3C_EC.StdbyCtrlMode.STBY_CR_CONTROL.TARGET_XACT_ENABLE,
      1, "enable target transactions");

    write_field(ral.I3C_EC.StdbyCtrlMode.STBY_CR_DEVICE_ADDR.STATIC_ADDR_VALID,
                0, "invalidate static address");
    write_field(ral.I3C_EC.StdbyCtrlMode.STBY_CR_DEVICE_ADDR.DYNAMIC_ADDR_VALID,
                0, "invalidate dynamic address before bus prime");

    // A NACKed private header followed by STOP starts the DUT bus-available
    // timer without making this IBI test depend on broadcast-CCC parity.
    bus_idle_seq = smc_i3c_host_bus_idle_seq::type_id::create("bus_idle_seq");
    bus_idle_seq.unassigned_addr = vseq_ctx.cfg.ibi_target_addr;
    bus_idle_seq.start(vseq_ctx.i3c_sqr);

    write_field(ral.I3C_EC.StdbyCtrlMode.STBY_CR_DEVICE_ADDR.DYNAMIC_ADDR,
                vseq_ctx.cfg.ibi_target_addr, "program target dynamic address");
    write_field(ral.I3C_EC.StdbyCtrlMode.STBY_CR_DEVICE_ADDR.DYNAMIC_ADDR_VALID,
                1, "validate target dynamic address");
    write_field(ral.I3C_EC.TTI.CONTROL.IBI_RETRY_NUM,
                vseq_ctx.cfg.ibi_retry_count, "set IBI retry count");
    write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 1, "enable DUT target IBI");

    read_field(ral.I3C_EC.StdbyCtrlMode.STBY_CR_DEVICE_CHAR.BCR_VAR,
               bcr_var, "read target BCR variable bits");
    read_field(ral.I3C_EC.StdbyCtrlMode.STBY_CR_DEVICE_CHAR.BCR_FIXED,
               bcr_fixed, "read target BCR fixed bits");
    vseq_ctx.cfg.ibi_bcr = {bcr_fixed[2:0], bcr_var[4:0]};
    vseq_ctx.cfg.ibi_bcr_valid = 1'b1;
    if (!vseq_ctx.cfg.ibi_bcr[BCR_IBI_CAPABLE_BIT])
      `uvm_fatal("IBI_BCR_CAPABILITY",
                 $sformatf("DUT target BCR 0x%02h does not advertise IBI capability",
                           vseq_ctx.cfg.ibi_bcr))
    if (!vseq_ctx.cfg.ibi_bcr[BCR_MDB_CAPABLE_BIT])
      `uvm_fatal("IBI_BCR_CAPABILITY",
                 $sformatf("MDB-only test requires BCR[2]=1, got BCR=0x%02h",
                           vseq_ctx.cfg.ibi_bcr))

    read_field(ral.I3C_EC.TTI.IBI_QUEUE_SIZE.IBI_QUEUE_SIZE,
               queue_size, "read IBI queue size");
    if (queue_size > 30)
      `uvm_fatal("IBI_QUEUE_SIZE",
                 $sformatf("IBI_QUEUE_SIZE encoding %0d cannot be decoded safely",
                           queue_size))
    vseq_ctx.cfg.ibi_queue_size_code = int'(queue_size);
    vseq_ctx.cfg.ibi_queue_size = 1 << (int'(queue_size) + 1);
    if (vseq_ctx.cfg.ibi_queue_size == 0)
      `uvm_fatal("IBI_QUEUE_SIZE",
                 "Decoded IBI queue capacity must be non-zero")
    `uvm_info("IBI_QUEUE_SIZE",
              $sformatf("IBI queue encoding=%0d capacity=%0d DWORDs",
                        vseq_ctx.cfg.ibi_queue_size_code,
                        vseq_ctx.cfg.ibi_queue_size),
              UVM_MEDIUM)
  endtask
`endif
`endif

  protected task wait_irq(bit expected, string operation);
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      if (vseq_ctx.cfg.vif.i3c_irq === expected)
        return;
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_fatal("IBI_IRQ_TIMEOUT",
               $sformatf("%s: i3c_irq did not become %0b", operation, expected))
  endtask

  protected task wait_scoreboard_completion(int unsigned expected_count,
                                             string operation);
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      if (vseq_ctx.cfg.ibi_sb_completion_count >= expected_count)
        return;
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_fatal("IBI_SB_TIMEOUT",
               $sformatf("%s: scoreboard completion count did not reach %0d (actual=%0d)",
                         operation, expected_count,
                         vseq_ctx.cfg.ibi_sb_completion_count))
  endtask

  protected task wait_bus_idle(string operation);
`ifdef SMC_USE_I3C_RTL
    for (int unsigned cycle = 0;
         cycle < vseq_ctx.cfg.ibi_timeout_cycles; cycle++) begin
      if ((vseq_ctx.cfg.i3c_vif.scl_i === 1'b1) &&
          (vseq_ctx.cfg.i3c_vif.sda_i === 1'b1))
        return;
      @(posedge vseq_ctx.cfg.vif.clk);
    end
    `uvm_fatal("IBI_BUS_IDLE_TIMEOUT",
               $sformatf("%s: I3C bus did not return idle", operation))
`else
    `uvm_fatal("IBI_BUS_IDLE_BUILD", "I3C bus wait requires DUT_MODE=rtl")
`endif
  endtask
endclass : smc_i3c_ibi_base_vseq

`endif // SMC_I3C_IBI_BASE_VSEQ_SV
