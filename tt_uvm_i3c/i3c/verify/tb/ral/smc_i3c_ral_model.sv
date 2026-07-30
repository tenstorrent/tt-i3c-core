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
// File        : smc_i3c_ral_model.sv
// Description : I3C register-model wrapper for the AXI4-Lite frontdoor.
// Authors     : Duy Huynh, Dang Thai
// Date        : 2026-07-18
//
// *****************************************************************************

class smc_i3c_ral_model extends I3CCSR;
    function new(string name = "smc_i3c_ral_model");
        super.new(name);
    endfunction

    virtual function void build();
        // The upstream root map is a 16-byte UVM_NO_ENDIAN map. This environment reaches
        // these registers through a 32-bit little-endian AXI-Lite frontdoor.
        this.default_map = create_map("reg_map", 0, 4, UVM_LITTLE_ENDIAN);

        this.I3CBase = new("I3CBase");
        this.I3CBase.configure(this);
        this.I3CBase.build();
        this.default_map.add_submap(this.I3CBase.default_map, 'h0);

        this.PIOControl = new("PIOControl");
        this.PIOControl.configure(this);
        this.PIOControl.build();
        this.default_map.add_submap(this.PIOControl.default_map, 'h80);

        this.I3C_EC = new("I3C_EC");
        this.I3C_EC.configure(this);
        this.I3C_EC.build();
        this.default_map.add_submap(this.I3C_EC.default_map, 'h100);

        this.DAT = new("DAT");
        this.DAT.configure(this);
        this.DAT.build();
        this.default_map.add_submap(this.DAT.default_map, 'h400);

        this.DCT = new("DCT");
        this.DCT.configure(this);
        this.DCT.build();
        this.default_map.add_submap(this.DCT.default_map, 'h800);
    endfunction
endclass : smc_i3c_ral_model
