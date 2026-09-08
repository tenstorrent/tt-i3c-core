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
// File        : i3c_ibi_attempt_coverage.sv
// Description : Functional coverage collector for I3C IBI attempt.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-07-21
//
// *****************************************************************************

`ifndef I3C_IBI_ATTEMPT_COVERAGE_SV
`define I3C_IBI_ATTEMPT_COVERAGE_SV

class i3c_ibi_attempt_coverage extends uvm_object;
  `uvm_object_utils(i3c_ibi_attempt_coverage)

  // arb_outcome / bus_state encodings (mirror i3c_ibi_item).
  localparam bit [1:0] ARB_SOLE = 2'd0, ARB_WON = 2'd1, ARB_LOST = 2'd2;
  localparam bit [1:0] BUS_AVAIL = 2'd0, BUS_START = 2'd1,
                       BUS_AFTER = 2'd2, BUS_BUSY  = 2'd3;

  protected bit         cov_role;
  protected bit [2:0]   cov_src_instance;
  protected bit         cov_ibi_enabled;
  protected bit [6:0]   cov_ibi_addr;
  protected ibi_addr_class_e cov_addr_class;
  protected bit         cov_addr_class_valid;
  protected bit [7:0]   cov_bcr;
  protected int unsigned cov_requester_count;
  protected bit [1:0]   cov_arb_outcome;
  protected bit [1:0]   cov_bus_state;
  protected int unsigned bcr_illegal_count = 0;

  covergroup cg_ibi_attempt;
    option.per_instance = 1;
    option.goal         = 100;

    cp_role: coverpoint cov_role {
      bins target     = {0};
      bins controller = {1};
    }

    // Active and reserved instance bins follow the central TB configuration.
    cp_source_instance: coverpoint cov_src_instance {
      bins active[] = {[0:TB_MAX_I3C_INSTANCES-1]}
                      with (item < TB_NUM_I3C_INSTANCES);
      ignore_bins inactive = {[0:TB_MAX_I3C_INSTANCES-1]}
                             with (item >= TB_NUM_I3C_INSTANCES);
      ignore_bins oob = {[0:$]}
                        with (item >= TB_MAX_I3C_INSTANCES);
    }

    cp_event_enable: coverpoint cov_ibi_enabled {
      bins en_off = {0};
      bins en_on  = {1};
    }

    // ATTEMPT is published only after a legal IBI has started. Reserved and
    // broadcast addresses belong to the pre-attempt eligibility/blocked
    // checks; scoring them here would require the DUT to start an illegal IBI.
    cp_target_addr_class: coverpoint cov_addr_class iff (cov_addr_class_valid) {
      bins valid     = {IBI_ADDR_VALID};
      ignore_bins reserved  = {IBI_ADDR_RESERVED};
      ignore_bins broadcast = {IBI_ADDR_BROADCAST};
    }

    // This group measures started IBI attempts. BCR[1]==0 is an eligibility
    // rejection and therefore cannot legally reach this sampling point. The
    // reviewed native core also requires an MDB for every accepted IBI; accepted
    // no-MDB operation is tracked as NO MEASURE in the IBI vplan.
    cp_ibi_capable: coverpoint cov_bcr[1] {
      ignore_bins no = {0};
      bins yes = {1};
    }
    cp_mdb_capable: coverpoint cov_bcr[2] {
      ignore_bins no = {0};
      bins yes = {1};
    }
    // Both negative capability values are ignored above, leaving only the
    // legal accepted-attempt capability combination in this cross.
    x_bcr_capability: cross cp_ibi_capable, cp_mdb_capable;

    cp_requester_count: coverpoint cov_requester_count {
      bins single = {1};
      bins two    = {2};
      bins three  = {3};
      bins four   = {4};
      ignore_bins above_configured = {[TB_MAX_IBI_REQUESTERS+1:$]};
    }

    cp_arb_outcome: coverpoint cov_arb_outcome {
      bins sole = {ARB_SOLE};
      bins won  = {ARB_WON};
      bins lost = {ARB_LOST};
      ignore_bins no_contention = {ARB_WON, ARB_LOST}
                                  iff (TB_MAX_IBI_REQUESTERS == 1);
    }

    cp_bus_state: coverpoint cov_bus_state {
      bins bus_available = {BUS_AVAIL};
      bins bus_start     = {BUS_START};
      bins after_xfer    = {BUS_AFTER};
      // ATTEMPT is sampled only after IBI_START. A request blocked while busy
      // must be observed before IBI_START by SVA/checker coverage.
      ignore_bins busy   = {BUS_BUSY};
    }

    // A single requester is always sole; multi-requester resolves win/lose.
    x_arb: cross cp_requester_count, cp_arb_outcome {
      ignore_bins single_contested =
        binsof(cp_requester_count.single) &&
        (binsof(cp_arb_outcome.won) || binsof(cp_arb_outcome.lost));
      ignore_bins multi_sole =
        (binsof(cp_requester_count.two) ||
         binsof(cp_requester_count.three) ||
         binsof(cp_requester_count.four)) &&
        binsof(cp_arb_outcome.sole);
    }

    x_entry: cross cp_bus_state, cp_arb_outcome;
  endgroup

  function new(string name = "i3c_ibi_attempt_coverage");
    super.new(name);
    if ((TB_NUM_I3C_INSTANCES == 0) ||
        (TB_NUM_I3C_INSTANCES > TB_MAX_I3C_INSTANCES) ||
        (TB_MAX_I3C_INSTANCES > 8) ||
        (TB_MAX_IBI_REQUESTERS == 0))
      `uvm_fatal("IBI_COV_CFG",
                 $sformatf("Invalid I3C coverage configuration: active=%0d max=%0d max_requesters=%0d",
                           TB_NUM_I3C_INSTANCES, TB_MAX_I3C_INSTANCES,
                           TB_MAX_IBI_REQUESTERS))
    cg_ibi_attempt = new();
  endfunction

  virtual function void sample_attempt(input bit          role,
                                       input bit [2:0]    src_instance,
                                       input bit [6:0]    ibi_addr,
                                       input ibi_addr_class_e addr_class,
                                       input bit          addr_class_valid,
                                       input bit [7:0]    bcr,
                                       input bit          ibi_enabled,
                                       input int unsigned requester_count,
                                       input bit [1:0]    arb_outcome,
                                       input bit [1:0]    bus_state);
    cov_role            = role;
    cov_src_instance    = src_instance;
    cov_ibi_addr        = ibi_addr;
    cov_addr_class      = addr_class;
    cov_addr_class_valid = addr_class_valid;
    cov_bcr             = bcr;
    cov_ibi_enabled     = ibi_enabled;
    cov_requester_count = requester_count;
    cov_arb_outcome     = arb_outcome;
    cov_bus_state       = bus_state;
`ifndef I3C_COV_STRICT_ILLEGAL
    if (!bcr[1] && bcr[2]) begin
      bcr_illegal_count++;
      if (bcr_illegal_count == 1)
        `uvm_warning("IBI_COV_BCR",
                     "Observed MDB capability without IBI capability; strict coverage mode would classify this as illegal")
    end
`endif
    cg_ibi_attempt.sample();
  endfunction

endclass : i3c_ibi_attempt_coverage

`endif // I3C_IBI_ATTEMPT_COVERAGE_SV
