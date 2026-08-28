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
// File        : smc_i3c_ibi_target_tx_basic_vseq.sv
// Description : Virtual sequence for I3C IBI basic.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-24
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_BASIC_VSEQ_SV
`define SMC_I3C_IBI_TARGET_TX_BASIC_VSEQ_SV

class smc_i3c_ibi_target_tx_basic_vseq extends smc_i3c_ibi_base_vseq;
    `uvm_object_utils(smc_i3c_ibi_target_tx_basic_vseq)

    function new(string name = "smc_i3c_ibi_target_tx_basic_vseq");
        super.new(name);
    endfunction

    virtual task body();
        super.body();  // waits for reset release

        if (!vseq_ctx.cfg.has_rtl)
            `uvm_fatal("SMC_I3C_MODE",
                       "smc_i3c_ibi_target_tx_basic_test requires DUT_MODE=rtl")
        if (vseq_ctx.cfg.ibi_dut_role != SMC_I3C_IBI_DUT_TARGET)
            `uvm_fatal("IBI_BASIC_ROLE",
                       "smc_i3c_ibi_target_tx_basic_test covers DUT-target transmit only; use the controller-receive test for DUT-controller mode")
`ifndef SMC_USE_I3C_RTL
        `uvm_fatal("IBI_VIP_BUILD", "I3C host VIP is available only in DUT_MODE=rtl")
`elsif SMC_USE_I3C_RAL
        begin
            smc_i3c_ral_model ral;
            smc_i3c_host_accept_ibi_seq host_seq;
            uvm_event host_armed_event;
            uvm_reg_data_t field_value;
            uvm_reg_data_t ibi_descriptor;
            bit transaction_done;
            int unsigned attempt_samples_before;
            int unsigned completion_samples_before;
            int unsigned queue_irq_samples_before;
            int unsigned attempt_samples;
            int unsigned completion_samples;
            int unsigned queue_irq_samples;

            if (vseq_ctx.i3c_sqr == null)
                `uvm_fatal("IBI_HOST_SQR", "I3C host sequencer is not available")

            ral = get_i3c_ral_model();
            attempt_samples_before = vseq_ctx.cfg.ibi_cov_attempt_samples;
            completion_samples_before = vseq_ctx.cfg.ibi_cov_completion_samples;
            queue_irq_samples_before = vseq_ctx.cfg.ibi_cov_queue_irq_samples;
            vseq_ctx.cfg.ibi_expected_ack = 1'b1;
            vseq_ctx.cfg.ibi_expected_terminal_status = IBI_STATUS_SUCCESS;
            initialize_target_ibi(ral);

            write_field(ral.I3C_EC.TTI.INTERRUPT_ENABLE.IBI_DONE_EN,
                        1, "enable IBI_DONE interrupt");
            wait_irq(1'b0, "check initial IRQ state");
            expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE,
                         0, "check initial IBI_DONE");
            expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_IBI,
                         0, "check initial PENDING_IBI");
            expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_INTERRUPT,
                         0, "check initial PENDING_INTERRUPT");
            read_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH,
                       field_value, "observe initial IBI queue depth");
            read_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY,
                       field_value, "observe initial IBI queue empty state");

            host_seq = smc_i3c_host_accept_ibi_seq::type_id::create("host_seq");
            ibi_descriptor = uvm_reg_data_t'(vseq_ctx.cfg.ibi_basic_mdb) << 24;
            host_armed_event = uvm_event_pool::get_global(
                SMC_I3C_HOST_IBI_ARMED_EVENT);
            host_armed_event.reset();
            transaction_done = 1'b0;

            fork : ibi_timeout_guard
                begin
                    fork
                        begin
                            host_seq.start(vseq_ctx.i3c_sqr);
                        end
                        begin
                            host_armed_event.wait_on();
                            write_register(ral.I3C_EC.TTI.IBI_PORT,
                                           ibi_descriptor,
                                           "queue MDB-only IBI descriptor");
                        end
                    join
                    transaction_done = 1'b1;
                end
                begin
                    repeat (vseq_ctx.cfg.ibi_timeout_cycles)
                        @(posedge vseq_ctx.cfg.vif.clk);
                    if (!transaction_done)
                        `uvm_fatal("IBI_TIMEOUT",
                                   "Timed out waiting for DUT-target IBI ACK/completion")
                end
            join_any
            disable ibi_timeout_guard;

            if (!transaction_done || !host_seq.response_valid)
                `uvm_fatal("IBI_HOST_CHECK", "Host did not complete the target IBI transfer")

            wait_irq(1'b1, "wait for IBI_DONE IRQ assertion");
            expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE,
                         1, "check asserted IBI_DONE status");

            // LAST_IBI_STATUS is the architectural completion result. Reading
            // it also clears IBI_DONE and therefore the enabled boundary IRQ.
            read_field(ral.I3C_EC.TTI.STATUS.LAST_IBI_STATUS,
                       field_value, "read LAST_IBI_STATUS");

            wait_irq(1'b0, "wait for IRQ clear after LAST_IBI_STATUS read");
            expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.IBI_DONE,
                         0, "check cleared IBI_DONE status");
            expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_IBI,
                         0, "check final PENDING_IBI");
            expect_field(ral.I3C_EC.TTI.INTERRUPT_STATUS.PENDING_INTERRUPT,
                         0, "check final PENDING_INTERRUPT");
            read_field(ral.I3C_EC.TTI.IBI_QUEUE_DEPTH.IBI_QUEUE_DEPTH,
                       field_value, "observe final IBI queue depth");
            read_field(ral.I3C_EC.TTI.QUEUE_STATUS.IBI_QUEUE_EMPTY,
                       field_value, "observe final IBI queue empty state");
            wait_bus_idle("check bus after successful IBI");

            attempt_samples = vseq_ctx.cfg.ibi_cov_attempt_samples -
                              attempt_samples_before;
            completion_samples = vseq_ctx.cfg.ibi_cov_completion_samples -
                                 completion_samples_before;
            queue_irq_samples = vseq_ctx.cfg.ibi_cov_queue_irq_samples -
                                queue_irq_samples_before;
            if ((attempt_samples == 0) || (completion_samples == 0) ||
                (queue_irq_samples == 0)) begin
                if (vseq_ctx.cfg.require_ibi_coverage_samples)
                    `uvm_fatal("IBI_COVERAGE_WIRING",
                               $sformatf("Missing IBI coverage sample: attempt=%0d completion=%0d queue_irq=%0d",
                                         attempt_samples, completion_samples,
                                         queue_irq_samples))
                else
                    `uvm_warning("IBI_COVERAGE_WIRING",
                                 $sformatf("Functional checks passed but coverage observation is incomplete: attempt=%0d completion=%0d queue_irq=%0d; use +IBI_REQUIRE_COV after observer validation",
                                           attempt_samples, completion_samples,
                                           queue_irq_samples))
            end else if ((attempt_samples > 1) ||
                         (completion_samples > 1)) begin
                `uvm_warning("IBI_COVERAGE_DUPLICATE",
                             $sformatf("One basic IBI produced multiple transaction samples: attempt=%0d completion=%0d (CSR queue_irq snapshots=%0d)",
                                       attempt_samples, completion_samples,
                                       queue_irq_samples))
            end else begin
                `uvm_info("IBI_COVERAGE_WIRING",
                          $sformatf("Observed IBI coverage samples: attempt=%0d completion=%0d queue_irq=%0d",
                                    attempt_samples, completion_samples,
                                    queue_irq_samples),
                          UVM_LOW)
            end

            `uvm_info("IBI_BASIC_PASS",
                      $sformatf("DUT target IBI accepted: DA=0x%02h MDB=0x%02h",
                                vseq_ctx.cfg.ibi_target_addr,
                                vseq_ctx.cfg.ibi_basic_mdb),
                      UVM_LOW)
        end
`else
        `uvm_fatal("IBI_RAL_BUILD", "smc_i3c_ibi_target_tx_basic_test requires SMC_USE_I3C_RAL")
`endif
    endtask
endclass : smc_i3c_ibi_target_tx_basic_vseq

`endif // SMC_I3C_IBI_TARGET_TX_BASIC_VSEQ_SV
