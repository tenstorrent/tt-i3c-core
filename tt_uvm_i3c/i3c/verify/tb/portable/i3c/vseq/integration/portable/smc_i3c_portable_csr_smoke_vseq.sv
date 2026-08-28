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
// File        : smc_i3c_portable_csr_smoke_vseq.sv
// Description : Virtual sequence for I3C child CSR smoke.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-14
//
// *****************************************************************************

class smc_i3c_portable_csr_smoke_vseq extends smc_i3c_portable_base_vseq;
    `uvm_object_utils(smc_i3c_portable_csr_smoke_vseq)
    function new(string name = "smc_i3c_portable_csr_smoke_vseq");
        super.new(name);
    endfunction
    virtual task body();
        bit [31:0] data;
        bit [1:0] response;
        require_context();
        context.csr_api.read_csr(SMC_I3C_HCI_VERSION_OFFSET, data, response);
        if (response != 2'b00 || data != SMC_I3C_HCI_VERSION_RESET)
            `uvm_error(get_type_name(), $sformatf(
                "HCI_VERSION response=%0b data=0x%08h", response, data))
    endtask
endclass : smc_i3c_portable_csr_smoke_vseq
