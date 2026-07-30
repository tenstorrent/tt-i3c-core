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
// File        : smc_i3c_ibi_base_test.sv
// Description : Base UVM test for I3C IBI scenarios.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-25
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_BASE_TEST_SV
`define SMC_I3C_IBI_BASE_TEST_SV

class smc_i3c_ibi_base_test extends smc_peripherals_base_test;
    `uvm_component_utils(smc_i3c_ibi_base_test)

    protected smc_i3c_ibi_dut_role_e dut_role = SMC_I3C_IBI_DUT_TARGET;
    protected int unsigned controller_target_count = 1;

    function new(string name = "smc_i3c_ibi_base_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected function bit is_reserved_dynamic_addr(bit [6:0] addr);
        // Mirrors i3c_pkg::is_i3c_rsvd_addr from the pinned core. Keeping the
        // policy here avoids hardcoded address ranges in sequences/coverage.
        return addr inside {[7'h00:7'h07], 7'h3e, 7'h5e, 7'h6e, 7'h76,
                            [7'h78:7'h7f]};
    endfunction

    protected virtual function bit require_ibi_coverage_by_default();
        return 1'b0;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        int role_plusarg;
        int unsigned target_addr_plusarg;
        int unsigned mdb_plusarg;
        int unsigned timeout_plusarg;
        int unsigned retry_plusarg;

`ifdef SMC_USE_I3C_RTL
        if ($value$plusargs("IBI_DUT_CONTROLLER=%0d", role_plusarg)) begin
            case (role_plusarg)
                0: dut_role = SMC_I3C_IBI_DUT_TARGET;
                1: dut_role = SMC_I3C_IBI_DUT_CONTROLLER;
                default:
                    `uvm_fatal("IBI_ROLE",
                               $sformatf("IBI_DUT_CONTROLLER must be 0 or 1, got %0d",
                                         role_plusarg))
            endcase
        end
        // These overrides are selected before the env builds its I3C agent.
        smc_i3c_monitor::install_type_override();
        if (dut_role == SMC_I3C_IBI_DUT_CONTROLLER)
            smc_i3c_target_driver::install_type_override();
        else
            smc_i3c_host_driver::install_type_override();
`endif

        super.build_phase(phase);

        cfg.ibi_dut_role = dut_role;
        cfg.ibi_controller_target_count = controller_target_count;
        cfg.require_ibi_coverage_samples =
            require_ibi_coverage_by_default() ||
            $test$plusargs("IBI_REQUIRE_COV");
        cfg.require_ibi_passive_monitor_match =
            $test$plusargs("IBI_REQUIRE_PASSIVE_MONITOR");

        if ($value$plusargs("IBI_TARGET_ADDR=%h", target_addr_plusarg)) begin
            if (target_addr_plusarg > 7'h7f)
                `uvm_fatal("IBI_TARGET_ADDR",
                           $sformatf("IBI_TARGET_ADDR must fit in seven bits, got 0x%0h",
                                     target_addr_plusarg))
            cfg.ibi_target_addr = target_addr_plusarg[6:0];
        end
        if (is_reserved_dynamic_addr(cfg.ibi_target_addr))
            `uvm_fatal("IBI_TARGET_ADDR",
                       $sformatf("IBI_TARGET_ADDR 0x%02h is reserved by I3C",
                                 cfg.ibi_target_addr))
        cfg.ibi_addr_class = IBI_ADDR_VALID;
        cfg.ibi_addr_class_valid = 1'b1;
        cfg.ibi_source_instance_by_addr[cfg.ibi_target_addr] =
            cfg.ibi_source_instance;
        cfg.vif.i3c_controller_expected_addr = cfg.ibi_target_addr;

        if ($value$plusargs("IBI_BASIC_MDB=%h", mdb_plusarg)) begin
            if (mdb_plusarg > 8'hff)
                `uvm_fatal("IBI_BASIC_MDB",
                           $sformatf("IBI_BASIC_MDB must fit in one byte, got 0x%0h",
                                     mdb_plusarg))
            cfg.ibi_basic_mdb = mdb_plusarg[7:0];
        end
        if ($value$plusargs("IBI_TIMEOUT_CYCLES=%0d", timeout_plusarg)) begin
            if (timeout_plusarg == 0)
                `uvm_fatal("IBI_TIMEOUT_CFG", "IBI_TIMEOUT_CYCLES must be non-zero")
            cfg.ibi_timeout_cycles = timeout_plusarg;
        end
        if ($value$plusargs("IBI_RETRY_COUNT=%0d", retry_plusarg)) begin
            if (retry_plusarg > 7)
                `uvm_fatal("IBI_RETRY_CFG", "IBI_RETRY_COUNT must fit the 3-bit CSR field")
            cfg.ibi_retry_count = retry_plusarg;
        end

`ifdef SMC_USE_I3C_RTL
        if (!uvm_config_db#(virtual i3c_if)::get(
                this, "", "smc_i3c_vif", cfg.i3c_vif))
            `uvm_fatal("IBI_VIF", "Missing smc_i3c_vif for IBI functional test")
        if (cfg.ibi_controller_target_count > 1) begin
            if (!uvm_config_db#(virtual i3c_if)::get(
                    this, "", "smc_i3c_secondary_vif",
                    cfg.i3c_secondary_vif))
                `uvm_fatal("IBI_SECONDARY_VIF",
                           "Missing secondary i3c_if for multi-target IBI test")
        end
        cfg.has_i3c_agent = 1'b1;
        cfg.has_ibi_coverage = 1'b1;
        cfg.has_ibi_scoreboard = (dut_role == SMC_I3C_IBI_DUT_TARGET);
        cfg.has_ibi_controller_checker =
            (dut_role == SMC_I3C_IBI_DUT_CONTROLLER);
`endif

        // Target-transmit tests use an independent descriptor predictor and
        // actual-event observer. The scoreboard compares their transaction
        // streams; coverage samples observed attempts/completions and the
        // correlated queue/IRQ result.

        `uvm_info(get_type_name(),
                   $sformatf("IBI base test configured: DUT role=%s DA=0x%02h MDB=0x%02h timeout=%0d require_cov=%0b",
                              (dut_role == SMC_I3C_IBI_DUT_CONTROLLER) ?
                                "controller" : "target",
                              cfg.ibi_target_addr,
                              cfg.ibi_basic_mdb,
                              cfg.ibi_timeout_cycles,
                              cfg.require_ibi_coverage_samples),
                   UVM_LOW)
    endfunction

    virtual function smc_peripherals_base_vseq create_vseq();
        `uvm_fatal("IBI_BASE_ONLY",
                   "smc_i3c_ibi_base_test is a base class and cannot run directly")
        return null;
    endfunction
endclass : smc_i3c_ibi_base_test

`endif // SMC_I3C_IBI_BASE_TEST_SV
