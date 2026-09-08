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
// File        : i3c_vip_types_pkg.sv
// Description : Standalone I3C VIP timing types derived from the Tenstorrent tt-i3c-core fork.
// Authors     : Huynh Pham Anh Duy, Thai Hai Dang
// Date        : 2026-09-08
//
// *****************************************************************************

package i3c_vip_types_pkg;

  typedef struct {
    int tHoldStop   = 1_300; // 1.3 us
    int tHoldStart  = 600;
    int tSetupStart = 600;
    int tSetupBit   = 100;
    int tHoldBit    = 0;
    int tClockPulse = 900;
    int tClockLow   = 1_600;
    int tSetupStop  = 1_300;
  } i2c_timing_t;

  typedef struct {
    int tHoldStop   = 1_300; // 1.3 us
    int tHoldStart  = 39;
    int tSetupStart = 20;
    int tHoldRStart = 20;
    // Simulation launch delay from the first SCL falling edge after START to
    // the first Address Header bit. Keep START completion and A6 in distinct
    // time slots so resolved-bus monitors cannot interpret the handoff as an
    // ambiguous simultaneous SDA/SCL transition.
    int tAddrLaunchDelay = 3;
    int tSetupBit   = 3;
    int tHoldBit    = 0;
    int tClockPulse = 32;
    int tClockLowOD = 200;
    int tClockLowPP = 48;
    int tSetupStop  = 20;
  } i3c_timing_t;

endpackage : i3c_vip_types_pkg
