// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 VNCHIP LABS
// Authors: Huynh Pham Anh Duy, Thai Hai Dang
// Standalone packaging derived from timing definitions in the CHIPS Alliance
// I3C UVM VIP as carried by the Tenstorrent tt-i3c-core fork.

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
