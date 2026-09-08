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
// File        : i3c_ral_all_regs_vseq.sv
// Description : Virtual sequence for all I3C registers through the RAL model.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-18
//
// *****************************************************************************

class i3c_ral_all_regs_vseq extends i3c_base_vseq;
    `uvm_object_utils(i3c_ral_all_regs_vseq)

    localparam int unsigned MIN_EXPECTED_REGISTERS = 150;

    int unsigned register_count;
    int unsigned memory_count;
    int unsigned read_attempt_count;
    int unsigned read_skip_count;
    int unsigned reset_check_count;
    int unsigned write_register_count;
    int unsigned write_check_count;
    int unsigned write_skip_count;
    int unsigned restore_count;
    int unsigned failure_count;

    function new(string name = "i3c_ral_all_regs_vseq");
        super.new(name);
    endfunction

    protected function bit name_matches(string pattern, string full_name);
        return uvm_is_match(pattern, full_name);
    endfunction

    protected function bit has_read_side_effect(string full_name);
        return name_matches("*RESPONSE_PORT*", full_name) ||
               name_matches("*RX_DATA_PORT*", full_name) ||
               name_matches("*IBI_PORT*", full_name);
    endfunction

    protected function bit has_write_side_effect(string full_name);
        return name_matches("*RESET*", full_name) ||
               name_matches("*CONTROL*", full_name) ||
               name_matches("*CTRL*", full_name) ||
               name_matches("*COMMAND*", full_name) ||
               name_matches("*PORT*", full_name) ||
               name_matches("*FORCE*", full_name) ||
               name_matches("*STATUS*", full_name) ||
               name_matches("*RECOVERY*", full_name) ||
               name_matches("*SecFwRecoveryIf*", full_name) ||
               name_matches("*TTI*", full_name) ||
               name_matches("*SoCMgmtIf*", full_name) ||
               name_matches("*DEVICE_ADDR*", full_name) ||
               name_matches("*DEV_CTX*", full_name);
    endfunction

    protected function uvm_reg_data_t field_mask(uvm_reg_field field_handle);
        uvm_reg_data_t mask;
        int unsigned field_width;

        field_width = field_handle.get_n_bits();
        mask = '1;
        if (field_width < $bits(mask))
            mask >>= ($bits(mask) - field_width);
        mask <<= field_handle.get_lsb_pos();
        return mask;
    endfunction

    protected function void classify_register(
        uvm_reg register_handle,
        output bit readable,
        output bit destructive_read,
        output bit unsafe_write_access,
        output uvm_reg_data_t writable_mask,
        output uvm_reg_data_t reset_mask,
        output uvm_reg_data_t reset_value
    );
        uvm_reg_field fields[$];
        uvm_reg_field field_handle;
        string access;
        uvm_reg_data_t mask;

        readable = 1'b0;
        destructive_read = 1'b0;
        unsafe_write_access = 1'b0;
        writable_mask = '0;
        reset_mask = '0;
        reset_value = '0;

        register_handle.get_fields(fields);
        foreach (fields[field_index]) begin
            field_handle = fields[field_index];
            access = field_handle.get_access(get_i3c_ral_model().default_map);
            mask = field_mask(field_handle);

            if (access != "WO")
                readable = 1'b1;
            if (access == "WRC" || access == "RC" || access == "RS")
                destructive_read = 1'b1;

            if (access == "RW" && !field_handle.is_volatile())
                writable_mask |= mask;
            else if (access != "RO" && access != "RW")
                unsafe_write_access = 1'b1;

            if (access != "WO" && access != "WRC" &&
                !field_handle.is_volatile() && field_handle.has_reset("HARD")) begin
                reset_mask |= mask;
                reset_value |= (field_handle.get_reset("HARD") <<
                                field_handle.get_lsb_pos()) & mask;
            end
        end
    endfunction

    protected task read_register(
        uvm_reg register_handle,
        output uvm_status_e status,
        output uvm_reg_data_t data
    );
        register_handle.read(status, data, UVM_FRONTDOOR,
                             get_i3c_ral_model().default_map, this);
    endtask

    protected task write_register(
        uvm_reg register_handle,
        input uvm_reg_data_t data,
        output uvm_status_e status
    );
        register_handle.write(status, data, UVM_FRONTDOOR,
                              get_i3c_ral_model().default_map, this);
    endtask

    protected function void record_failure(string report_id, string message);
        failure_count++;
        `uvm_error(report_id, message)
    endfunction

    protected task audit_register(uvm_reg register_handle,
                                  int unsigned register_index);
        bit readable;
        bit destructive_read;
        bit unsafe_write_access;
        bit read_completed;
        string full_name;
        uvm_reg_data_t writable_mask;
        uvm_reg_data_t reset_mask;
        uvm_reg_data_t reset_value;
        uvm_reg_data_t saved_data;
        uvm_reg_data_t read_data;
        uvm_reg_data_t pattern;
        uvm_reg_data_t write_data;
        uvm_status_e status;

        full_name = register_handle.get_full_name();
        classify_register(register_handle, readable, destructive_read,
                          unsafe_write_access, writable_mask,
                          reset_mask, reset_value);
        read_completed = 1'b0;

        if (!readable || destructive_read || has_read_side_effect(full_name)) begin
            read_skip_count++;
            `uvm_info("I3C_RAL_SKIP_READ", $sformatf(
                "[%0d/%0d] %s: unreadable or read side effect",
                register_index + 1, register_count, full_name), UVM_HIGH)
        end else begin
            read_attempt_count++;
            read_register(register_handle, status, saved_data);
            if (status != UVM_IS_OK) begin
                record_failure("I3C_RAL_READ", $sformatf(
                    "%s frontdoor read failed with status=%s",
                    full_name, status.name()));
            end else begin
                read_completed = 1'b1;
                if (reset_mask != '0) begin
                    reset_check_count++;
                    if ((saved_data & reset_mask) !== (reset_value & reset_mask))
                        record_failure("I3C_RAL_RESET", $sformatf(
                            "%s reset mismatch: expected=0x%0h actual=0x%0h mask=0x%0h",
                            full_name, reset_value, saved_data, reset_mask));
                end
            end
        end

        if (!read_completed || writable_mask == '0 || unsafe_write_access ||
            has_write_side_effect(full_name)) begin
            write_skip_count++;
            `uvm_info("I3C_RAL_SKIP_WRITE", $sformatf(
                "[%0d/%0d] %s: no safe stable RW field or write side effect",
                register_index + 1, register_count, full_name), UVM_HIGH)
            return;
        end

        write_register_count++;
        for (int unsigned pattern_index = 0; pattern_index < 2; pattern_index++) begin
            pattern = (pattern_index == 0) ?
                      uvm_reg_data_t'(128'h5555_5555_5555_5555_5555_5555_5555_5555) :
                      uvm_reg_data_t'(128'haaaa_aaaa_aaaa_aaaa_aaaa_aaaa_aaaa_aaaa);
            write_data = (saved_data & ~writable_mask) | (pattern & writable_mask);
            write_register(register_handle, write_data, status);
            if (status != UVM_IS_OK) begin
                record_failure("I3C_RAL_WRITE", $sformatf(
                    "%s pattern[%0d] write failed with status=%s",
                    full_name, pattern_index, status.name()));
                continue;
            end

            read_register(register_handle, status, read_data);
            if (status != UVM_IS_OK) begin
                record_failure("I3C_RAL_READBACK", $sformatf(
                    "%s pattern[%0d] readback failed with status=%s",
                    full_name, pattern_index, status.name()));
                continue;
            end

            write_check_count++;
            if ((read_data & writable_mask) !== (write_data & writable_mask))
                record_failure("I3C_RAL_READBACK", $sformatf(
                    "%s pattern[%0d] mismatch: expected=0x%0h actual=0x%0h mask=0x%0h",
                    full_name, pattern_index, write_data, read_data, writable_mask));
        end

        write_register(register_handle, saved_data, status);
        if (status != UVM_IS_OK)
            record_failure("I3C_RAL_RESTORE", $sformatf(
                "%s restore failed with status=%s", full_name, status.name()));
        else
            restore_count++;
    endtask

    protected function void report_summary();
        `uvm_info("I3C_RAL", "-------------------------------------------------", UVM_LOW)
        `uvm_info("I3C_RAL", " I3C FULL RAL REGISTER AUDIT SUMMARY", UVM_LOW)
        `uvm_info("I3C_RAL", $sformatf(" Registers inventoried : %0d", register_count), UVM_LOW)
        `uvm_info("I3C_RAL", $sformatf(" Memories inventoried  : %0d (reported, not 32-bit tested)", memory_count), UVM_LOW)
        `uvm_info("I3C_RAL", $sformatf(" Read attempts         : %0d", read_attempt_count), UVM_LOW)
        `uvm_info("I3C_RAL", $sformatf(" Read skips            : %0d", read_skip_count), UVM_LOW)
        `uvm_info("I3C_RAL", $sformatf(" Reset-value checks    : %0d", reset_check_count), UVM_LOW)
        `uvm_info("I3C_RAL", $sformatf(" RW registers tested   : %0d", write_register_count), UVM_LOW)
        `uvm_info("I3C_RAL", $sformatf(" RW pattern checks     : %0d", write_check_count), UVM_LOW)
        `uvm_info("I3C_RAL", $sformatf(" Write skips           : %0d", write_skip_count), UVM_LOW)
        `uvm_info("I3C_RAL", $sformatf(" Registers restored    : %0d", restore_count), UVM_LOW)
        `uvm_info("I3C_RAL", $sformatf(" Failures              : %0d", failure_count), UVM_LOW)
        if (failure_count == 0)
            `uvm_info("I3C_RAL", " PASSED: all modeled safe accesses matched", UVM_LOW)
        else
            `uvm_error("I3C_RAL", $sformatf(
                " FAILED: %0d RAL check failure(s)", failure_count))
        `uvm_info("I3C_RAL", "-------------------------------------------------", UVM_LOW)
    endfunction

    virtual task body();
        i3c_ral_model ral_model;
        uvm_reg registers[$];
        uvm_mem memories[$];

        super.body();
        if (!vseq_ctx.cfg.has_rtl)
            `uvm_fatal("I3C_RAL_MODE", "RAL all-register test requires native I3C RTL mode")

        ral_model = get_i3c_ral_model();
        ral_model.reset("HARD");
        ral_model.get_registers(registers, UVM_HIER);
        ral_model.get_memories(memories, UVM_HIER);
        register_count = registers.size();
        memory_count = memories.size();

        if (register_count < MIN_EXPECTED_REGISTERS)
            `uvm_fatal("I3C_RAL_INVENTORY", $sformatf(
                "RAL model is incomplete: expected at least %0d registers, found %0d",
                MIN_EXPECTED_REGISTERS, register_count))

        foreach (registers[register_index])
            audit_register(registers[register_index], register_index);

        if (register_count != (read_attempt_count + read_skip_count))
            record_failure("I3C_RAL_ACCOUNTING", $sformatf(
                "Read accounting mismatch: total=%0d attempts=%0d skips=%0d",
                register_count, read_attempt_count, read_skip_count));
        if (register_count != (write_register_count + write_skip_count))
            record_failure("I3C_RAL_ACCOUNTING", $sformatf(
                "Write accounting mismatch: total=%0d tested=%0d skips=%0d",
                register_count, write_register_count, write_skip_count));

        report_summary();
    endtask
endclass : i3c_ral_all_regs_vseq
