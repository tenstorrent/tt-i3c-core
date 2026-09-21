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
// File        : i3c_vseq_pkg.sv
// Description : Package for I3C virtual sequences.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-07
//
// *****************************************************************************

package i3c_vseq_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Wildcard imports are NOT transitive: env_pkg importing these does not
    // re-export them here, so the vseqs (axi4lite_base_seq, TB_*_WIDTH) need
    // their own imports.
    import i3c_tb_params_pkg::*;
    import axi4lite_vip_pkg::*;
    import i3c_coverage_pkg::*;
    import i3c_env_pkg::*;
`ifdef I3C_DV_NATIVE_RTL
    import i3c_vip_pkg::*;
`endif
`ifdef I3C_DV_NATIVE_RAL
    import I3CCSR_uvm::*;
    import i3c_ral_pkg::*;
`endif

    `include "i3c_base_vseq.sv"
    `include "common/i3c_csr_smoke_seq.sv"
    `include "common/i3c_csr_smoke_vseq.sv"
    `include "common/i3c_sanity_vseq.sv"
`ifdef I3C_DV_NATIVE_RTL
    `include "i3c_host_accept_ibi_seq.sv"
    `include "i3c_target_send_ibi_seq.sv"
    `include "i3c_target_private_write_seq.sv"
    `include "i3c_target_private_read_seq.sv"
`endif
    `include "ibi/base/i3c_ibi_base_vseq.sv"
    `include "i3c_ibi_random_plan.sv"
    `include "ibi/base/i3c_ibi_random_base_vseq.sv"
    `include "ibi/target_tx/i3c_ibi_target_tx_random_vseq.sv"
    `include "ibi/target_tx/i3c_ibi_target_tx_stress_vseq.sv"
    `include "ibi/target_tx/i3c_ibi_target_tx_basic_vseq.sv"
    `include "ibi/target_tx/i3c_ibi_target_tx_ack_nack_vseq.sv"
    `include "ibi/target_tx/i3c_ibi_target_tx_recovery_cleanup_vseq.sv"
    `include "ibi/target_tx/i3c_ibi_target_tx_retry_arbitration_vseq.sv"
    `include "ibi/target_tx/i3c_ibi_target_tx_mdb_payload_vseq.sv"
    `include "ibi/target_tx/i3c_ibi_target_tx_fifo_irq_vseq.sv"
    `include "ibi/controller_rx/i3c_ibi_controller_rx_basic_vseq.sv"
    `include "ibi/controller_rx/i3c_ibi_controller_rx_content_vseq.sv"
    `include "ibi/controller_rx/i3c_ibi_controller_rx_fifo_irq_vseq.sv"
    `include "ibi/controller_rx/i3c_ibi_controller_rx_policy_vseq.sv"
    `include "ibi/controller_rx/i3c_ibi_controller_rx_no_mdb_vseq.sv"
    `include "ibi/controller_rx/i3c_ibi_controller_rx_random_vseq.sv"
    `include "ibi/controller_rx/i3c_ibi_controller_rx_multi_target_vseq.sv"
    `include "ibi/target_tx/i3c_ibi_target_tx_multi_target_vseq.sv"
    // The DUT-loss context closure can run the checked Private Write/IBI
    // sequence as a real preceding transfer before contested arbitration.
    `include "ibi/target_tx/i3c_ibi_target_tx_busy_bus_block_vseq.sv"
    `include "ibi/target_tx/i3c_ibi_target_tx_dut_loss_vseq.sv"
    `include "ibi/controller_rx/i3c_ibi_controller_rx_timing_context_vseq.sv"
    `include "ibi/controller_rx/i3c_ibi_controller_rx_reset_flush_vseq.sv"
    `include "ibi/controller_rx/i3c_ibi_controller_rx_recovery_cleanup_vseq.sv"
    `include "ibi/controller_rx/i3c_ibi_controller_rx_soft_rst_selfclear_vseq.sv"
    `include "ibi/controller_rx/i3c_ibi_controller_rx_mdb_decode_vseq.sv"
    `include "ibi/controller_rx/i3c_ibi_controller_rx_pending_read_notification_vseq.sv"
    `include "ibi/target_tx/i3c_ibi_target_tx_overflow_vseq.sv"
    `include "ibi/target_tx/i3c_ibi_target_tx_invalid_target_vseq.sv"
    `include "ibi/base/i3c_ibi_multi_target_compat_vseqs.sv"
`ifdef I3C_DV_NATIVE_RAL
    `include "common/i3c_ral_all_regs_vseq.sv"
`endif
endpackage : i3c_vseq_pkg
