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
// File        : smc_peripherals_base_test.sv
// Description : Base UVM test for SMC peripherals.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-16
//
// *****************************************************************************

class smc_peripherals_base_test extends uvm_test;
    `uvm_component_utils(smc_peripherals_base_test)

    smc_peripherals_env          env;
    smc_peripherals_env_cfg      cfg;
    smc_peripherals_base_vseq    vseq;
    virtual smc_peripherals_if   vif;
    virtual axi4lite_if #(TB_ADDR_WIDTH, TB_DATA_WIDTH) bus_vif;  // P6

    function new(string name = "smc_peripherals_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function smc_peripherals_base_vseq create_vseq();
        return smc_peripherals_base_vseq::type_id::create("vseq");
    endfunction

    virtual function smc_peripherals_vseq_context get_env_vseq_ctx();
        if (env == null || env.vseq_ctx == null)
            `uvm_fatal("NO_VSEQ_CTX", "SMC peripherals vseq context is not available")
        return env.vseq_ctx;
    endfunction

    virtual task start_vseq(smc_peripherals_base_vseq seq);
        if (seq == null)
            `uvm_fatal(get_type_name(), "Cannot start a null virtual sequence")
        seq.vseq_ctx = get_env_vseq_ctx();
        seq.start(null);
    endtask

    function void build_phase(uvm_phase phase);
        int scoreboard_plusarg;

        super.build_phase(phase);

        if (!uvm_config_db#(virtual smc_peripherals_if)::get(this, "", "smc_peripherals_vif", vif)) begin
            `uvm_fatal(get_type_name(), "Missing smc_peripherals_vif")
        end

        cfg = smc_peripherals_env_cfg::type_id::create("cfg");
        cfg.vif = vif;
        if ($value$plusargs("SMC_SB=%0d", scoreboard_plusarg))
            cfg.has_scoreboard = (scoreboard_plusarg != 0);
`ifdef SMC_USE_I3C_RTL
        cfg.has_rtl = 1'b1;
`else
        cfg.has_rtl = 1'b0;
`endif

        // P6: shared AXI4-Lite bus vif (from tb_top). If absent, disable agent.
        if (uvm_config_db#(virtual axi4lite_if #(TB_ADDR_WIDTH, TB_DATA_WIDTH))::get(
                this, "", "smc_peripherals_bus_vif", bus_vif)) begin
            cfg.bus_vif = bus_vif;
        end else begin
            cfg.has_local_bus_agent = 1'b0;
            `uvm_warning(get_type_name(), "No bus vif; peripherals bus agent disabled")
        end

        uvm_config_db#(smc_peripherals_env_cfg)::set(this, "env", "cfg", cfg);
        env = smc_peripherals_env::type_id::create("env", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        uvm_config_db#(smc_peripherals_vseq_context)::set(null, "uvm_test_top", "context", env.vseq_ctx);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        vseq = create_vseq();
        start_vseq(vseq);
        phase.drop_objection(this);
    endtask
endclass : smc_peripherals_base_test
