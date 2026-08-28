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
// File        : smc_peripherals_scoreboard.sv
// Description : Scoreboard for peripherals.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-25
//
// *****************************************************************************

class smc_peripherals_scoreboard #(int ADDR_WIDTH = TB_ADDR_WIDTH,
                                   int DATA_WIDTH = TB_DATA_WIDTH)
  extends uvm_scoreboard;

    `uvm_component_param_utils(smc_peripherals_scoreboard #(ADDR_WIDTH, DATA_WIDTH))

    localparam bit [1:0] RESP_OKAY   = 2'b00;
    localparam bit [1:0] RESP_DECERR = 2'b11;
    localparam longint unsigned HCI_VERSION_OFFSET = 'h000;
    localparam longint unsigned INTR_ENABLE_OFFSET = 'h024;
    localparam bit [31:0] HCI_VERSION_RESET = 32'h0000_0120;
    localparam bit [31:0] INTR_ENABLE_MASK  = 32'h0000_7c00;

    uvm_analysis_imp #(
        axi4lite_item #(ADDR_WIDTH, DATA_WIDTH),
        smc_peripherals_scoreboard #(ADDR_WIDTH, DATA_WIDTH)
    ) bus_export;

    smc_i3c_csr_scoreboard_cfg #(ADDR_WIDTH, DATA_WIDTH) cfg;
    smc_peripherals_env_cfg env_cfg;
    bit [31:0] intr_enable_shadow;
    int unsigned transactions;
    int unsigned modeled_checks;
    int unsigned match_count;
    int unsigned mismatch_count;
    int unsigned unmodeled_accesses;
    int unsigned reset_events;

    function new(string name = "smc_peripherals_scoreboard",
                 uvm_component parent = null);
        super.new(name, parent);
        bus_export = new("bus_export", this);
        reset_model();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(
                smc_i3c_csr_scoreboard_cfg #(ADDR_WIDTH, DATA_WIDTH)
            )::get(this, "", "cfg", cfg))
            `uvm_fatal(get_type_name(), "Missing smc_i3c_csr_scoreboard_cfg")
    endfunction

    task run_phase(uvm_phase phase);
        if (cfg.bus_vif == null)
            return;

        if (cfg.bus_vif.rst_n !== 1'b1) begin
            reset_model();
            reset_events++;
            @(posedge cfg.bus_vif.rst_n);
        end

        forever begin
            @(negedge cfg.bus_vif.rst_n);
            reset_model();
            reset_events++;
        end
    endtask

    protected function void reset_model();
        intr_enable_shadow = '0;
    endfunction

    protected function bit address_in_i3c_window(bit [ADDR_WIDTH-1:0] address);
        longint unsigned address_value;
        address_value = address;
        return (address_value >= cfg.base_address) &&
               (address_value < (cfg.base_address + cfg.window_bytes));
    endfunction

    protected function longint unsigned csr_offset(bit [ADDR_WIDTH-1:0] address);
        longint unsigned address_value;
        address_value = address;
        return address_value - cfg.base_address;
    endfunction

    protected function bit [31:0] apply_write_strobe(
        bit [31:0] previous_value,
        bit [DATA_WIDTH-1:0] write_data,
        bit [(DATA_WIDTH/8)-1:0] write_strobe
    );
        bit [31:0] next_value;
        next_value = previous_value;
        for (int unsigned byte_index = 0;
             byte_index < ((DATA_WIDTH / 8) < 4 ? (DATA_WIDTH / 8) : 4);
             byte_index++) begin
            if (write_strobe[byte_index])
                next_value[byte_index*8 +: 8] = write_data[byte_index*8 +: 8];
        end
        return next_value;
    endfunction

    protected function void record_match(string check_name,
                                         axi4lite_item #(ADDR_WIDTH, DATA_WIDTH) item);
        modeled_checks++;
        match_count++;
        `uvm_info("SMC_I3C_SB_MATCH", $sformatf(
            "%s: %s", check_name, item.convert2string()), UVM_HIGH)
    endfunction

    protected function void record_mismatch(string check_name,
                                            string detail,
                                            axi4lite_item #(ADDR_WIDTH, DATA_WIDTH) item);
        modeled_checks++;
        mismatch_count++;
        `uvm_error("SMC_I3C_SB_MISMATCH", $sformatf(
            "%s: %s; transaction={%s}", check_name, detail,
            item.convert2string()))
    endfunction

    protected function void check_response(
        string check_name,
        bit [1:0] expected_response,
        axi4lite_item #(ADDR_WIDTH, DATA_WIDTH) item
    );
        if (item.resp === expected_response)
            record_match(check_name, item);
        else
            record_mismatch(check_name, $sformatf(
                "expected response=%0b actual=%0b",
                expected_response, item.resp), item);
    endfunction

    virtual function void write(axi4lite_item #(ADDR_WIDTH, DATA_WIDTH) item);
        longint unsigned offset;
        bit [31:0] next_intr_enable;

        if (item == null)
            return;
        transactions++;

        if (!address_in_i3c_window(item.addr)) begin
            check_response("outside-window response", RESP_DECERR, item);
            return;
        end

        offset = csr_offset(item.addr);
        case (offset)
            HCI_VERSION_OFFSET: begin
                check_response("HCI_VERSION response", RESP_OKAY, item);
                if (!item.write) begin
                    if (item.rdata[31:0] === HCI_VERSION_RESET)
                        record_match("HCI_VERSION reset value", item);
                    else
                        record_mismatch("HCI_VERSION reset value", $sformatf(
                            "expected=0x%08h actual=0x%08h",
                            HCI_VERSION_RESET, item.rdata[31:0]), item);
                end else begin
                    unmodeled_accesses++;
                    `uvm_warning("SMC_I3C_SB_RO_WRITE",
                        "HCI_VERSION write observed; RO-write policy is not modeled yet")
                end
            end

            INTR_ENABLE_OFFSET: begin
                check_response("INTR_STATUS_ENABLE response", RESP_OKAY, item);
                if (item.write) begin
                    next_intr_enable = apply_write_strobe(
                        intr_enable_shadow, item.data, item.strb);
                    intr_enable_shadow = next_intr_enable & INTR_ENABLE_MASK;
                end else if ((item.rdata[31:0] & INTR_ENABLE_MASK) ===
                             intr_enable_shadow) begin
                    record_match("INTR_STATUS_ENABLE readback", item);
                end else begin
                    record_mismatch("INTR_STATUS_ENABLE readback", $sformatf(
                        "expected(masked)=0x%08h actual(masked)=0x%08h mask=0x%08h",
                        intr_enable_shadow,
                        item.rdata[31:0] & INTR_ENABLE_MASK,
                        INTR_ENABLE_MASK), item);
                end
            end

            default: begin
                unmodeled_accesses++;
                `uvm_info("SMC_I3C_SB_UNMODELED", $sformatf(
                    "No CSR predictor for offset=0x%0h; transaction observed only: %s",
                    offset, item.convert2string()), UVM_HIGH)
            end
        endcase
    endfunction

    function void report_phase(uvm_phase phase);
        int unsigned ibi_completions;
        int unsigned ibi_mismatches;
        int unsigned total_mismatches;
        bit ibi_checker_enabled;

        super.report_phase(phase);
        ibi_completions = 0;
        ibi_mismatches = 0;
        ibi_checker_enabled = 1'b0;
        if (env_cfg != null) begin
            ibi_completions = env_cfg.ibi_sb_completion_count;
            ibi_mismatches = env_cfg.ibi_sb_mismatch_count;
            ibi_checker_enabled =
                env_cfg.has_ibi_scoreboard ||
                env_cfg.has_ibi_controller_checker;
        end
        total_mismatches = mismatch_count + ibi_mismatches;

        `uvm_info("SMC_I3C_SB", "-------------------------------------------------", UVM_LOW)
        `uvm_info("SMC_I3C_SB", " SMC I3C SCOREBOARD SUMMARY", UVM_LOW)
        `uvm_info("SMC_I3C_SB", $sformatf(" CSR transactions    : %0d", transactions), UVM_LOW)
        `uvm_info("SMC_I3C_SB", $sformatf(" CSR modeled checks  : %0d", modeled_checks), UVM_LOW)
        `uvm_info("SMC_I3C_SB", $sformatf(" CSR matches         : %0d", match_count), UVM_LOW)
        `uvm_info("SMC_I3C_SB", $sformatf(" CSR mismatches      : %0d", mismatch_count), UVM_LOW)
        `uvm_info("SMC_I3C_SB", $sformatf(" CSR unmodeled       : %0d", unmodeled_accesses), UVM_LOW)
        `uvm_info("SMC_I3C_SB", $sformatf(" Reset events        : %0d", reset_events), UVM_LOW)
        `uvm_info("SMC_I3C_SB", $sformatf(" IBI checker enabled : %0b", ibi_checker_enabled), UVM_LOW)
        `uvm_info("SMC_I3C_SB", $sformatf(" IBI completions     : %0d", ibi_completions), UVM_LOW)
        `uvm_info("SMC_I3C_SB", $sformatf(" IBI mismatches      : %0d", ibi_mismatches), UVM_LOW)
        `uvm_info("SMC_I3C_SB", $sformatf(" Total mismatches    : %0d", total_mismatches), UVM_LOW)
        if (total_mismatches != 0)
            `uvm_error("SMC_I3C_SB", $sformatf(
                " FAILED: %0d total mismatch(es)", total_mismatches))
        else if ((modeled_checks == 0) &&
                 (!ibi_checker_enabled || (ibi_completions == 0)))
            `uvm_warning("SMC_I3C_SB",
                " INCOMPLETE: no modeled CSR or completed IBI check")
        else
            `uvm_info("SMC_I3C_SB", " PASSED: 0 total mismatches", UVM_LOW)
        `uvm_info("SMC_I3C_SB", "-------------------------------------------------", UVM_LOW)
    endfunction
endclass : smc_peripherals_scoreboard
