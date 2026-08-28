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
// File        : smc_i3c_portable_services.sv
// Description : Service interface for I3C child.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-14
//
// *****************************************************************************

virtual class smc_i3c_portable_services extends uvm_object;
    function new(string name = "smc_i3c_portable_services");
        super.new(name);
    endfunction
    pure virtual task wait_for_reset_release();
endclass : smc_i3c_portable_services
