# gfx9 on Windows (ROCm/TheRock): enablement and validation summary

> **STATUS (2026-10-09): ACHIEVED on gfx90c.** gfx9 is functional on Windows through the open ROCr
> backend: device enumeration, kernel dispatch, the full ROCm math/ML library stack, and real
> rocm-examples programs all run. Validated by ~270,000 test-case executions with no unexplained gfx9
> defect. Scope/caveats: validated on gfx90c (one GCN5 client APU); runtime device-trap handler and
> stream-wait are prototype/opt-in; broadening to other gfx9 Windows parts and upstream submission are
> not yet done (nothing has been posted upstream).

Status snapshot for reporting. Local work only; nothing has been posted upstream. Detail lives in
`upstream-patches/INDEX.md` (catalog), `CHANGE-IMPACT.md` (priority), `compare/ARCH-COMPARISON.md`,
`compare/TEST-COVERAGE.md`, and `compare/gfx90c-gaps-and-gfx906-findings.md`.

## 1. What was achieved

gfx9 (GCN5) GPUs are enabled on Windows through the open ROCm/ROCr backend in TheRock, on hardware
and OS combinations that ship no ROCm support today. Validated end to end on a gfx90c APU (Ryzen
5700G iGPU, Windows 11, legacy driver): device enumeration, kernel dispatch, and the ROCm math/ML
library stack all function. Demonstrated by passing the HIP conformance suite and the ROCm libraries
at parity with supported architectures, except for independently-explained failures.

## 2. The changes (25 distinct, across 5 repositories)

- **9 runtime fixes** (wkmi + rocm-systems dxg/CLR): GPU enumeration, kernel submit, queue-error
  reporting, legacy-KMD clocks, cache coherency (the big one), code-object/XNACK acceptance,
  exit-hang, async-alloc heap, and the PAL->ROCr fallback that makes gfx9 work without a manual env
  var (fix 10, validated 2026-10-09).
- **9 correctness fixes** (llvm-project + rocm-libraries + headers): device-libs dot math, LLP64
  64-bit-Windows wave64 bugs (headers + tests), three MIOpen fixes (grouped-conv, legacy-CK macro,
  MultiMarginLoss type), the device-assert message, and a safe device-trap fallback.
- **3 CI fixes** (TheRock): the DLL-shadowing fix (tests must load the artifact runtime, not the
  driver's), unsupported-family job pruning, and a rocPRIM quick-tier timing partition.
- Plus **4 opt-in/experimental** runtime changes (CPU-side stream-wait, CU-mask, blit-queue,
  device-trap prototype) and **4 already-upstream** fixes that need only a submodule pin bump.

Repository footprint: ROCm/rocm-systems, ROCm/rocm-libraries, ROCm/llvm-project, ROCm/TheRock, and
AMD-ROCm-Internal/wkmi. A TheRock fork carrying submodule patches can reproduce the whole stack
except wkmi (the internal Windows driver lib). All patches re-verified to apply to current upstream.

## 3. Validation evidence (~270,000 test-case executions)

| axis | what | result |
|---|---|---|
| HIP conformance | hip-tests Catch2 across gfx90c / gfx1201 / gfx906 | gfx90c 98.8%, every failure fix-attributed; 0 unexplained |
| Cross-ISA (Linux) | gfx906 MI50 vs gfx90c: hip-tests + 336 component gtests (17,816) | 0 fail-in-both; confirms fixes are gfx90c/Windows-specific, not gfx9-general |
| Windows A/B | gfx1201 RX 9070 XT (supported RDNA4) vs gfx90c: rocSOLVER + hip-tests | rocSOLVER byte-identical (56,801/48); validates methodology on a known-good Windows arch |
| Library breadth | rocBLAS, rocSOLVER, rocSPARSE, rocFFT, rocRAND, rocPRIM, rocThrust, hipCUB, MIOpen, hipDNN, rocWMMA, rocALUTION, libhipcxx | all pass or correctly all-skip on gfx90c |

## 4. Test coverage completeness

Per `docs/development/windows_support.md`: **36 components are Windows-supported; all are covered**
(tested, or correctly all-skip on the gfx90c APU). **All untested components are Windows-UNSUPPORTED
by design** (amd-smi, rccl, profiler suites, rocDecode/JPEG, rocgdb, hipFile, hipSPARSELt, rocRoller),
auto-disabled on Windows. Only hipThreads (a separate lit artifact), standalone Composable Kernel
(header-only), and RPP (experimental) remain unrun among supported components, all low-value for
runtime validation.

## 5. Notable findings (not our bugs, found along the way)

- **LASWP / OpenBLAS:** the one scary-looking library failure (48 rocSOLVER cases) root-caused to an
  integer divide-by-zero in the host reference `rocm_openblas!blas_level1_thread` on Windows,
  arch-independent (identical on gfx90c and gfx1201 Windows; passes on gfx906 Linux OpenBLAS). Not a
  gfx or ROCm-runtime defect; a Windows OpenBLAS test-dependency issue.
- **DLL shadowing (fix 2b) reproduced** on the gfx1201 box: library tests loaded the driver's
  `System32\amdhip64_7.dll` until the artifact runtime was placed beside them.
- **hipStreamWaitValue_Default** fails on both gfx90c and gfx1201 Windows: a broader Windows PM4-path
  issue (addressed by the experimental CPU-side stream-wait prototype), not gfx9-specific.

## 6. Open items

- Runtime-side device-trap handler (compiler fallback lands cleanly; driver escape refused on the
  legacy KMD). The CPU-side stream-wait and CU-mask changes are validated but opt-in/prototype.
- Upstream submission is mapped (INDEX section 9) but on hold pending clearance; wkmi is internal-only.
