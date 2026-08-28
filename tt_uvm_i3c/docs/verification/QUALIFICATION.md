# Qualification Procedure

This procedure defines the minimum evidence needed to promote the candidate to
a qualified release. Run from the package root on the intended server/tool
environment.

## 1. Resolve pinned sources

```bash
source ./run.sh env tt
export I3C_ROOT_DIR=/absolute/path/to/tt-i3c-core
export CALIPTRA_ROOT=/absolute/path/to/caliptra-rtl
./run.sh doctor --source-mode pinned
```

Record the resolved source revisions, clean-state checks, simulator version,
and UVM selection.

## 2. Regenerate and inspect the plan

```bash
./run.sh generate
./run.sh list-tests --all
```

Compare the generated entries, enable state, per-entry plusargs, and seed
policy against the authoritative inventory in the release manifest. The
disabled SOFT_RST reproduction must not enter the normal regression silently.

## 3. Compile and run enabled tests

```bash
./run.sh compile --source-mode pinned
./run.sh regression --all --source-mode pinned
```

All enabled cases and required seeds must produce an explicit PASS verdict.
Scheduler/infrastructure retries are acceptable only when the final artifact
preserves their history and no verification failure is reclassified as PASS.

## 4. Collect IBI coverage

```bash
./run.sh coverage --all --source-mode pinned
```

Review assertion and functional-group coverage, unresolved objects, zero-hit
bins/properties, exclusions, and merge provenance. Code coverage is outside the
current IBI-focused qualification target and must not be included in the
denominator accidentally.

## 5. Review the verification plan

Walk `docs/verification/VERIFICATION_PLAN.md` requirement by requirement
against the merged coverage result. Confirm every mapped test, SVA, and
functional-coverage object resolves against this candidate, update each
requirement's `Status` from `Pending` to `Measured` only where recorded
evidence supports it, and confirm that `Not Applicable` and `Out of Scope`
entries do not contribute false closure.

## 6. Record and approve

Update `docs/release/RELEASE_MANIFEST.md` with immutable artifact references, results,
tool/source versions, review owner/date, and the final delivery commit. Resolve
or explicitly disposition every item in `docs/verification/KNOWN_ISSUES.md`. Only then may
the manifest status move from candidate to qualified.
