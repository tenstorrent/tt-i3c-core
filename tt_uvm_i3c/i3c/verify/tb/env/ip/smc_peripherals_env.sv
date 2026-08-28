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
// File        : smc_peripherals_env.sv
// Description : Top-level UVM environment for SMC peripherals.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
//
// *****************************************************************************

class smc_peripherals_env extends uvm_env;
    `uvm_component_utils(smc_peripherals_env)

    smc_peripherals_env_cfg       cfg;
    smc_peripherals_vseq_context  vseq_ctx;  // 'context' is a SV keyword
    smc_peripherals_vseq_services services;
    smc_i3c_csr_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH) i3c_csr_helper;
    smc_peripherals_scoreboard #(TB_ADDR_WIDTH, TB_DATA_WIDTH) scoreboard;
    axi4lite_agent #(TB_ADDR_WIDTH, TB_DATA_WIDTH) bus_agt;  // P6: shared VIP agent
    smc_i3c_ibi_blocked_coverage i3c_ibi_blocked_cov;
`ifdef SMC_USE_I3C_RTL
    i3c_agent i3c_agt;
    i3c_agent i3c_target_agt[TB_MAX_IBI_REQUESTERS];
    i3c_agent i3c_agt_secondary;
`ifdef SMC_USE_I3C_RAL
    smc_i3c_ibi_predictor ibi_predictor;
    smc_i3c_ibi_observer ibi_observer;
    smc_i3c_ibi_coverage ibi_functional_cov;
    smc_i3c_ibi_sva_probe ibi_sva_probe;
    smc_i3c_ibi_recovery_checker ibi_recovery_checker;
    smc_i3c_ibi_scoreboard ibi_scoreboard;
    smc_i3c_host_driver ibi_host_driver;
    smc_i3c_target_driver ibi_target_driver;
    smc_i3c_target_driver ibi_target_driver_by_slot[TB_MAX_IBI_REQUESTERS];
    smc_i3c_target_driver ibi_target_driver_secondary;
    smc_i3c_ibi_controller_predictor ibi_controller_predictor;
    smc_i3c_ibi_controller_observer ibi_controller_observer;
    smc_i3c_ibi_controller_scoreboard ibi_controller_scoreboard;
`endif
`endif
`ifdef SMC_USE_I3C_RAL
    smc_i3c_ral_model i3c_ral_model;
    smc_i3c_controller_hci_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
      i3c_controller_hci_helper;
    smc_i3c_axi4lite_reg_adapter #(TB_ADDR_WIDTH, TB_DATA_WIDTH) ral_adapter;
    uvm_reg_predictor #(axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH)) ral_predictor;
`endif

    function new(string name = "smc_peripherals_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(smc_peripherals_env_cfg)::get(this, "", "cfg", cfg)) begin
            cfg = smc_peripherals_env_cfg::type_id::create("cfg");
        end

        services = smc_peripherals_vseq_services::type_id::create("services");
        services.vif = cfg.vif;

        i3c_csr_helper = smc_i3c_csr_helper #(TB_ADDR_WIDTH, TB_DATA_WIDTH)::type_id::create(
            "i3c_csr_helper");

        vseq_ctx = smc_peripherals_vseq_context::type_id::create("context");
        vseq_ctx.cfg = cfg;
        vseq_ctx.services = services;
        vseq_ctx.i3c_csr_helper = i3c_csr_helper;
        i3c_ibi_blocked_cov = smc_i3c_ibi_blocked_coverage::type_id::create(
            "i3c_ibi_blocked_cov");
        vseq_ctx.i3c_ibi_blocked_cov = i3c_ibi_blocked_cov;

`ifdef SMC_USE_I3C_RAL
        if (cfg.has_rtl && cfg.has_ral) begin
            if (cfg.ral_model == null) begin
                // Generated RAL classes query this resource while they are
                // constructed. Configure the intended policy explicitly so a
                // missing optional resource is not reported once per field.
                uvm_reg::include_coverage("*", cfg.ral_coverage_models);
                i3c_ral_model = new("i3c_ral_model");
                i3c_ral_model.build();
                i3c_ral_model.default_map.set_base_addr(cfg.i3c_base_address);
                i3c_ral_model.lock_model();
                i3c_ral_model.reset("HARD");
                cfg.ral_model = i3c_ral_model;
            end else begin
                i3c_ral_model = cfg.ral_model;
            end
            ral_adapter = smc_i3c_axi4lite_reg_adapter #(
                TB_ADDR_WIDTH, TB_DATA_WIDTH
            )::type_id::create("ral_adapter");
            ral_predictor = uvm_reg_predictor #(
                axi4lite_item #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
            )::type_id::create("ral_predictor", this);
            vseq_ctx.i3c_ral_model = i3c_ral_model;
            i3c_controller_hci_helper =
              smc_i3c_controller_hci_helper #(
                TB_ADDR_WIDTH, TB_DATA_WIDTH
              )::type_id::create("i3c_controller_hci_helper");
            i3c_controller_hci_helper.csr_helper = i3c_csr_helper;
            i3c_controller_hci_helper.ral_model = i3c_ral_model;
            i3c_controller_hci_helper.cfg = cfg;
            vseq_ctx.i3c_controller_hci_helper =
              i3c_controller_hci_helper;
        end
`endif

        // P6: build the shared AXI4-Lite reg-access agent (ACTIVE) when enabled.
        if (cfg.has_local_bus_agent) begin
            if (cfg.bus_cfg == null)
                cfg.bus_cfg = axi4lite_config #(TB_ADDR_WIDTH, TB_DATA_WIDTH)::type_id::create("bus_cfg");
            cfg.bus_cfg.vif = cfg.bus_vif;
            uvm_config_db#(axi4lite_config #(TB_ADDR_WIDTH, TB_DATA_WIDTH))::set(this, "bus_agt", "cfg", cfg.bus_cfg);
            bus_agt = axi4lite_agent #(TB_ADDR_WIDTH, TB_DATA_WIDTH)::type_id::create("bus_agt", this);
        end

`ifdef SMC_USE_I3C_RTL
        if (cfg.has_i3c_agent) begin
            string agent_name;

            cfg.sync_ibi_target_slots();
            if ((cfg.ibi_controller_target_count < 1) ||
                (cfg.ibi_controller_target_count >
                 TB_MAX_IBI_REQUESTERS))
                `uvm_fatal("SMC_I3C_TARGET_COUNT",
                           $sformatf("IBI requester count must be 1..%0d, got %0d",
                                     TB_MAX_IBI_REQUESTERS,
                                     cfg.ibi_controller_target_count))
            if (cfg.i3c_vif == null)
                `uvm_fatal("SMC_I3C_VIF", "IBI test requested the I3C agent without an i3c_if")
            if (cfg.i3c_cfg == null)
                cfg.i3c_cfg = i3c_agent_cfg::type_id::create("i3c_cfg");
            cfg.i3c_cfg.is_active = 1'b1;
            cfg.i3c_cfg.has_driver = 1'b1;
            cfg.i3c_cfg.en_monitor = 1'b1;
            cfg.i3c_cfg.if_mode =
              (cfg.ibi_dut_role == SMC_I3C_IBI_DUT_CONTROLLER) ?
                Device : Host;
            cfg.i3c_cfg.vif = cfg.i3c_vif;
            cfg.i3c_cfg.i3c_target0.dynamic_addr = cfg.ibi_target_addr;
            cfg.i3c_cfg.i3c_target0.dynamic_addr_valid = 1'b1;
            cfg.i3c_cfg.i3c_target0.IBI_enabled = 1'b1;
            cfg.i3c_cfg.i3c_target0.bcr = cfg.ibi_bcr;
            uvm_config_db#(i3c_agent_cfg)::set(this, "i3c_agt", "cfg", cfg.i3c_cfg);
            uvm_config_db#(virtual i3c_if)::set(this, "i3c_agt", "vif", cfg.i3c_vif);
            if (cfg.ibi_dut_role == SMC_I3C_IBI_DUT_CONTROLLER) begin
                // The primary Device-mode agent is Target slot zero. Give its
                // specialized driver the same slot identity and shared
                // telemetry object used by the auxiliary Target agents.
                uvm_config_db#(int unsigned)::set(
                  this, "i3c_agt.driver", "smc_i3c_target_slot", 0);
                uvm_config_db#(smc_peripherals_env_cfg)::set(
                  this, "i3c_agt.driver", "smc_peripherals_env_cfg", cfg);
            end
            i3c_agt = i3c_agent::type_id::create("i3c_agt", this);
            i3c_target_agt[0] = i3c_agt;
            for (int unsigned slot = 1;
                 slot < cfg.ibi_controller_target_count; slot++) begin
                agent_name = (slot == 1) ? "i3c_agt_secondary" :
                  $sformatf("i3c_agt_target_%0d", slot);
                if (cfg.i3c_target_vif[slot] == null)
                    `uvm_fatal("SMC_I3C_TARGET_VIF",
                               $sformatf("Multi-target IBI test requires i3c_if slot %0d",
                                         slot))
                cfg.i3c_target_cfg[slot] =
                  i3c_agent_cfg::type_id::create(
                    $sformatf("i3c_target_cfg_%0d", slot));
                cfg.i3c_target_cfg[slot].is_active = 1'b1;
                cfg.i3c_target_cfg[slot].has_driver = 1'b1;
                cfg.i3c_target_cfg[slot].en_monitor = 1'b0;
                cfg.i3c_target_cfg[slot].if_mode = Device;
                cfg.i3c_target_cfg[slot].vif = cfg.i3c_target_vif[slot];
                cfg.i3c_target_cfg[slot].i3c_target0.dynamic_addr =
                  cfg.ibi_target_addr_by_slot[slot];
                cfg.i3c_target_cfg[slot].i3c_target0.dynamic_addr_valid = 1'b1;
                cfg.i3c_target_cfg[slot].i3c_target0.IBI_enabled = 1'b1;
                cfg.i3c_target_cfg[slot].i3c_target0.bcr = cfg.ibi_bcr;
                uvm_config_db#(i3c_agent_cfg)::set(
                  this, agent_name, "cfg", cfg.i3c_target_cfg[slot]);
                uvm_config_db#(virtual i3c_if)::set(
                  this, agent_name, "vif", cfg.i3c_target_vif[slot]);
                uvm_config_db#(int unsigned)::set(
                  this, {agent_name, ".driver"},
                  "smc_i3c_target_slot", slot);
                uvm_config_db#(smc_peripherals_env_cfg)::set(
                  this, {agent_name, ".driver"},
                  "smc_peripherals_env_cfg", cfg);
                i3c_target_agt[slot] =
                  i3c_agent::type_id::create(agent_name, this);
            end
            i3c_agt_secondary = i3c_target_agt[1];
            cfg.i3c_secondary_cfg = cfg.i3c_target_cfg[1];
        end
`ifdef SMC_USE_I3C_RAL
        if (cfg.has_ibi_scoreboard) begin
            if (!cfg.has_i3c_agent)
                `uvm_fatal("IBI_OBSERVER_AGENT", "IBI observation requires the active I3C agent")
            ibi_observer = smc_i3c_ibi_observer::type_id::create("ibi_observer", this);
            ibi_observer.cfg = cfg;
        end
        if (cfg.has_ibi_coverage) begin
            ibi_functional_cov = smc_i3c_ibi_coverage::type_id::create(
                "ibi_functional_cov", this);
            ibi_sva_probe = smc_i3c_ibi_sva_probe::type_id::create(
                "ibi_sva_probe", this);
            ibi_sva_probe.vif = cfg.vif;
        end
        if (cfg.has_ibi_recovery_checker) begin
            if (!cfg.has_ibi_coverage)
                `uvm_fatal("IBI_RECOVERY_COV",
                           "Recovery checker requires IBI coverage/SVA consumers")
            ibi_recovery_checker =
              smc_i3c_ibi_recovery_checker::type_id::create(
                "ibi_recovery_checker", this);
            ibi_recovery_checker.cfg = cfg;
            vseq_ctx.i3c_ibi_recovery_checker = ibi_recovery_checker;
        end
        if (cfg.has_ibi_scoreboard) begin
            if (!cfg.has_i3c_agent)
                `uvm_fatal("IBI_SB_AGENT", "IBI scoreboard requires the active I3C agent")
            ibi_predictor = smc_i3c_ibi_predictor::type_id::create(
                "ibi_predictor", this);
            ibi_predictor.cfg = cfg;
            ibi_scoreboard = smc_i3c_ibi_scoreboard::type_id::create(
                "ibi_scoreboard", this);
            ibi_scoreboard.cfg = cfg;
        end
        if (cfg.has_ibi_controller_checker) begin
            if (!cfg.has_i3c_agent)
                `uvm_fatal("IBI_CTRL_AGENT",
                           "Controller IBI checking requires the active I3C agent")
            ibi_controller_predictor =
              smc_i3c_ibi_controller_predictor::type_id::create(
                "ibi_controller_predictor", this);
            ibi_controller_predictor.cfg = cfg;
            ibi_controller_observer =
              smc_i3c_ibi_controller_observer::type_id::create(
                "ibi_controller_observer", this);
            ibi_controller_observer.cfg = cfg;
            ibi_controller_scoreboard =
              smc_i3c_ibi_controller_scoreboard::type_id::create(
                "ibi_controller_scoreboard", this);
            ibi_controller_scoreboard.cfg = cfg;
        end
`endif
`endif

        if (cfg.has_scoreboard) begin
            if (cfg.scoreboard_cfg == null)
                cfg.scoreboard_cfg = smc_i3c_csr_scoreboard_cfg #(
                    TB_ADDR_WIDTH, TB_DATA_WIDTH
                )::type_id::create("scoreboard_cfg");
            cfg.scoreboard_cfg.bus_vif = cfg.bus_vif;
            cfg.scoreboard_cfg.base_address = cfg.i3c_base_address;
            cfg.scoreboard_cfg.window_bytes = cfg.i3c_window_bytes;
            uvm_config_db#(
                smc_i3c_csr_scoreboard_cfg #(TB_ADDR_WIDTH, TB_DATA_WIDTH)
            )::set(this, "scoreboard", "cfg", cfg.scoreboard_cfg);
            scoreboard = smc_peripherals_scoreboard #(
                TB_ADDR_WIDTH, TB_DATA_WIDTH
            )::type_id::create("scoreboard", this);
            scoreboard.env_cfg = cfg;
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (bus_agt != null) begin
            vseq_ctx.bus_sqr = bus_agt.sqr;  // Legacy direct access for existing vseqs.
            i3c_csr_helper.bus_sqr = bus_agt.sqr;
        end
`ifdef SMC_USE_I3C_RTL
        if (i3c_agt != null) begin
            vseq_ctx.i3c_sqr = i3c_agt.sequencer;
            if (cfg.ibi_dut_role == SMC_I3C_IBI_DUT_CONTROLLER)
                vseq_ctx.i3c_target_sqr[0] = i3c_agt.sequencer;
            // The upstream driver waits for a reset negedge that may occur
            // before UVM run_phase starts. Initialize its public state here so
            // the first host sequence always begins from an idle bus.
            if (i3c_agt.driver != null)
                i3c_agt.driver.bus_state = DrvIdle;
        end
        for (int unsigned slot = 1;
             slot < cfg.ibi_controller_target_count; slot++) begin
            if (i3c_target_agt[slot] == null)
                continue;
            vseq_ctx.i3c_target_sqr[slot] =
              i3c_target_agt[slot].sequencer;
            if (i3c_target_agt[slot].driver != null)
                i3c_target_agt[slot].driver.bus_state = DrvIdle;
        end
        vseq_ctx.i3c_secondary_sqr = vseq_ctx.i3c_target_sqr[1];
`ifdef SMC_USE_I3C_RAL
        if ((ibi_observer != null) || (ibi_predictor != null) ||
            (ibi_scoreboard != null) ||
            (ibi_controller_observer != null) ||
            (ibi_controller_predictor != null) ||
            (ibi_controller_scoreboard != null)) begin
            if ((i3c_agt == null) || (i3c_agt.monitor == null) || (bus_agt == null))
                `uvm_fatal("IBI_CHECK_CONNECT", "IBI checker sources are not available")
        end
        if (ibi_recovery_checker != null) begin
            bus_agt.mon_analysis_port.connect(
                ibi_recovery_checker.axi_export);
            ibi_recovery_checker.recovery_port.connect(
                ibi_functional_cov.analysis_export);
            ibi_recovery_checker.recovery_port.connect(
                ibi_sva_probe.analysis_export);
        end
        if ((ibi_observer != null) || (ibi_predictor != null) ||
            (ibi_scoreboard != null)) begin
            if (!$cast(ibi_host_driver, i3c_agt.driver))
                `uvm_fatal("IBI_HOST_DRIVER",
                           "IBI checking requires the smc_i3c_host_driver factory override")
        end
        if (ibi_observer != null) begin
            i3c_agt.monitor.analysis_port.connect(ibi_observer.bus_export);
            ibi_host_driver.ibi_analysis_port.connect(ibi_observer.host_export);
            bus_agt.mon_analysis_port.connect(ibi_observer.axi_export);
            if (ibi_functional_cov != null)
                ibi_observer.coverage_port.connect(
                    ibi_functional_cov.analysis_export);
            if (ibi_sva_probe != null)
                ibi_observer.sva_port.connect(
                    ibi_sva_probe.analysis_export);
        end
        if (ibi_predictor != null)
            bus_agt.mon_analysis_port.connect(ibi_predictor.axi_export);
        if (ibi_scoreboard != null) begin
            if ((ibi_predictor == null) || (ibi_observer == null))
                `uvm_fatal("IBI_SB_PIPELINE",
                           "IBI scoreboard requires predictor and actual observer")
            ibi_predictor.expected_port.connect(ibi_scoreboard.expected_export);
            ibi_observer.actual_port.connect(ibi_scoreboard.actual_export);
            bus_agt.mon_analysis_port.connect(ibi_scoreboard.axi_export);
            if (ibi_functional_cov != null)
                ibi_scoreboard.coverage_port.connect(
                    ibi_functional_cov.analysis_export);
            if (ibi_sva_probe != null)
                ibi_scoreboard.coverage_port.connect(
                    ibi_sva_probe.analysis_export);
            if (ibi_sva_probe != null)
                ibi_scoreboard.sva_port.connect(
                    ibi_sva_probe.analysis_export);
            if (ibi_recovery_checker != null) begin
                ibi_observer.sva_port.connect(
                    ibi_recovery_checker.event_export);
                ibi_scoreboard.sva_port.connect(
                    ibi_recovery_checker.event_export);
            end
        end
        if ((ibi_controller_observer != null) ||
            (ibi_controller_predictor != null) ||
            (ibi_controller_scoreboard != null)) begin
            if (!$cast(ibi_target_driver, i3c_agt.driver))
                `uvm_fatal("IBI_TARGET_DRIVER",
                           "Controller IBI checking requires the smc_i3c_target_driver factory override")
            ibi_target_driver_by_slot[0] = ibi_target_driver;
            for (int unsigned slot = 1;
                 slot < cfg.ibi_controller_target_count; slot++) begin
                if (!$cast(ibi_target_driver_by_slot[slot],
                           i3c_target_agt[slot].driver))
                    `uvm_fatal("IBI_AUX_TARGET_DRIVER",
                               $sformatf("IBI Target slot %0d requires the smc_i3c_target_driver override",
                                         slot))
            end
            ibi_target_driver_secondary = ibi_target_driver_by_slot[1];
            if ((ibi_controller_observer == null) ||
                (ibi_controller_predictor == null) ||
                (ibi_controller_scoreboard == null))
                `uvm_fatal("IBI_CTRL_PIPELINE",
                           "Controller IBI predictor, observer and scoreboard must be built together")
            ibi_target_driver.ibi_analysis_port.connect(
                ibi_controller_predictor.target_export);
            ibi_target_driver.ibi_analysis_port.connect(
                ibi_controller_observer.target_export);
            for (int unsigned slot = 1;
                 slot < cfg.ibi_controller_target_count; slot++) begin
                ibi_target_driver_by_slot[slot].ibi_analysis_port.connect(
                    ibi_controller_predictor.target_export);
                ibi_target_driver_by_slot[slot].ibi_analysis_port.connect(
                    ibi_controller_observer.target_export);
            end
            i3c_agt.monitor.analysis_port.connect(
                ibi_controller_observer.bus_export);
            bus_agt.mon_analysis_port.connect(
                ibi_controller_observer.axi_export);
            ibi_controller_predictor.expected_port.connect(
                ibi_controller_scoreboard.expected_export);
            ibi_controller_observer.actual_port.connect(
                ibi_controller_scoreboard.actual_export);
            bus_agt.mon_analysis_port.connect(
                ibi_controller_scoreboard.axi_export);
            if (ibi_functional_cov != null)
                ibi_controller_scoreboard.coverage_port.connect(
                    ibi_functional_cov.analysis_export);
            if (ibi_sva_probe != null)
                ibi_controller_scoreboard.coverage_port.connect(
                    ibi_sva_probe.analysis_export);
            if (ibi_recovery_checker != null)
                ibi_controller_scoreboard.coverage_port.connect(
                    ibi_recovery_checker.event_export);
        end
`endif
`endif
        if (bus_agt != null && scoreboard != null)
            bus_agt.mon_analysis_port.connect(scoreboard.bus_export);
`ifdef SMC_USE_I3C_RAL
        if (i3c_ral_model != null && bus_agt != null &&
            bus_agt.sqr != null && ral_adapter != null) begin
            i3c_ral_model.default_map.set_base_addr(cfg.i3c_base_address);
            i3c_ral_model.default_map.set_sequencer(bus_agt.sqr, ral_adapter);
            if (ral_predictor != null) begin
                ral_predictor.map = i3c_ral_model.default_map;
                ral_predictor.adapter = ral_adapter;
                bus_agt.mon_analysis_port.connect(ral_predictor.bus_in);
                i3c_ral_model.default_map.set_auto_predict(0);
            end else begin
                i3c_ral_model.default_map.set_auto_predict(1);
            end
        end
`endif
    endfunction
endclass : smc_peripherals_env
