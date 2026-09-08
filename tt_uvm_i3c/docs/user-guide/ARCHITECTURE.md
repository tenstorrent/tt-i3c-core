# Architecture

`tt_uvm_i3c` is a native-I3C UVM environment. The project-owned tree contains
the verification infrastructure and a thin AXI4-Lite/DV boundary; the native
RTL and generated CSR package are resolved from the containing repository,
with `I3C_ROOT_DIR` available as an optional integration override.

```text
tt_uvm_i3c/
├── i3c/
│   ├── sim/                 # runner, generated inputs, and test plan
│   └── verify/
│       ├── vip/             # AXI4-Lite and protocol VIP
│       └── tb/              # environment, RAL, sequences, tests, SVA, coverage
├── third_party/             # bundled Accellera UVM
└── run.sh                   # optional reference runner
```

## Data path

The UVM environment drives two independent paths:

```text
AXI4-Lite VIP ──> i3c_dv_axi_adapter ──> i3c_dv_wrapper ──> native i3c_wrapper
I3C VIP       ──────────────────────────────── shared SDA/SCL bus ──┘
```

The adapter converts AXI4-Lite requests into single-beat native AXI transfers.
It preserves native CSR offsets, forwards core responses, selects the correct
32-bit lane for a 64-bit host, and reports illegal cross-lane strobes as
`SLVERR`. It does not implement an absolute base address, register window,
access policy, enable gate, or local `DECERR` behavior.

`i3c_dv_wrapper` is deliberately thin. It instantiates the native
`i3c_wrapper`, connects the adapter, and forwards reset, pad, recovery, and IRQ
signals. The top-level `tb_i3c_top` always instantiates this native boundary;
there is no fake or stub DUT mode.

SDA and SCL are shared open-drain nets with pull-ups. The top-level harness
derives controller pad enable from the selected role and keeps unknown inactive
core values from contaminating the bus. Recovery and reset status remain
observable through `i3c_tb_if`.

## Verification ownership

- `verify/vip/` owns protocol and AXI4-Lite agents and their public interfaces.
- `verify/tb/env/` owns configuration, DV-specific driver/monitor subclasses,
  predictors, scoreboards, and services.
- `verify/tb/ral/` owns the little-endian frontdoor adapter and wrapper around
  the generated native CSR model.
- `verify/tb/vseq/` and `verify/tb/tests/` own scenario stimulus and canonical
  test identities.
- `verify/tb/sva/` and `verify/tb/coverage/` own protocol assertions and IBI
  functional coverage.

The native source repository's `src/i3c.f` is the only DUT compile authority.
`sim/project/generate_dv_inputs.sh` emits the project sources, native filelist,
adapter, wrapper, and ordered UVM packages into the generated compile list.
`sim/filelists/test.f` is the authoritative test grouping and is normalized
without duplicating canonical test identities.

The native RTL and RAL definitions are required for every functional run. The
compile defines `I3C_DV_NATIVE_RTL` and `I3C_DV_NATIVE_RAL` are emitted by the
project configuration as capability markers, not user-selectable DUT modes.

## Register model contract

The RAL wrapper creates a 4-byte little-endian root map and attaches generated
submaps at their native offsets. CSR helper and scoreboard requests use those
offsets directly. No project-specific absolute address or access-denial policy is
modeled in the DV tree.

## IBI pipelines

For Target-TX, the native DUT initiates an IBI while the protocol VIP acts as
Controller. For Controller-RX, the protocol VIP Target agents initiate IBIs
and the native DUT consumes them. Expected and observed streams are joined by
the role-specific predictors and scoreboards; passive role/protocol SVA and
IBI functional coverage consume the same normalized transaction evidence.
