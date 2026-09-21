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
// File        : i3c_ibi_bus_prime_tasks.svh
// Description : Shared I3C IBI bus-priming tasks.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-09-08
//
// *****************************************************************************

  // Every DUT-Target IBI test first sends a Controller-owned I3C header to
  // start the DUT bus-available timer. Check that this common bus-prime START
  // uses the I3C timing profile rather than silently falling back to I2C.
  protected task check_bus_prime_start_timing();
    realtime sda_fall_time;
    realtime scl_fall_time;
    realtime hold_time;
    int unsigned minimum_hold_ns;
    int unsigned minimum_addr_launch_ns;
    bit timing_done;
    bit first_scl_fall_seen;
    virtual i3c_if target_slot_vif;

    minimum_hold_ns = vseq_ctx.cfg.i3c_cfg.tc.i3c_tc.tHoldStart;
    minimum_addr_launch_ns =
      vseq_ctx.cfg.i3c_cfg.tc.i3c_tc.tAddrLaunchDelay;
    if ((vseq_ctx.cfg.i3c_vif.scl_i !== 1'b1) ||
        (vseq_ctx.cfg.i3c_vif.sda_i !== 1'b1))
      `uvm_fatal("IBI_BUS_PRIME_IDLE",
                 $sformatf("Bus-prime START began without idle SCL/SDA=1/1; observed %b/%b",
                           vseq_ctx.cfg.i3c_vif.scl_i,
                           vseq_ctx.cfg.i3c_vif.sda_i))

    timing_done = 1'b0;
    first_scl_fall_seen = 1'b0;
    fork : bus_prime_start_timeout_guard
      begin
        @(negedge vseq_ctx.cfg.i3c_vif.sda_i);
        sda_fall_time = $realtime;
        if (vseq_ctx.cfg.i3c_vif.scl_i !== 1'b1)
          `uvm_fatal("IBI_BUS_PRIME_START",
                     "Bus-prime SDA fell while SCL was not high")
        if ($isunknown({vseq_ctx.cfg.i3c_vif.scl_i,
                        vseq_ctx.cfg.i3c_vif.sda_i}))
          `uvm_fatal("IBI_BUS_PRIME_UNKNOWN",
                     "Bus-prime START observed X/Z on the resolved bus")
        if ((vseq_ctx.cfg.i3c_vif.host_sda_o !== 1'b0) ||
            (vseq_ctx.cfg.i3c_vif.host_sda_pp_en !== 1'b0))
          `uvm_fatal("IBI_BUS_PRIME_OWNER",
                     "UVM Controller did not own bus-prime SDA in open-drain mode")
        if (vseq_ctx.cfg.vif.i3c_sda_oe !== 1'b0)
          `uvm_fatal("IBI_BUS_PRIME_CONTENTION",
                     "DUT Target drove SDA during Controller bus-prime START")
        for (int unsigned slot = 1;
             slot < vseq_ctx.cfg.ibi_controller_target_count; slot++) begin
          target_slot_vif = i3c_vif_for_slot(slot);
          if ((target_slot_vif.device_sda_o !== 1'b1) ||
              (target_slot_vif.device_sda_pp_en !== 1'b0))
            `uvm_fatal("IBI_BUS_PRIME_CONTENTION",
                       $sformatf("UVM Target slot %0d drove SDA during Controller bus-prime START",
                                 slot))
        end

        fork : stable_bus_prime_start_guard
          begin
            @(negedge vseq_ctx.cfg.i3c_vif.scl_i);
            scl_fall_time = $realtime;
            first_scl_fall_seen = 1'b1;
            if ((vseq_ctx.cfg.i3c_vif.scl_o !== 1'b0) ||
                (vseq_ctx.cfg.i3c_vif.scl_pp_en !== 1'b1))
              `uvm_fatal("IBI_BUS_PRIME_SCL_OWNER",
                         "Bus-prime SCL falling edge was not driven Push-Pull by the UVM Controller")
            hold_time = scl_fall_time - sda_fall_time;
            // Enforce the configured minimum. A longer legal START hold must
            // not fail merely because the BFM normally uses the minimum.
            if (hold_time < realtime'(minimum_hold_ns))
              `uvm_fatal("IBI_BUS_PRIME_HOLD",
                         $sformatf("Bus-prime START hold=%0.3f ns is below configured minimum tHoldStart=%0d ns",
                                   hold_time, minimum_hold_ns))

            // The bus-prime address is normally 0x5A, whose A6=1 releases SDA.
            // Regardless of A6, SDA must retain the START-low value throughout
            // the configured handoff interval after the first SCL falling edge.
            fork : address_launch_guard
              begin
                #(minimum_addr_launch_ns * 1ns);
              end
              begin
                @(posedge vseq_ctx.cfg.i3c_vif.sda_i);
                if (($realtime - scl_fall_time) <
                    realtime'(minimum_addr_launch_ns))
                  `uvm_fatal("IBI_BUS_PRIME_ADDR_LAUNCH",
                             $sformatf("Bus-prime SDA changed %0.3f ns after first SCL falling edge; configured address-launch minimum=%0d ns",
                                       $realtime - scl_fall_time,
                                       minimum_addr_launch_ns))
              end
            join_any
            disable address_launch_guard;
            timing_done = 1'b1;
          end
          begin
            forever begin
              @(posedge vseq_ctx.cfg.i3c_vif.sda_i);
              if (!first_scl_fall_seen)
                `uvm_fatal("IBI_BUS_PRIME_GLITCH",
                           "Bus-prime SDA released before the first SCL falling edge")
            end
          end
          begin
            forever begin
              @(vseq_ctx.cfg.i3c_vif.scl_i or
                vseq_ctx.cfg.i3c_vif.sda_i);
              if ($isunknown({vseq_ctx.cfg.i3c_vif.scl_i,
                              vseq_ctx.cfg.i3c_vif.sda_i}))
                `uvm_fatal("IBI_BUS_PRIME_UNKNOWN",
                           "Bus-prime START observed X/Z before the first SCL falling edge")
            end
          end
        join_any
        disable stable_bus_prime_start_guard;
      end
      begin
        repeat (vseq_ctx.cfg.ibi_timeout_cycles)
          @(posedge vseq_ctx.cfg.vif.clk);
        if (!timing_done)
          `uvm_fatal("IBI_BUS_PRIME_TIMEOUT",
                     "Timed out waiting for the complete bus-prime START phase")
      end
    join_any
    disable bus_prime_start_timeout_guard;

    if (!timing_done)
      `uvm_fatal("IBI_BUS_PRIME_INCOMPLETE",
                 "Bus-prime START timing checker did not complete")
    `uvm_info("IBI_BUS_PRIME_TIMING",
              $sformatf("Controller-owned I3C bus-prime START hold=%0.3f ns minimum=%0d ns address-launch minimum=%0d ns",
                        hold_time, minimum_hold_ns,
                        minimum_addr_launch_ns),
              UVM_LOW)
  endtask

  protected task initialize_target_ibi(i3c_ral_model ral);
    i3c_host_bus_idle_seq bus_idle_seq;
    i3c_csr_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH) csr_helper;
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
    bus_idle_seq = i3c_host_bus_idle_seq::type_id::create("bus_idle_seq");
    bus_idle_seq.unassigned_addr = vseq_ctx.cfg.ibi_target_addr;
    fork
      bus_idle_seq.start(vseq_ctx.i3c_sqr);
      check_bus_prime_start_timing();
    join

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
// IBI bus-prime timing tasks included inside i3c_ibi_base_vseq.
