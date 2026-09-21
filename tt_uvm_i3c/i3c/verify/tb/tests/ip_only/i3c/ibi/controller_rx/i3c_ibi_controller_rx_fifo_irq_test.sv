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
// File        : i3c_ibi_controller_rx_fifo_irq_test.sv
// Description : UVM test for Controller-RX IBI FIFO threshold and IRQ.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-04
//
// *****************************************************************************

`ifndef I3C_IBI_CONTROLLER_RX_FIFO_IRQ_TEST_SV
`define I3C_IBI_CONTROLLER_RX_FIFO_IRQ_TEST_SV

// Accumulates accepted IBI records before software reads IBI_PORT. The vseq
// checks the below/at-threshold boundary, signal masking, coalesced queue IRQ,
// FIFO ordering, full-queue NACK handling, descriptor content, drain
// deassertion and the PIO W1C interrupt path.
class i3c_ibi_controller_rx_fifo_irq_test extends
    i3c_ibi_controller_rx_basic_test;
  `uvm_component_utils(i3c_ibi_controller_rx_fifo_irq_test)

  function new(string name = "i3c_ibi_controller_rx_fifo_irq_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // IBI_STATUS_THLD is a queue-level interrupt. One assertion can cover
    // multiple records, so the observer must not demand one edge per record.
    cfg.require_ibi_controller_record_irq = 1'b0;
  endfunction

  virtual function i3c_base_vseq create_vseq();
    return i3c_ibi_controller_rx_fifo_irq_vseq::type_id::create("vseq");
  endfunction
endclass : i3c_ibi_controller_rx_fifo_irq_test

`endif // I3C_IBI_CONTROLLER_RX_FIFO_IRQ_TEST_SV
