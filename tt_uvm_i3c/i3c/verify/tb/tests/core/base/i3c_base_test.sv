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
// File        : i3c_base_test.sv
// Description : Base UVM test for I3C verification environment.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-16
//
// *****************************************************************************

class i3c_base_test extends uvm_test;
    `uvm_component_utils(i3c_base_test)

    i3c_env          env;
    i3c_env_cfg      cfg;
    i3c_base_vseq    vseq;
    virtual i3c_tb_if   vif;
    virtual axi4lite_if #(TB_ADDR_WIDTH, TB_DATA_WIDTH) bus_vif;  // P6

    function new(string name = "i3c_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function i3c_base_vseq create_vseq();
        return i3c_base_vseq::type_id::create("vseq");
    endfunction

    virtual function i3c_vseq_context get_env_vseq_ctx();
        if (env == null || env.vseq_ctx == null)
            `uvm_fatal("NO_VSEQ_CTX", "I3C verification environment vseq context is not available")
        return env.vseq_ctx;
    endfunction

    virtual task start_vseq(i3c_base_vseq seq);
        if (seq == null)
            `uvm_fatal(get_type_name(), "Cannot start a null virtual sequence")
        seq.vseq_ctx = get_env_vseq_ctx();
        seq.start(null);
    endtask

    function void build_phase(uvm_phase phase);
        int scoreboard_plusarg;

        super.build_phase(phase);

        if (!uvm_config_db#(virtual i3c_tb_if)::get(this, "", "i3c_vif", vif)) begin
            `uvm_fatal(get_type_name(), "Missing i3c_vif")
        end

        cfg = i3c_env_cfg::type_id::create("cfg");
        cfg.vif = vif;
        if ($value$plusargs("I3C_SB=%0d", scoreboard_plusarg))
            cfg.has_scoreboard = (scoreboard_plusarg != 0);
`ifdef I3C_DV_NATIVE_RTL
        cfg.has_rtl = 1'b1;
`else
        cfg.has_rtl = 1'b0;
`endif

        // P6: shared AXI4-Lite bus vif (from tb_top). If absent, disable agent.
        if (uvm_config_db#(virtual axi4lite_if #(TB_ADDR_WIDTH, TB_DATA_WIDTH))::get(
                this, "", "i3c_bus_vif", bus_vif)) begin
            cfg.bus_vif = bus_vif;
        end else begin
            cfg.has_local_bus_agent = 1'b0;
            `uvm_warning(get_type_name(), "No bus vif; I3C bus agent disabled")
        end

        uvm_config_db#(i3c_env_cfg)::set(this, "env", "cfg", cfg);
        env = i3c_env::type_id::create("env", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        uvm_config_db#(i3c_vseq_context)::set(null, "uvm_test_top", "context", env.vseq_ctx);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        vseq = create_vseq();
        start_vseq(vseq);
        phase.drop_objection(this);
    endtask
endclass : i3c_base_test
