// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
// Authors: Huynh Pham Anh Duy, Thai Hai Dang
//
// Shared I3C IBI register-access tasks.

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

  // LAST_IBI_STATUS is RO. Do not rely on reading it to acknowledge IBI_DONE;
  // explicitly clear the architectural W1C source after the status is checked.
  protected task clear_target_ibi_done_irq(
      input smc_i3c_ral_model ral,
      input string operation);
    uvm_reg_data_t ibi_done_before;
    uvm_reg_data_t ibi_done_after;

    read_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE,
               ibi_done_before, {operation, ": read IBI_DONE before clear"});
    `uvm_info("IBI_IRQ_CLEANUP",
              $sformatf("%s: IBI_DONE before clear=0x%0h",
                        operation, ibi_done_before),
              UVM_MEDIUM)
    if (ibi_done_before != 0)
      clear_w1c_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE, 1,
                      {operation, ": clear IBI_DONE W1C"});
    read_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE,
               ibi_done_after, {operation, ": read IBI_DONE after clear"});
    `uvm_info("IBI_IRQ_CLEANUP",
              $sformatf("%s: IBI_DONE after clear=0x%0h",
                        operation, ibi_done_after),
              UVM_MEDIUM)
    if (ibi_done_after != 0)
      `uvm_fatal("IBI_IRQ_CLEANUP",
                 $sformatf("%s: IBI_DONE remained set after W1C (0x%0h)",
                           operation, ibi_done_after))
    wait_irq(1'b0, {operation, ": wait for IRQ low"});
  endtask

  // The caller pauses IBI at the address-detected boundary so the retained
  // descriptor cannot retry while software reads status and clears the FIFO.
  // Once the queue is proven empty, re-enable the Target for the next entry.
  protected task rearm_target_ibi_after_queue_reset(
      input smc_i3c_ral_model ral,
      input string operation);
    wait_bus_idle({operation, ": wait for idle bus"});
    expect_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 0,
                 {operation, ": verify Target IBI paused"});
    expect_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY, 1,
                 {operation, ": verify descriptor queue empty"});
    write_action_field(
      ral.I3C_EC.TTI.RESET_CONTROL.IBI_RETRY_CTR_RST, 1,
      {operation, ": reset exhausted IBI retry counter"});
    write_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 1,
                {operation, ": re-enable Target IBI"});
    expect_field(ral.I3C_EC.TTI.CONTROL.IBI_EN, 1,
                 {operation, ": verify Target IBI re-enabled"});
    repeat (2) @(posedge vseq_ctx.cfg.vif.clk);
  endtask

// IBI RAL access tasks included inside smc_i3c_ibi_base_vseq.
