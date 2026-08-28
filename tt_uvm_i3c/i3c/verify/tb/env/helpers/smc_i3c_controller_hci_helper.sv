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
// File        : smc_i3c_controller_hci_helper.sv
// Description : Helper API for I3C controller HCI.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef SMC_I3C_CONTROLLER_HCI_HELPER_SV
`define SMC_I3C_CONTROLLER_HCI_HELPER_SV

class smc_i3c_controller_hci_helper #(
    int ADDR_WIDTH = TB_ADDR_WIDTH,
    int DATA_WIDTH = TB_DATA_WIDTH
) extends uvm_object;
  `uvm_object_param_utils(
    smc_i3c_controller_hci_helper #(ADDR_WIDTH, DATA_WIDTH))

  smc_i3c_csr_helper #(ADDR_WIDTH, DATA_WIDTH) csr_helper;
  smc_i3c_ral_model ral_model;
  smc_peripherals_env_cfg cfg;

  function new(string name = "smc_i3c_controller_hci_helper");
    super.new(name);
  endfunction

  protected function longint unsigned address_to_offset(
      input uvm_reg_addr_t address,
      input string operation);
    if (csr_helper == null)
      `uvm_fatal("I3C_HCI_HELPER", "CSR helper is not configured")
    if (address < csr_helper.base_address)
      `uvm_fatal("I3C_HCI_ADDRESS",
                 $sformatf("%s address 0x%0h is below I3C base 0x%0h",
                           operation, address, csr_helper.base_address))
    return longint'(address - csr_helper.base_address);
  endfunction

  protected task read_register(
      input uvm_reg register_handle,
      output bit [DATA_WIDTH-1:0] value,
      input string operation,
      input uvm_sequence_base parent_seq = null);
    bit [1:0] response;
    longint unsigned offset;

    offset = address_to_offset(
      register_handle.get_address(ral_model.default_map), operation);
    csr_helper.read_csr(offset, value, response, parent_seq);
    if (response != 2'b00)
      `uvm_fatal("I3C_HCI_READ",
                 $sformatf("%s failed at offset 0x%0h response=%0b",
                           operation, offset, response))
  endtask

  protected task write_register(
      input uvm_reg register_handle,
      input bit [DATA_WIDTH-1:0] value,
      input string operation,
      input uvm_sequence_base parent_seq = null);
    bit [1:0] response;
    longint unsigned offset;

    offset = address_to_offset(
      register_handle.get_address(ral_model.default_map), operation);
    csr_helper.write_csr(offset, value, {(DATA_WIDTH/8){1'b1}},
                         response, parent_seq);
    if (response != 2'b00)
      `uvm_fatal("I3C_HCI_WRITE",
                 $sformatf("%s failed at offset 0x%0h response=%0b",
                           operation, offset, response))
  endtask

  protected task update_rw_field(
      input uvm_reg_field field_handle,
      input uvm_reg_data_t field_value,
      input string operation,
      input uvm_sequence_base parent_seq = null);
    uvm_reg register_handle;
    bit [DATA_WIDTH-1:0] register_value;
    int unsigned lsb;
    int unsigned width;

    register_handle = field_handle.get_parent();
    lsb = field_handle.get_lsb_pos();
    width = field_handle.get_n_bits();
    if ((lsb + width) > DATA_WIDTH)
      `uvm_fatal("I3C_HCI_FIELD",
                 $sformatf("%s field exceeds AXI data width", operation))
    read_register(register_handle, register_value,
                  {operation, " parent read"}, parent_seq);
    for (int unsigned index = 0; index < width; index++)
      register_value[lsb + index] = field_value[index];
    write_register(register_handle, register_value, operation, parent_seq);
  endtask

  protected task write_absolute_word(
      input uvm_reg_addr_t address,
      input bit [DATA_WIDTH-1:0] value,
      input string operation,
      input uvm_sequence_base parent_seq = null);
    bit [1:0] response;
    longint unsigned offset;

    offset = address_to_offset(address, operation);
    csr_helper.write_csr(offset, value, {(DATA_WIDTH/8){1'b1}},
                         response, parent_seq);
    if (response != 2'b00)
      `uvm_fatal("I3C_HCI_MEMORY_WRITE",
                 $sformatf("%s failed at offset 0x%0h response=%0b",
                           operation, offset, response))
  endtask

  protected task read_absolute_word(
      input uvm_reg_addr_t address,
      output bit [DATA_WIDTH-1:0] value,
      input string operation,
      input uvm_sequence_base parent_seq = null);
    bit [1:0] response;
    longint unsigned offset;

    offset = address_to_offset(address, operation);
    csr_helper.read_csr(offset, value, response, parent_seq);
    if (response != 2'b00)
      `uvm_fatal("I3C_HCI_MEMORY_READ",
                 $sformatf("%s failed at offset 0x%0h response=%0b",
                           operation, offset, response))
  endtask

  virtual task program_dat_entry(
      input int unsigned device_index,
      input bit [6:0] dynamic_addr,
      input bit [6:0] static_addr,
      input bit ibi_reject,
      input bit ibi_payload,
      input uvm_sequence_base parent_seq = null,
      // HCI compares (MDB & AUTOCMD_MASK) against AUTOCMD_VALUE. A zero
      // mask/value pair matches every MDB, so ordinary IBI tests explicitly
      // use value 1 with mask 0 to disable unintended Auto-Commands.
      input bit [7:0] autocmd_mask = 8'h00,
      input bit [7:0] autocmd_value = 8'h01,
      input bit [2:0] autocmd_mode = 3'b000);
    bit [63:0] dat_entry;
    bit [63:0] dat_readback;
    uvm_reg_addr_t entry_address;

    if ((ral_model == null) || (cfg == null))
      `uvm_fatal("I3C_HCI_DAT_CFG",
                 "RAL model and environment config are required")
    if (device_index >= ral_model.DAT.m_mem.get_size())
      `uvm_fatal("I3C_HCI_DAT_INDEX",
                 $sformatf("DAT index %0d exceeds table size %0d",
                           device_index, ral_model.DAT.m_mem.get_size()))

    // HCI DAT entry layout from I3CCSR.DAT.DAT_MEMORY. Addressing is derived
    // from the generated RAL map; only the standardized field encoding lives
    // here.
    dat_entry = '0;
    dat_entry[6:0] = static_addr;
    dat_entry[12] = ibi_payload;
    dat_entry[13] = ibi_reject;
    dat_entry[23:16] = {1'b0, dynamic_addr};
    dat_entry[31] = 1'b0; // I3C device, not legacy I2C.
    dat_entry[39:32] = autocmd_mask;
    dat_entry[47:40] = autocmd_value;
    dat_entry[50:48] = autocmd_mode;

    entry_address =
      ral_model.DAT.m_mem.get_address(device_index, ral_model.default_map);
    write_absolute_word(entry_address, dat_entry[31:0],
                        $sformatf("write DAT[%0d] low", device_index),
                        parent_seq);
    write_absolute_word(entry_address + (DATA_WIDTH/8), dat_entry[63:32],
                        $sformatf("write DAT[%0d] high", device_index),
                        parent_seq);
    read_absolute_word(entry_address, dat_readback[31:0],
                       $sformatf("read DAT[%0d] low", device_index),
                       parent_seq);
    read_absolute_word(entry_address + (DATA_WIDTH/8), dat_readback[63:32],
                       $sformatf("read DAT[%0d] high", device_index),
                       parent_seq);
    if (dat_readback !== dat_entry)
      `uvm_fatal("I3C_HCI_DAT_READBACK",
                 $sformatf("DAT[%0d] expected=0x%016h actual=0x%016h",
                           device_index, dat_entry, dat_readback))

    if (cfg.ibi_controller_dat_index_valid.exists(device_index) &&
        cfg.ibi_controller_dat_index_valid[device_index]) begin
      bit [6:0] previous_addr;

      previous_addr = cfg.ibi_controller_dat_addr_by_index[device_index];
      cfg.ibi_controller_dat_valid_by_addr[previous_addr] = 1'b0;
    end
    cfg.ibi_controller_dat_index_valid[device_index] = 1'b1;
    cfg.ibi_controller_dat_addr_by_index[device_index] = dynamic_addr;
    cfg.ibi_controller_dat_index = device_index;
    cfg.ibi_controller_dat_valid = 1'b1;
    cfg.ibi_controller_dat_dynamic_addr = dynamic_addr;
    cfg.ibi_controller_dat_ibi_reject = ibi_reject;
    cfg.ibi_controller_dat_ibi_payload = ibi_payload;
    cfg.ibi_controller_dat_valid_by_addr[dynamic_addr] = 1'b1;
    cfg.ibi_controller_dat_reject_by_addr[dynamic_addr] = ibi_reject;
    cfg.ibi_controller_dat_payload_by_addr[dynamic_addr] = ibi_payload;
    cfg.ibi_controller_dat_autocmd_mask_by_addr[dynamic_addr] =
      autocmd_mask;
    cfg.ibi_controller_dat_autocmd_value_by_addr[dynamic_addr] =
      autocmd_value;
    cfg.ibi_controller_dat_autocmd_mode_by_addr[dynamic_addr] =
      autocmd_mode;
  endtask

  virtual task initialize_controller_ibi(
      input bit [6:0] target_addr,
      input int unsigned device_index,
      input uvm_sequence_base parent_seq = null,
      input bit [7:0] autocmd_mask = 8'h00,
      input bit [7:0] autocmd_value = 8'h01,
      input bit [2:0] autocmd_mode = 3'b000);
    bit [DATA_WIDTH-1:0] saved_stby_control;
    bit [DATA_WIDTH-1:0] saved_pio_control;
    bit [DATA_WIDTH-1:0] saved_host_control;
    bit controller_ready;
    bit [1:0] read_response;
    bit [1:0] write_response;

    if ((csr_helper == null) || (ral_model == null) || (cfg == null))
      `uvm_fatal("I3C_HCI_INIT_CFG",
                 "Controller HCI helper is not fully configured")

    csr_helper.prepare_controller_for_private_write(
      saved_stby_control, saved_pio_control, controller_ready, parent_seq);
    if (!controller_ready)
      `uvm_fatal("I3C_HCI_CONTROLLER",
                 "Failed to configure active-controller timing and PIO mode")

    program_dat_entry(device_index, target_addr, '0,
                      1'b0, 1'b1, parent_seq,
                      autocmd_mask, autocmd_value, autocmd_mode);

    update_rw_field(
      ral_model.PIOControl.QUEUE_THLD_CTRL.IBI_STATUS_THLD,
      1, "set HCI IBI status threshold", parent_seq);
    update_rw_field(
      ral_model.PIOControl.PIO_INTR_STATUS_ENABLE.IBI_STATUS_THLD_STAT_EN,
      1, "enable HCI IBI threshold status", parent_seq);
    update_rw_field(
      ral_model.PIOControl.PIO_INTR_SIGNAL_ENABLE.IBI_STATUS_THLD_SIGNAL_EN,
      1, "enable HCI IBI threshold signal", parent_seq);

    csr_helper.set_bus_enable(1'b1, saved_host_control,
                              read_response, write_response, parent_seq);
    if ((read_response != 2'b00) || (write_response != 2'b00))
      `uvm_fatal("I3C_HCI_BUS_ENABLE",
                 $sformatf("BUS_ENABLE failed read=%0b write=%0b",
                           read_response, write_response))

  endtask

  virtual task enable_broadcast_header(
      input uvm_sequence_base parent_seq = null);
    bit [63:0] descriptor;

    // HCI Internal Control Command, MIPI command 2 with bit 12 set, enables
    // the broadcast address header for following I3C transfers.
    descriptor = '0;
    descriptor[12] = 1'b1;
    descriptor[11:8] = 4'h2;
    descriptor[2:0] = 3'b111;
    write_register(ral_model.PIOControl.COMMAND_PORT,
                   descriptor[31:0],
                   "enable I3C broadcast address header low",
                   parent_seq);
    write_register(ral_model.PIOControl.COMMAND_PORT,
                   descriptor[63:32],
                   "enable I3C broadcast address header high",
                   parent_seq);
  endtask

  virtual task issue_dat_private_write(
      input int unsigned device_index,
      input bit [7:0] payload,
      input bit [3:0] transaction_id,
      input uvm_sequence_base parent_seq = null);
    bit [63:0] descriptor;

    if (device_index >= ral_model.DAT.m_mem.get_size())
      `uvm_fatal("I3C_HCI_CMD_INDEX",
                 $sformatf("Command DAT index %0d exceeds table size %0d",
                           device_index, ral_model.DAT.m_mem.get_size()))

    // HCI immediate transfer through DAT. The command provides a real
    // Controller address phase for target IBI arbitration and preloads the
    // matching DAT policy before the IBI address is evaluated.
    descriptor = '0;
    descriptor[63:32] = {24'b0, payload};
    descriptor[31] = 1'b1; // TOC
    descriptor[30] = 1'b1; // WROC
    descriptor[25:23] = 3'd1;
    descriptor[20:16] = device_index[4:0];
    descriptor[6:3] = transaction_id;
    descriptor[2:0] = 3'b001;
    write_register(ral_model.PIOControl.COMMAND_PORT,
                   descriptor[31:0],
                   "issue DAT private write low",
                   parent_seq);
    write_register(ral_model.PIOControl.COMMAND_PORT,
                   descriptor[63:32],
                   "issue DAT private write high",
                   parent_seq);
  endtask

  virtual task issue_dat_private_read(
      input int unsigned device_index,
      input int unsigned byte_count,
      input bit [3:0] transaction_id,
      input uvm_sequence_base parent_seq = null);
    bit [63:0] descriptor;

    if (device_index >= ral_model.DAT.m_mem.get_size())
      `uvm_fatal("I3C_HCI_CMD_INDEX",
                 $sformatf("Command DAT index %0d exceeds table size %0d",
                           device_index, ral_model.DAT.m_mem.get_size()))
    if ((byte_count == 0) || (byte_count > 16'hffff))
      `uvm_fatal("I3C_HCI_READ_LENGTH",
                 $sformatf("Private Read byte count must be 1..65535, got %0d",
                           byte_count))

    // HCI Regular Transfer through DAT. WROC is clear because these IBI tests
    // verify the read on the bus and drain RX_DATA_PORT directly; leaving a
    // response descriptor behind would contaminate later queue checks.
    descriptor = '0;
    descriptor[63:48] = byte_count[15:0];
    descriptor[31] = 1'b1; // TOC: STOP after the Private Read.
    descriptor[30] = 1'b0; // WROC: no response descriptor requested.
    descriptor[29] = 1'b1; // RNW: Private Read.
    descriptor[28:26] = 3'b000; // SDR0.
    descriptor[20:16] = device_index[4:0];
    descriptor[15] = 1'b0; // Private transfer, not CCC.
    descriptor[6:3] = transaction_id;
    descriptor[2:0] = 3'b000; // Regular transfer, DAT format.
    write_register(ral_model.PIOControl.COMMAND_PORT,
                   descriptor[31:0],
                   "issue DAT private read low",
                   parent_seq);
    write_register(ral_model.PIOControl.COMMAND_PORT,
                   descriptor[63:32],
                   "issue DAT private read high",
                   parent_seq);
  endtask

  virtual task read_rx_data(
      input int unsigned byte_count,
      output byte unsigned data[$],
      input uvm_sequence_base parent_seq = null);
    bit [DATA_WIDTH-1:0] word;
    int unsigned word_count;

    if (byte_count == 0)
      `uvm_fatal("I3C_HCI_RX_LENGTH",
                 "RX data read requires at least one byte")
    word_count = (byte_count + (DATA_WIDTH/8) - 1) / (DATA_WIDTH/8);
    data.delete();
    for (int unsigned word_index = 0;
         word_index < word_count; word_index++) begin
      read_register(ral_model.PIOControl.RX_DATA_PORT, word,
                    $sformatf("read HCI RX data word %0d", word_index),
                    parent_seq);
      for (int unsigned byte_index = 0;
           byte_index < (DATA_WIDTH/8); byte_index++) begin
        if (data.size() < byte_count)
          data.push_back(word[8*byte_index +: 8]);
      end
    end
  endtask

  virtual task read_ibi_status(
      output bit [DATA_WIDTH-1:0] value,
      input uvm_sequence_base parent_seq = null);
    read_register(ral_model.PIOControl.PIO_INTR_STATUS, value,
                  "read HCI PIO interrupt status", parent_seq);
  endtask

  virtual task wait_bus_available(
      input uvm_sequence_base parent_seq = null);
    bit [DATA_WIDTH-1:0] t_aval;

    read_register(ral_model.I3C_EC.SoCMgmtIf.T_AVAL_REG, t_aval,
                  "read controller bus-available timing", parent_seq);
    for (int unsigned cycle = 0; cycle <= int'(t_aval); cycle++) begin
      if ((cfg.i3c_vif.scl_i !== 1'b1) ||
          (cfg.i3c_vif.sda_i !== 1'b1))
        `uvm_fatal("I3C_HCI_BUS_AVAILABLE",
                   $sformatf("I3C bus left idle while waiting T_AVAL=%0d",
                             t_aval))
      @(posedge cfg.vif.clk);
    end
  endtask

  virtual task read_ibi_record(
      output bit [31:0] descriptor,
      output byte unsigned data[$],
      input uvm_sequence_base parent_seq = null);
    bit [DATA_WIDTH-1:0] word;
    int unsigned data_length;
    int unsigned word_count;

    read_register(ral_model.PIOControl.IBI_PORT, word,
                  "read HCI IBI status descriptor", parent_seq);
    descriptor = word[31:0];
    data_length = descriptor[7:0];
    word_count = (data_length + 3) / 4;
    data.delete();
    for (int unsigned word_index = 0;
         word_index < word_count; word_index++) begin
      read_register(ral_model.PIOControl.IBI_PORT, word,
                    $sformatf("read HCI IBI data word %0d", word_index),
                    parent_seq);
      for (int unsigned byte_index = 0; byte_index < 4; byte_index++) begin
        if (data.size() < data_length)
          data.push_back(word[8*byte_index +: 8]);
      end
    end
  endtask
endclass : smc_i3c_controller_hci_helper

`endif // SMC_I3C_CONTROLLER_HCI_HELPER_SV
