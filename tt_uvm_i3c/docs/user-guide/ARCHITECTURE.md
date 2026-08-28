# Architecture

## Main Structure

The standalone `tt_uvm_i3c` package is organized into four main areas:
documentation, the I3C project payload, simulation infrastructure, and the
bundled UVM library.

```text
tt_uvm_i3c/
├── README.md
├── run.sh
├── docs/
│   ├── README.md
│   ├── user-guide/
│   ├── verification/
│   ├── components/
│   └── release/
├── i3c/
│   ├── rtl/
│   │   ├── external/
│   │   │   ├── i3c_core.f
│   │   │   └── i3c_manifest.mk
│   │   ├── wrappers/
│   │   │   ├── smc_i3c_axi_adapter.sv
│   │   │   └── smc_i3c_wrapper.sv
│   │   ├── smc_peripherals_stub.sv
│   │   └── smc_peripherals_top.sv
│   ├── sim/
│   │   ├── Makefile
│   │   ├── filelists/
│   │   ├── mk/
│   │   ├── project/
│   │   └── scripts/
│   └── verify/
│       ├── vip/
│       │   ├── axi4lite_vip/
│       │   └── i3c_vip/
│       └── tb/
│           ├── interfaces/
│           ├── portable/i3c/
│           ├── coverage/
│           ├── env/
│           ├── ral/
│           ├── sva/
│           ├── tests/
│           ├── top/
│           └── vseq/
└── third_party/
    └── uvm-core-2020.3.1/
```

The directories have the following responsibilities:

- `docs/` is the single detailed-documentation tree, grouped by audience.
- `i3c/rtl/` contains the local integration RTL. The TT I3C core itself is
  external and is selected through `I3C_ROOT_DIR`.
- `i3c/sim/` contains compile filelists, generated Make fragments, source pins,
  and the VCS test, regression, waveform, and coverage runner.
- `i3c/verify/vip/` contains the AXI4-Lite VIP, the self-contained I3C protocol
  VIP, and the top-level peripheral interface.
- `i3c/verify/tb/` contains the UVM environment, register model integration,
  virtual sequences, tests, scoreboards, assertions, and functional coverage.
- `third_party/uvm-core-2020.3.1/` contains the bundled Accellera UVM library
  used by default.

`run.sh` at the package root is the public entry point for the optional
reference automation. It is not a runtime dependency of the SystemVerilog/UVM
environment. An external runner may consume the documented filelists, top,
test classes, plusargs, and verdict contract instead; see
`docs/user-guide/EXTERNAL_RUNNER.md`. The internal `smc_*` names are retained
from the qualified OCAH integration baseline and do not introduce a dependency
on another OCAH directory.

## Data Architecture

The testbench uses two active stimulus paths:

1. The AXI4-Lite path configures and observes the DUT registers.
2. The I3C path generates or responds to protocol traffic on the shared
   open-drain SDA/SCL bus.

```text
UVM test
   |
   v
Virtual sequence
   |
   +---------------- AXI4-Lite path ----------------+
   |                                                |
   v                                                v
AXI4-Lite sequencer -> driver -> AXI4-Lite interface
                                      |
                                      v
                            smc_i3c_axi_adapter
                                      |
                               AXI4 single-beat
                                      |
                                      v
                                 TT I3C core
                                      |
   +------------------- I3C path -------------------+
   |                                  |
   v                                  v
I3C sequencer -> I3C VIP driver -> SDA/SCL bus
                                      |
                                      v
                                 TT I3C core
```

The AXI4-Lite monitor publishes every observed register transaction to the
following consumers:

- the CSR/address-window scoreboard;
- the UVM register predictor;
- IBI predictors and observers that correlate CSR, queue, HCI, and interrupt
  effects;
- AXI integration and IBI functional coverage.

The I3C monitor publishes decoded bus transactions to the IBI observers and
scoreboards. Expected and actual IBI traffic are kept as separate analysis
streams:

```text
CSR and test intent -> predictor -> expected transaction --+
                                                           |
                                                           v
                                                     IBI scoreboard
                                                           ^
                                                           |
I3C bus and DUT state -> observer -> actual transaction ---+
```

Two IBI checking pipelines are selected according to the DUT role:

- **DUT Target:** the DUT initiates IBI, while the I3C VIP acts as Controller
  and returns ACK or NACK. The Target pipeline checks bus content, CSR state,
  queue effects, terminal status, retries, and interrupts.
- **DUT Controller:** the I3C VIP acts as Target and initiates IBI. The
  Controller pipeline checks address and DAT policy, response content, HCI
  descriptors, FIFO effects, interrupts, multi-target arbitration, and timing
  context.

The virtual-sequence context provides sequences with the resolved environment
configuration, AXI4-Lite sequencer, primary and secondary I3C sequencers, RAL
model, CSR helper, Controller HCI helper, and reset services. This avoids
direct hierarchical access from tests and sequences to UVM components.

At the hardware boundary, SDA and SCL are modeled as shared open-drain buses
with pull-ups. A participant drives a line only when it actively requests a
low value; otherwise it releases the line. The top-level bus model also
prevents inactive or unknown DUT output values from contaminating the bus.

## DUT Wrapper

The real-RTL hierarchy is:

```text
tb_smc_peripherals_top
└── u_dut : smc_peripherals_top
    └── u_i3c0 : smc_i3c_wrapper
        ├── u_axi_adapter : smc_i3c_axi_adapter
        └── u_i3c_core    : i3c_wrapper
```

`smc_peripherals_top` exposes a standalone AXI4-Lite register interface, I3C
pad signals, reset controls, recovery status, and the I3C interrupt. It
instantiates `smc_i3c_wrapper` at the default host address
`0x0040_0000` with a 4 KiB register window.

`smc_i3c_wrapper` performs the integration around the external TT I3C core:

- combines the top-level reset and enable controls into the core reset;
- qualifies register access with `enable_i` and `access_allow_i`;
- converts the host AXI4-Lite interface through `smc_i3c_axi_adapter`;
- instantiates the external TT `i3c_wrapper`;
- forwards SDA/SCL, open-drain output enables, recovery signals, reset
  requests, and the interrupt.

`smc_i3c_axi_adapter` converts a 32-bit or 64-bit host AXI4-Lite interface into
the TT core's 32-bit AXI interface. It emits single-beat transfers, translates
the absolute host address into a local 12-bit core address, and selects the
correct 32-bit data lane for a 64-bit host.

The adapter enforces the integration boundary:

- an access outside the configured register window returns `DECERR`;
- an access rejected by the access policy returns `DECERR`;
- a write strobe that selects bytes outside the addressed 32-bit lane returns
  `SLVERR`;
- accepted core responses are forwarded to the host interface.

When compiled with `DUT_MODE=stub`, the real hierarchy is replaced by
`smc_peripherals_stub`. The stub supports infrastructure development but does
not provide the TT I3C protocol or generated RAL functionality. Real
verification tests require `DUT_MODE=rtl`, the external core filelist at
`$I3C_ROOT_DIR/src/i3c.f`, and the generated register model at
`$I3C_ROOT_DIR/src/csr/I3CCSR_uvm.sv`.

## Verification Ownership and Build Contract

The verification payload is divided by responsibility:

- `i3c/verify/vip/` owns protocol agents, drivers, monitors, interfaces,
  transactions, and sequences.
- `i3c/verify/tb/interfaces/` owns testbench signal bundles.
- `i3c/verify/tb/env/` owns DUT-specific configuration, adapters, predictors,
  scoreboards, services, and driver/monitor specializations.
- `i3c/verify/tb/portable/` owns parent-independent APIs and virtual-sequence
  infrastructure.
- `i3c/verify/tb/sequences/`, `vseq/`, and `tests/` own protocol stimulus,
  multi-interface coordination, and scenario selection.
- `i3c/verify/tb/coverage/` and `sva/` own functional coverage and assertions.

The generated source order places parameters and reporting first, followed by
interfaces and SVA, RAL and VIP packages, coverage, environment, virtual
sequences, tests, and the testbench top. The generator
`i3c/sim/scripts/gen_mk_files.sh` owns the generated Make fragments under
`i3c/sim/mk/`; new package sources must be added in dependency order.

`SMC_USE_I3C_RTL` enables RTL-facing I3C VIP and bus operations, while
`SMC_USE_I3C_RAL` enables the generated I3C register model. Four I3C interface
slots are available. Slot 0 is the primary peer; slots 1 through 3 are optional
auxiliary agents, and the legacy `secondary` handle aliases slot 1.

## Portable I3C Layer

The portable layer under `i3c/verify/tb/portable/i3c/` provides abstract CSR
access, integration services, context and analysis types, and reusable virtual
sequence bases without depending on the standalone DUT wrapper. Parent
environments implement `smc_i3c_csr_api` and translate offset-based accesses to
their local AXI-Lite, AXI, or RAL transport. Its source export is
`i3c/sim/mk/i3c_portable_srcs.mk`.

## IBI Robustness Boundary

The pinned core uses `STBY_CR_DEVICE_ADDR.DYNAMIC_ADDR` for IBI when
`DYNAMIC_ADDR_VALID` is set. `TTI.CONTROL.IBI_EN`, rather than BCR capability,
is the runtime IBI gate. Current eligibility tests cover an invalid dynamic
address and a queued request while `IBI_EN=0`; they do not claim protection
against software forcing a reserved dynamic address or creating a contradictory
pre-mode configuration. See `docs/verification/KNOWN_ISSUES.md` for the
authoritative limitations and dispositions.
