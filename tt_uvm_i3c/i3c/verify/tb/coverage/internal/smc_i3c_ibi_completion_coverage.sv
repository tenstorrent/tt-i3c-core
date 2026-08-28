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
// File        : smc_i3c_ibi_completion_coverage.sv
// Description : Functional coverage collector for I3C IBI completion.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-21
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_COMPLETION_COVERAGE_SV
`define SMC_I3C_IBI_COMPLETION_COVERAGE_SV

class smc_i3c_ibi_completion_coverage extends uvm_object;
  `uvm_object_utils(smc_i3c_ibi_completion_coverage)

  // Normalized MDB classes avoid sampling stale values when absent.
  localparam bit [2:0] MDB_NONE = 3'd0, MDB_GRP_000 = 3'd1,
                       MDB_GRP_001 = 3'd2, MDB_GRP_101 = 3'd3,
                       MDB_OTHER = 3'd4;
  // Payload policy encoding.
  localparam bit [1:0] POL_NONE = 2'd0, POL_MAND = 2'd1, POL_OPT = 2'd2;
  // arb_outcome / event_enable mirror encodings.
  localparam bit [1:0] ARB_SOLE = 2'd0, ARB_WON = 2'd1, ARB_LOST = 2'd2;

  protected bit         cov_ack;
  protected int unsigned cov_retry_count;
  protected ibi_terminal_status_e cov_terminal_status;
  protected bit         cov_mdb_present;
  protected bit [2:0]   cov_mdb_class;
  protected int unsigned cov_payload_len;
  protected bit         cov_dat_match;
  protected bit [1:0]   cov_payload_policy;
  protected ibi_error_kind_e cov_reset_error_kind;
  protected ibi_recovery_result_e cov_recovery_result;
  protected int unsigned dat_illegal_count = 0;
  protected int unsigned enable_illegal_count = 0;
  protected int unsigned recovery_contract_count = 0;
  protected int unsigned policy_contract_count = 0;
  // Mirrored ATTEMPT context.
  protected bit         cov_attempt_ctx_valid;
  protected bit         cov_role_ctx;
  protected bit [1:0]   cov_arb_outcome_ctx;
  protected bit         cov_ibi_enabled_ctx;

  covergroup cg_ibi_completion;
    option.per_instance = 1;
    option.goal         = 100;

    cp_response: coverpoint cov_ack {
      bins nack = {0};
      bins ack  = {1};
    }

    cp_retry_count: coverpoint cov_retry_count {
      bins none = {0};
      bins one  = {1};
      bins few  = {[2:3]};
      bins many = {[4:$]};
    }

    cp_terminal_status: coverpoint cov_terminal_status {
      bins success         = {IBI_STATUS_SUCCESS};
      bins failure_nack    = {IBI_STATUS_FAILURE_NACK};
      bins failure_partial = {IBI_STATUS_FAILURE_PARTIAL_DATA};
      bins failure_retry   = {IBI_STATUS_FAILURE_RETRY};
      bins failure_addr_arb = {IBI_STATUS_FAILURE_ADDRESS_ARB};
      illegal_bins undefined = default;
    }

    cp_mdb_present: coverpoint cov_mdb_present {
      option.weight = 0;
      bins absent  = {0};
      bins present = {1};
    }

    // Includes an explicit no-MDB class so absent data never samples group 000.
    cp_mdb_group: coverpoint cov_mdb_class {
      bins absent   = {MDB_NONE};
      bins grp_000  = {MDB_GRP_000};
      bins grp_001  = {MDB_GRP_001};
      bins grp_101  = {MDB_GRP_101};
      bins other    = {MDB_OTHER};
    }

    cp_payload_len: coverpoint cov_payload_len {
      bins none           = {0};
      bins one            = {1};
      bins short_payload  = {[2:4]};
      bins medium_payload = {[5:8]};
      bins long_payload   = {[9:$]};
    }

    // DAT policy applies only when the DUT is the receiving controller.
    cp_dat_decision: coverpoint {cov_dat_match, cov_ack}
                     iff (cov_attempt_ctx_valid && cov_role_ctx) {
      bins match_accept    = {2'b11};
      bins match_reject    = {2'b10};
      bins nomatch_reject  = {2'b00};
`ifdef SMC_I3C_COV_STRICT_ILLEGAL
      illegal_bins nomatch_accept = {2'b01};
`else
      ignore_bins nomatch_accept = {2'b01};
`endif
    }

    cp_payload_policy: coverpoint cov_payload_policy
                       iff (cov_attempt_ctx_valid && cov_role_ctx) {
      bins none      = {POL_NONE};
      bins mandatory = {POL_MAND};
      bins optional  = {POL_OPT};
    }

    cp_reset_error_kind: coverpoint cov_reset_error_kind {
      bins none        = {IBI_ERR_NONE};
      bins proto_error = {IBI_ERR_PROTOCOL};
      // Reset/flush, overflow and abort are published as IBI_EVT_RECOVERY and
      // scored by cg_ibi_recovery. They never traverse sample_completion().
      ignore_bins recovery_owned = {IBI_ERR_RESET_FLUSH,
                                     IBI_ERR_OVERFLOW,
                                     IBI_ERR_ABORT};
    }

    // ---- mirror coverpoints (weight 0: crosses only, no score impact) ----
    cp_arb_outcome_h: coverpoint cov_arb_outcome_ctx iff (cov_attempt_ctx_valid) {
      option.weight = 0;
      bins sole = {ARB_SOLE};
      bins won  = {ARB_WON};
      bins lost = {ARB_LOST};
      ignore_bins no_contention = {ARB_WON, ARB_LOST}
                                  iff (TB_MAX_IBI_REQUESTERS == 1);
    }
    cp_event_enable_h: coverpoint cov_ibi_enabled_ctx iff (cov_attempt_ctx_valid) {
      option.weight = 0;
      bins en_off = {0};
      bins en_on  = {1};
    }

    // A NACKed IBI transfers no MDB/payload; ignore those impossible cells.
    x_content: cross cp_mdb_group, cp_payload_len, cp_response {
      ignore_bins nack_with_mdb =
        binsof(cp_response.nack) && !binsof(cp_mdb_group.absent);
      ignore_bins nack_with_payload =
        binsof(cp_response.nack) && !binsof(cp_payload_len.none);
      ignore_bins absent_mdb_with_payload =
        binsof(cp_mdb_group.absent) && !binsof(cp_payload_len.none);
      // The pinned Controller requires an MDB for every accepted IBI. An
      // address-only ACK is therefore outside the supported architecture.
      ignore_bins accepted_without_mdb =
        binsof(cp_response.ack) && binsof(cp_mdb_group.absent);
    }

    x_response: cross cp_response, cp_retry_count, cp_payload_len {
      ignore_bins nack_with_payload =
        binsof(cp_response.nack) && !binsof(cp_payload_len.none);
    }

    x_policy: cross cp_dat_decision, cp_payload_policy, cp_mdb_present {
      ignore_bins reject_with_mdb =
        (binsof(cp_dat_decision.match_reject) ||
         binsof(cp_dat_decision.nomatch_reject)) &&
        binsof(cp_mdb_present.present);
      ignore_bins nomatch_without_policy =
        binsof(cp_dat_decision.nomatch_reject) &&
        (binsof(cp_payload_policy.mandatory) ||
         binsof(cp_payload_policy.optional));
      ignore_bins accepted_without_mdb =
        binsof(cp_dat_decision.match_accept) &&
        binsof(cp_mdb_present.absent);
      // A match decision is derived from a DAT entry, whose payload field is
      // mandatory or optional; POL_NONE is reserved for no-match handling.
      ignore_bins matched_without_policy =
        (binsof(cp_dat_decision.match_accept) ||
         binsof(cp_dat_decision.match_reject)) &&
        binsof(cp_payload_policy.none);
      // In the pinned Controller model the DAT payload-enable bit gates IBI
      // acceptance. POL_MAND represents that bit clear, so it cannot combine
      // with match_accept.
      ignore_bins mandatory_accept =
        binsof(cp_dat_decision.match_accept) &&
        binsof(cp_payload_policy.mandatory);
    }

    // The Controller scoreboard classifies a partial-data completion as a
    // protocol error. Other terminal outcomes are protocol-clean completion
    // statuses; recovery causes are owned by cg_ibi_recovery.
    x_error_status: cross cp_reset_error_kind, cp_terminal_status {
      ignore_bins protocol_non_partial =
        binsof(cp_reset_error_kind.proto_error) &&
        !binsof(cp_terminal_status.failure_partial);
      ignore_bins clean_partial =
        binsof(cp_reset_error_kind.none) &&
        binsof(cp_terminal_status.failure_partial);
    }

    // Keep requirement-owned relationships independently diagnosable. The
    // former five-dimensional x_master multiplied content, policy and
    // arbitration into many cells that had no distinct requirement meaning.
    // Content is already closed by x_content; these crosses retain the two
    // protocol relationships that matter at completion.
    x_enable_decision: cross cp_dat_decision, cp_event_enable_h {
`ifdef SMC_I3C_COV_STRICT_ILLEGAL
      illegal_bins disabled_accept =
        binsof(cp_event_enable_h.en_off) && binsof(cp_dat_decision.match_accept);
`else
      ignore_bins disabled_accept =
        binsof(cp_event_enable_h.en_off) && binsof(cp_dat_decision.match_accept);
`endif
      // ibi_enabled is derived from a valid DAT match. A no-match rejection
      // therefore cannot carry enabled context.
      ignore_bins nomatch_enabled =
        binsof(cp_dat_decision.nomatch_reject) &&
        binsof(cp_event_enable_h.en_on);
    }

    x_arb_response: cross cp_arb_outcome_h, cp_response {
      // An arbitration loser releases the bus before the Controller response
      // phase, so neither ACK nor NACK can be attributed to that attempt.
      ignore_bins lost_response = binsof(cp_arb_outcome_h.lost);
    }
  endgroup

  function new(string name = "smc_i3c_ibi_completion_coverage");
    super.new(name);
    cg_ibi_completion = new();
  endfunction

  virtual function void sample_completion(input bit          ack,
                                           input int unsigned retry_count,
                                           input ibi_terminal_status_e terminal_status,
                                           input bit          mdb_present,
                                           input bit [7:0]    mdb,
                                           input int unsigned payload_len,
                                           input bit          dat_match,
                                           input bit [1:0]    payload_policy,
                                           input ibi_error_kind_e reset_error_kind,
                                           input ibi_recovery_result_e recovery_result,
                                           input bit          attempt_ctx_valid,
                                           input bit          role_ctx,
                                           input bit [1:0]    arb_outcome_ctx,
                                           input bit          ibi_enabled_ctx);
    cov_ack              = ack;
    cov_retry_count      = retry_count;
    cov_terminal_status  = terminal_status;
    cov_mdb_present      = mdb_present;
    cov_payload_len      = payload_len;
    if (!mdb_present)
      cov_mdb_class = MDB_NONE;
    else begin
      case (mdb[7:5])
        3'b000: cov_mdb_class = MDB_GRP_000;
        3'b001: cov_mdb_class = MDB_GRP_001;
        3'b101: cov_mdb_class = MDB_GRP_101;
        default: cov_mdb_class = MDB_OTHER;
      endcase
    end
    cov_dat_match        = dat_match;
    cov_payload_policy   = payload_policy;
    cov_reset_error_kind = reset_error_kind;
    cov_recovery_result  = recovery_result;
    cov_attempt_ctx_valid = attempt_ctx_valid;
    cov_role_ctx         = role_ctx;
    cov_arb_outcome_ctx  = arb_outcome_ctx;
    cov_ibi_enabled_ctx  = ibi_enabled_ctx;
    if (((reset_error_kind == IBI_ERR_NONE) &&
         (recovery_result != IBI_RECOVERY_NA)) ||
        ((reset_error_kind != IBI_ERR_NONE) &&
         (recovery_result == IBI_RECOVERY_NA))) begin
      recovery_contract_count++;
      if (recovery_contract_count == 1)
        `uvm_warning("IBI_COV_RECOVERY",
                     "Recovery result violates the coverage contract: NONE requires NA; an error requires RECOVERED or NOT_RECOVERED")
    end
    if (attempt_ctx_valid && role_ctx && !dat_match &&
        (payload_policy != POL_NONE)) begin
      policy_contract_count++;
      if (policy_contract_count == 1)
        `uvm_warning("IBI_COV_POLICY",
                     "Observed a non-NONE payload policy without a matched DAT entry")
    end
`ifndef SMC_I3C_COV_STRICT_ILLEGAL
    if (attempt_ctx_valid && role_ctx && !dat_match && ack) begin
      dat_illegal_count++;
      if (dat_illegal_count == 1)
        `uvm_warning("IBI_COV_DAT",
                     "Observed ACK without DAT match; strict coverage mode would classify this as illegal")
    end
    if (attempt_ctx_valid && !ibi_enabled_ctx && dat_match && ack) begin
      enable_illegal_count++;
      if (enable_illegal_count == 1)
        `uvm_warning("IBI_COV_ENABLE",
                     "Observed accepted IBI while disabled; strict coverage mode would classify this as illegal")
    end
`endif
    cg_ibi_completion.sample();
  endfunction

endclass : smc_i3c_ibi_completion_coverage

`endif // SMC_I3C_IBI_COMPLETION_COVERAGE_SV
