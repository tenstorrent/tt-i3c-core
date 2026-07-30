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
// File        : smc_peripherals_report_pkg.sv
// Description : UVM report-formatting package for SMC peripherals.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-16
//
// *****************************************************************************

package smc_peripherals_report_pkg;
    import uvm_pkg::*;

    class smc_peripherals_report_server extends uvm_pkg::uvm_default_report_server;
        string s_red    = "\033[31m";
        string s_green  = "\033[32m";
        string s_yellow = "\033[33m";
        string s_blue   = "\033[34m";
        string s_reset  = "\033[0m";

        virtual function string compose_report_message(
                uvm_pkg::uvm_report_message report_message,
                string report_object_name = "");
            uvm_pkg::uvm_severity severity;
            string id;
            string message;
            string filename;
            string short_file;
            string color_code;
            string severity_str;

            severity = report_message.get_severity();
            id       = report_message.get_id();
            message  = report_message.get_message();
            filename = report_message.get_filename();

            for (int i = filename.len() - 1; i >= 0; i--) begin
                if (filename[i] == "/" || filename[i] == "\\") begin
                    short_file = filename.substr(i + 1, filename.len() - 1);
                    break;
                end
            end
            if (short_file == "") short_file = filename;

            case (severity)
                uvm_pkg::UVM_INFO: begin
                    color_code = s_green;
                    severity_str = "INFO";
                end
                uvm_pkg::UVM_WARNING: begin
                    color_code = s_yellow;
                    severity_str = "WARNING";
                end
                uvm_pkg::UVM_ERROR: begin
                    color_code = s_red;
                    severity_str = "ERROR";
                end
                uvm_pkg::UVM_FATAL: begin
                    color_code = s_blue;
                    severity_str = "FATAL";
                end
                default: begin
                    color_code = s_reset;
                    severity_str = "UNKNOWN";
                end
            endcase

            return $sformatf("%s%-8s @ %-10t %-25s %-20s: %s%s",
                             color_code, severity_str, $time,
                             short_file, id, message, s_reset);
        endfunction
    endclass : smc_peripherals_report_server
endpackage : smc_peripherals_report_pkg
