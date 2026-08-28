# Source Baseline

- Delivery branch baseline: record the package commit in
  `docs/release/RELEASE_MANIFEST.md` for each candidate or release.
- TT I3C expected branch: `tt/main`.
- TT I3C expected commit:
  `a6361105cd3432699da636f1f5e6f1eb4df09ed2`.
- Caliptra expected commit:
  `a4582f5856136286d2389b1cfa8de2910a82fe5e`.
- UVM compatibility baseline: UVM 2020.3.1.
- Bundled UVM location: `third_party/uvm-core-2020.3.1`.

The authoritative machine-readable pins remain in:

```text
i3c/sim/project/i3c_source_pins.mk
```

Use `SOURCE_MODE=pinned` for qualification runs against the recorded baseline,
`SOURCE_MODE=latest` to compare with `origin/tt/main`, and
`SOURCE_MODE=worktree` for an explicitly reviewed development checkout.
In `pinned` mode, a branch/commit mismatch, dirty source checkout, missing Git
metadata, or missing required RTL/RAL file is a blocking error. `latest` and
`worktree` are development modes: they may intentionally select another
revision, but the resulting run is not evidence for the pinned release
baseline unless that revision is reviewed and the manifest is updated.
