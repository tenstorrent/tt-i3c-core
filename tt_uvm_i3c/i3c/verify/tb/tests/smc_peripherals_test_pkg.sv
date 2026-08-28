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
// File        : smc_peripherals_test_pkg.sv
// Description : UVM test package for SMC peripherals.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-07
//
// *****************************************************************************

package smc_peripherals_test_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import smc_peripherals_tb_params_pkg::*;
    import axi4lite_vip_pkg::*;
    import smc_i3c_coverage_pkg::*;
    import smc_peripherals_env_pkg::*;
    import smc_peripherals_vseq_pkg::*;

    `include "smc_peripherals_base_test.sv"
    `include "common/smc_i3c_csr_smoke_test.sv"
    `include "common/smc_i3c_sanity_test.sv"
    `include "ibi/base/smc_i3c_ibi_base_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_random_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_stress_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_basic_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_ack_nack_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_recovery_cleanup_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_retry_arbitration_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_retry_exhaustion_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_mdb_payload_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_partial_recovery_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_fifo_irq_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_basic_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_content_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_fifo_irq_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_policy_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_no_mdb_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_random_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_multi_target_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_multi_target_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_dut_loss_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_dut_win_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_timing_context_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_reset_flush_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_recovery_cleanup_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_soft_rst_selfclear_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_mdb_decode_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_pending_read_notification_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_overflow_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_overflow_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_invalid_target_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_busy_bus_block_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_multi_target_addr_matrix_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_multi_target_retry_limit_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_multi_target_timing_test.sv"
    `include "ibi/target_tx/smc_i3c_ibi_target_tx_multi_target_content_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_multi_target_ordering_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_multi_target_ack_nack_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_controller_rx_multi_target_queue_pressure_test.sv"
    `include "ibi/controller_rx/smc_i3c_ibi_multi_target_recovery_test.sv"
`ifdef SMC_USE_I3C_RAL
    `include "common/smc_i3c_ral_all_regs_test.sv"
`endif
endpackage : smc_peripherals_test_pkg
