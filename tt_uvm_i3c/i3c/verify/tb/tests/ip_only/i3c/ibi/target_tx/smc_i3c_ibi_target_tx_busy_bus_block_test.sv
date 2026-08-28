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
// File        : smc_i3c_ibi_target_tx_busy_bus_block_test.sv
// Description : Target-TX IBI exclusion/retry around an active bus transfer.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-06
// *****************************************************************************

`ifndef SMC_I3C_IBI_TARGET_TX_BUSY_BUS_BLOCK_TEST_SV
`define SMC_I3C_IBI_TARGET_TX_BUSY_BUS_BLOCK_TEST_SV

class smc_i3c_ibi_target_tx_busy_bus_block_test extends smc_i3c_ibi_base_test;
  `uvm_component_utils(smc_i3c_ibi_target_tx_busy_bus_block_test)

  function new(string name = "smc_i3c_ibi_target_tx_busy_bus_block_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function smc_peripherals_base_vseq create_vseq();
    return smc_i3c_ibi_target_tx_busy_bus_block_vseq::type_id::create("vseq");
  endfunction
endclass : smc_i3c_ibi_target_tx_busy_bus_block_test

`endif // SMC_I3C_IBI_TARGET_TX_BUSY_BUS_BLOCK_TEST_SV
