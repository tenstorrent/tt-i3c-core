# Source Baseline

- Delivery branch baseline: record the package commit in
  `docs/release/RELEASE_MANIFEST.md` for each candidate or release.
- Native TT I3C source root: resolved from the containing repository's `src/i3c.f`; `I3C_ROOT_DIR` is an optional override for a non-ancestor integration layout.
- Native compile authority: `${I3C_ROOT_DIR}/src/i3c.f`.
- Generated CSR authority: `${I3C_ROOT_DIR}/src/csr/I3CCSR_uvm.sv`.
- UVM compatibility baseline: UVM 2020.3.1.
- Bundled UVM location: `third_party/uvm-core-2020.3.1`.

Qualification records the native source revision and Caliptra revision in the
run manifest. A missing `src/i3c.f`, generated CSR package, or
required recursive dependency is a blocking preflight error.
