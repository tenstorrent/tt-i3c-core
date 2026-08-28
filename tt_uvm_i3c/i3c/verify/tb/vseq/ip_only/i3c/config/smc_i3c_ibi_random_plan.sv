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
// File        : smc_i3c_ibi_random_plan.sv
// Description : Reproducible constrained-random I3C IBI scenario plan.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-08-07
//
// *****************************************************************************

`ifndef SMC_I3C_IBI_RANDOM_PLAN_SV
`define SMC_I3C_IBI_RANDOM_PLAN_SV

typedef enum bit [1:0] {
  IBI_RANDOM_ACK,
  IBI_RANDOM_NACK_FLUSH,
  IBI_RANDOM_RETRY_ACK
} smc_i3c_ibi_random_response_e;

typedef enum bit [2:0] {
  IBI_RANDOM_MDB_000,
  IBI_RANDOM_MDB_001,
  IBI_RANDOM_MDB_101,
  IBI_RANDOM_MDB_OTHER
} smc_i3c_ibi_random_mdb_class_e;

typedef enum bit [1:0] {
  IBI_RANDOM_DAT_ACCEPT,
  IBI_RANDOM_DAT_REJECT,
  IBI_RANDOM_PAYLOAD_DISABLED,
  IBI_RANDOM_DAT_NO_MATCH
} smc_i3c_ibi_random_policy_e;

class smc_i3c_ibi_random_item extends uvm_object;
  `uvm_object_utils(smc_i3c_ibi_random_item)

  rand bit                              mdb_present;
  rand bit [7:0]                        mdb;
  rand smc_i3c_ibi_random_mdb_class_e   mdb_class;
  rand int unsigned                     payload_len;
  rand smc_i3c_ibi_random_response_e    response_mode;
  rand int unsigned                     nack_count_before_ack;
  rand int unsigned                     inter_ibi_gap;
  rand smc_i3c_ibi_random_policy_e      controller_policy;

  bit          controller_profile;
  bit          stress_profile;
  int unsigned max_payload = 16;

  constraint c_mdb_class {
    mdb_class dist {
      IBI_RANDOM_MDB_000   :/ 25,
      IBI_RANDOM_MDB_001   :/ 25,
      IBI_RANDOM_MDB_101   :/ 25,
      IBI_RANDOM_MDB_OTHER :/ 25
    };
    if (mdb_class == IBI_RANDOM_MDB_000)
      mdb[7:5] == 3'b000;
    else if (mdb_class == IBI_RANDOM_MDB_001)
      mdb[7:5] == 3'b001;
    else if (mdb_class == IBI_RANDOM_MDB_101)
      mdb[7:5] == 3'b101;
    else
      mdb[7:5] inside {3'b010, 3'b011, 3'b100, 3'b110, 3'b111};
  }

  constraint c_payload {
    payload_len inside {[0:max_payload]};
    if (stress_profile)
      payload_len dist {
        0             :/ 25,
        1             :/ 25,
        [2:8]         :/ 15,
        [9:255]       :/ 35
      };
    else
      payload_len dist {
        0       :/ 15,
        1       :/ 15,
        [2:4]   :/ 25,
        [5:8]   :/ 25,
        [9:255] :/ 20
      };
  }

  constraint c_role {
    if (controller_profile) {
      response_mode == IBI_RANDOM_ACK;
      nack_count_before_ack == 0;
      controller_policy dist {
        IBI_RANDOM_DAT_ACCEPT       :/ 35,
        IBI_RANDOM_DAT_REJECT       :/ 25,
        IBI_RANDOM_PAYLOAD_DISABLED :/ 20,
        IBI_RANDOM_DAT_NO_MATCH     :/ 20
      };
      // The pinned Device VIP cannot launch an empty/no-MDB IBI. Keep the
      // Controller-RX random profile inside that transport contract. Any
      // MDB-absence coverage needs a transport path that explicitly supports it.
      mdb_present == 1;
    } else {
      mdb_present == 1;
      controller_policy == IBI_RANDOM_DAT_ACCEPT;
      if (stress_profile)
        response_mode == IBI_RANDOM_ACK;
      else
        response_mode dist {
          IBI_RANDOM_ACK        :/ 55,
          IBI_RANDOM_NACK_FLUSH :/ 20,
          IBI_RANDOM_RETRY_ACK  :/ 25
        };
      if (response_mode == IBI_RANDOM_NACK_FLUSH) {
        payload_len == 0;
        nack_count_before_ack == 0;
      } else if (response_mode == IBI_RANDOM_RETRY_ACK) {
        // The proven retry path currently retains an MDB-only descriptor.
        payload_len == 0;
        nack_count_before_ack inside {[1:5]};
      } else
        nack_count_before_ack == 0;
    }
  }

  constraint c_gap {
    if (controller_profile)
      inter_ibi_gap == 0;
    else if (stress_profile)
      inter_ibi_gap dist {0 :/ 70, [1:4] :/ 25, [5:20] :/ 5};
    else
      inter_ibi_gap dist {0 :/ 15, [1:20] :/ 45, [21:100] :/ 40};
  }

  function new(string name = "smc_i3c_ibi_random_item");
    super.new(name);
  endfunction

  function string response_name();
    case (response_mode)
      IBI_RANDOM_ACK:        return "ACK";
      IBI_RANDOM_NACK_FLUSH: return "NACK_FLUSH";
      IBI_RANDOM_RETRY_ACK:  return "RETRY_ACK";
      default:               return "UNKNOWN";
    endcase
  endfunction

  function string policy_name();
    case (controller_policy)
      IBI_RANDOM_DAT_ACCEPT:       return "DAT_ACCEPT";
      IBI_RANDOM_DAT_REJECT:       return "DAT_REJECT";
      IBI_RANDOM_PAYLOAD_DISABLED: return "PAYLOAD_DISABLED";
      IBI_RANDOM_DAT_NO_MATCH:     return "DAT_NO_MATCH";
      default:                     return "UNKNOWN";
    endcase
  endfunction

  function string describe(int unsigned index);
    string expected_response;

    if (controller_profile)
      expected_response =
        (controller_policy == IBI_RANDOM_DAT_ACCEPT) ? "ACK" : "NACK";
    else
      expected_response = response_name();
    return $sformatf(
      "item=%0d role=%s mdb_present=%0b mdb=0x%02h mdb_class=%s payload=%0d response=%s nacks_before_ack=%0d gap=%0d policy=%s",
      index, controller_profile ? "controller-rx" : "target-tx",
      mdb_present, mdb, mdb_class.name(), payload_len, expected_response,
      nack_count_before_ack, inter_ibi_gap, policy_name());
  endfunction

  function bit validate(output string reason);
    reason = "";
    if (!mdb_present) begin
      reason = "pinned Device VIP requires an MDB";
      return 1'b0;
    end
    if (payload_len > max_payload) begin
      reason = $sformatf("payload_len=%0d exceeds max_payload=%0d",
                         payload_len, max_payload);
      return 1'b0;
    end
    case (mdb_class)
      IBI_RANDOM_MDB_000:
        if (mdb[7:5] != 3'b000) begin
          reason = $sformatf("MDB class 000 disagrees with MDB=0x%02h", mdb);
          return 1'b0;
        end
      IBI_RANDOM_MDB_001:
        if (mdb[7:5] != 3'b001) begin
          reason = $sformatf("MDB class 001 disagrees with MDB=0x%02h", mdb);
          return 1'b0;
        end
      IBI_RANDOM_MDB_101:
        if (mdb[7:5] != 3'b101) begin
          reason = $sformatf("MDB class 101 disagrees with MDB=0x%02h", mdb);
          return 1'b0;
        end
      IBI_RANDOM_MDB_OTHER:
        if (!(mdb[7:5] inside {3'b010, 3'b011, 3'b100, 3'b110, 3'b111})) begin
          reason = $sformatf("MDB class OTHER disagrees with MDB=0x%02h", mdb);
          return 1'b0;
        end
      default: begin
        reason = "unknown MDB class";
        return 1'b0;
      end
    endcase
    case (response_mode)
      IBI_RANDOM_ACK:
        if (nack_count_before_ack != 0) begin
          reason = $sformatf("ACK response has retry count %0d",
                             nack_count_before_ack);
          return 1'b0;
        end
      IBI_RANDOM_NACK_FLUSH:
        if ((payload_len != 0) || (nack_count_before_ack != 0)) begin
          reason = $sformatf("NACK_FLUSH requires payload/retry 0, got %0d/%0d",
                             payload_len, nack_count_before_ack);
          return 1'b0;
        end
      IBI_RANDOM_RETRY_ACK:
        if ((payload_len != 0) ||
            !(nack_count_before_ack inside {[1:5]})) begin
          reason = $sformatf("RETRY_ACK requires payload 0 and retry 1..5, got %0d/%0d",
                             payload_len, nack_count_before_ack);
          return 1'b0;
        end
      default: begin
        reason = "unknown response mode";
        return 1'b0;
      end
    endcase
    if (controller_profile) begin
      if ((response_mode != IBI_RANDOM_ACK) ||
          (inter_ibi_gap != 0)) begin
        reason = $sformatf("Controller profile requires ACK/gap 0, got %s/%0d",
                           response_name(), inter_ibi_gap);
        return 1'b0;
      end
    end else begin
      if (controller_policy != IBI_RANDOM_DAT_ACCEPT) begin
        reason = "Target profile requires DAT_ACCEPT policy";
        return 1'b0;
      end
      if ((!stress_profile && (inter_ibi_gap > 100)) ||
          (stress_profile && (inter_ibi_gap > 20))) begin
        reason = $sformatf("inter_ibi_gap=%0d exceeds profile limit",
                           inter_ibi_gap);
        return 1'b0;
      end
    end
    return 1'b1;
  endfunction
endclass : smc_i3c_ibi_random_item

class smc_i3c_ibi_random_plan extends uvm_object;
  `uvm_object_utils(smc_i3c_ibi_random_plan)

  smc_i3c_ibi_random_item items[$];

  function new(string name = "smc_i3c_ibi_random_plan");
    super.new(name);
  endfunction

  function void build(int unsigned item_count,
                      int unsigned max_payload,
                      bit controller_profile,
                      bit stress_profile,
                      bit mixed_response_profile = 1'b0,
                      bit must_hit_profile = 1'b0);
    smc_i3c_ibi_random_item item;
    string validation_reason;

    if (item_count == 0)
      `uvm_fatal("IBI_RANDOM_COUNT", "Random plan requires at least one item")
    if (max_payload > 8'hff)
      `uvm_fatal("IBI_RANDOM_PAYLOAD",
                 $sformatf("Maximum payload %0d exceeds descriptor limit 255",
                           max_payload))
    if (must_hit_profile && (item_count < 12))
      `uvm_fatal("IBI_RANDOM_MUST_HIT_COUNT",
                 $sformatf("Must-hit profile requires at least 12 items, got %0d",
                           item_count))
    if (must_hit_profile && mixed_response_profile && (item_count < 14))
      `uvm_fatal("IBI_RANDOM_MIXED_COUNT",
                 $sformatf("Mixed-response must-hit profile requires at least 14 items, got %0d",
                           item_count))

    items.delete();
    for (int unsigned index = 0; index < item_count; index++) begin
      item = smc_i3c_ibi_random_item::type_id::create(
        $sformatf("item_%0d", index));
      item.controller_profile = controller_profile;
      item.stress_profile = stress_profile;
      item.max_payload = max_payload;
      if (!item.randomize())
        `uvm_fatal("IBI_RANDOMIZE",
                   $sformatf("Failed to randomize IBI plan item %0d", index))
      // Stress runs always include the three payload boundaries before using
      // random values for the remaining entries. This keeps the test
      // coverage-directed without creating a second directed sequence.
      if (stress_profile) begin
        case (index % 4)
          0: item.payload_len = 0;
          1: item.payload_len = (max_payload == 0) ? 0 : 1;
          2: item.payload_len = max_payload;
          default: ;
        endcase
      end
      // Guarantee that a four-item (or longer) plan exercises every MDB
      // class. In particular, keep grp_101 deterministic instead of relying
      // on its random distribution to close pending-read coverage.
      if (item_count >= 4) begin
        case (index % 4)
          0: begin
            item.mdb_class = IBI_RANDOM_MDB_000;
            item.mdb[7:5] = 3'b000;
          end
          1: begin
            item.mdb_class = IBI_RANDOM_MDB_001;
            item.mdb[7:5] = 3'b001;
          end
          2: begin
            item.mdb_class = IBI_RANDOM_MDB_101;
            item.mdb[7:5] = 3'b101;
            item.mdb_present = 1'b1;
            // Make the requirement-owned pending-read boundary deterministic:
            // group 101 with one payload byte and an accepted response closes
            // a useful content cross without relying on seed luck.
            if (max_payload != 0)
              item.payload_len = 1;
            item.response_mode = IBI_RANDOM_ACK;
            item.nack_count_before_ack = 0;
            if (controller_profile)
              item.controller_policy = IBI_RANDOM_DAT_ACCEPT;
          end
          default: begin
            item.mdb_class = IBI_RANDOM_MDB_OTHER;
            item.mdb[7:5] = 3'b111;
          end
        endcase
      end
      // A must-hit prefix makes the coverage buckets independent of seed
      // luck. Remaining entries retain their constrained-random values.
      if (!controller_profile && must_hit_profile && (item_count >= 12)) begin
        case (index)
          4: begin
            item.response_mode = IBI_RANDOM_ACK;
            item.payload_len = 0;
            item.nack_count_before_ack = 0;
            item.inter_ibi_gap = 0;
          end
          5: begin
            item.response_mode = IBI_RANDOM_ACK;
            item.payload_len = (max_payload == 0) ? 0 : 1;
            item.nack_count_before_ack = 0;
            item.inter_ibi_gap = 1;
          end
          6: begin
            item.response_mode = IBI_RANDOM_ACK;
            item.payload_len = (max_payload < 4) ? max_payload : 4;
            item.nack_count_before_ack = 0;
            item.inter_ibi_gap = 4;
          end
          7: begin
            item.response_mode = IBI_RANDOM_ACK;
            item.payload_len = max_payload;
            item.nack_count_before_ack = 0;
            item.inter_ibi_gap = 20;
          end
          8: begin
            item.response_mode = IBI_RANDOM_NACK_FLUSH;
            item.payload_len = 0;
            item.nack_count_before_ack = 0;
          end
          9, 10, 11: begin
            item.response_mode = IBI_RANDOM_RETRY_ACK;
            item.payload_len = 0;
            item.nack_count_before_ack =
              (index == 9) ? 1 : ((index == 10) ? 3 : 5);
          end
          default: ;
        endcase
      end
      // Mixed stress keeps sustained ACK traffic dominant while injecting a
      // deterministic NACK/flush and retry in every four-item window.
      if (!controller_profile && stress_profile && mixed_response_profile) begin
        case (index % 4)
          0, 1: begin
            item.response_mode = IBI_RANDOM_ACK;
            item.nack_count_before_ack = 0;
          end
          2: begin
            item.response_mode = IBI_RANDOM_NACK_FLUSH;
            item.payload_len = 0;
            item.nack_count_before_ack = 0;
          end
          3: begin
            item.response_mode = IBI_RANDOM_RETRY_ACK;
            item.payload_len = 0;
            item.nack_count_before_ack = 1 + ((index / 4) % 5);
          end
        endcase
        // Preserve deterministic medium/long ACK payload boundaries after
        // the response schedule above has converted modulo-2/3 entries into
        // NACK/retry cases.
        if (index == 12) begin
          item.response_mode = IBI_RANDOM_ACK;
          item.payload_len = (max_payload < 4) ? max_payload : 4;
          item.nack_count_before_ack = 0;
          item.inter_ibi_gap = 0;
        end else if (index == 13) begin
          item.response_mode = IBI_RANDOM_ACK;
          item.payload_len = max_payload;
          item.nack_count_before_ack = 0;
          item.inter_ibi_gap = 20;
        end
      end
      if (!item.validate(validation_reason))
        `uvm_fatal("IBI_RANDOM_PLAN_INVALID",
                   $sformatf("Random plan item %0d is invalid after profile overrides: %s; %s",
                             index, validation_reason, item.describe(index)))
      items.push_back(item);
    end
  endfunction

  function void print_plan(string report_id = "IBI_RANDOM_PLAN");
    `uvm_info(report_id,
              $sformatf("Random plan contains %0d item(s); replay with the same simulator seed",
                        items.size()),
              UVM_LOW)
    foreach (items[index])
      `uvm_info(report_id, items[index].describe(index), UVM_LOW)
  endfunction
endclass : smc_i3c_ibi_random_plan

`endif // SMC_I3C_IBI_RANDOM_PLAN_SV
