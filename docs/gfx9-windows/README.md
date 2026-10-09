# gfx9 on Windows (ROCr path)

This branch carries the gfx9-on-Windows enablement work for TheRock.

## What is here
- `patches/amd-mainline/rocm-systems/` : CLR (ISA/xnack, mempool, PAL->ROCr fallback, exit-hang),
  dxg cache-coherency (ACQUIRE_MEM), HIP headers (LLP64, device-assert), hip-tests warp-reduce.
- `patches/amd-mainline/rocm-libraries/` : MIOpen (fused-conv, legacy-CK, MultiMarginLoss,
  tests-arch), rocPRIM quick-tier partition.
- `patches/amd-mainline/llvm-project/` : device-libs dot builtins, AMDGPU trap-endpgm fallback.
- `build_tools/` : two TheRock CI fixes applied live (prefer artifact DLLs over System32;
  skip hipBLASLt on unsupported Windows families).
- `docs/gfx9-windows/` : executive summary, catalog, change-impact, coverage, cross-arch comparison.

## NOT here (carry limitations)
- wkmi family-table + legacy-KMD clock fixes (fixes 1, 4): wkmi is an internal Windows driver lib,
  not a TheRock submodule, so it cannot be carried in this repo.
- dxg user-queue + HandleError fixes (fixes 2, 3): required for gfx9 kernel submit, but not
  available as standalone patch files in this working set.

Consequence: a build from this branch alone will NOT enumerate or dispatch on gfx9 Windows without
the wkmi + dxg fixes 2-3 applied separately. The Windows runtime fixes are `#if WINDOWS`-gated, so a
Linux build exercises only the cross-platform correctness fixes (device-libs, LLP64, MIOpen, LLVM
trap) plus the CI changes. Full validation was done on real Windows hardware (gfx90c); see
`docs/gfx9-windows/EXECUTIVE-SUMMARY.md`.
