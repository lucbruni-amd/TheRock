# gfx9-on-Windows: change impact table

Maintained alongside `upstream-patches/INDEX.md` (the catalog). This file ranks each change by
priority and states what breaks without it. Keep both in sync when a change is added or dropped.

Priority rubric:
- **P0 Blocker**: without it gfx9-on-Windows does not function; the GPU is not usable at all.
- **P1 High**: major functionality broken, wrong results, or a safety hazard (hang / reset / crash).
- **P2 Medium**: a specific feature, library, or test family is broken; or an opt-in improvement.
- **P3 Low**: test-only, CI job selection, or cosmetic; no effect on shipped functionality.

Last reviewed 2026-10-08. "Observed" = what actually happened on gfx90c without the change.

## Required runtime fixes

| # | change (repo) | prio | effect if absent (observed) |
|---|---|---|---|
| 1 | wkmi `DetectGfxIpVersion` FAMILY_AI/RV table (wkmi) | **P0** | No gfx9 GPU is enumerated at all: "No WDDM adapters found", hipInfo "no ROCm-capable device". Nothing else can run. |
| 2 | dxg `AllocUserQueueMemFromUMD` major==9 (rocm-systems) | **P0** | Every kernel submit fails `c01e0200`; no dispatch ever completes. |
| 3 | dxg `HandleError` returns HSA_STATUS_ERROR_EXCEPTION not -1 (rocm-systems) | P1 | ROCr misreads the all-bits error as "insufficient scratch" and access-violates; a real queue error crashes the process instead of being reported. |
| 4 | wkmi clock attributes /100 for kmd < 2510 (wkmi) | P1 | Clock/bandwidth attributes ~100x too large on the legacy KMD; any code that sizes work from clocks misbehaves. Narrow to kmd < 2510. |
| 6 | dxg ACQUIRE_MEM invalidate vector L1 + L2 (rocm-systems) | **P0** | Stale cross-kernel reads -> wrong results, runaway kernels, engine-reset storms, one 0x10E bugcheck. Root cause behind most library failures (rocprim/rocthrust/rocsolver/hipfft/hipdnn). |
| 7 | CLR ISA table: gfx902/909/90c xnack-unsupported (rocm-systems) | **P0** for MIOpen | Every `:xnack-` code object (all MIOpen asm kernels) rejected "no kernel image is available": MIOpen/hipDNN largely dead (788 failures). OS-independent. |
| 8 | CLR skip stream-drain in `__hipUnregisterFatBinary` at process exit (rocm-systems) | P1 | Any process using the HIP DLL hangs forever at exit if GPU work was in flight. Affects gfx9 and RDNA2 on the Windows PM4 path. |
| 9 | CLR Windows-APU mempool VM heap off + #7988 FreeBlock (rocm-systems) | **P0** for async alloc | `hipMallocAsync`/pool paths fail early then corrupt the heap (SEH flood, garbage sizes, hangs): hipsparse/rocsparse unusable (OOM + timeouts). The #7988 double-free part is OS-general. |
| 10 | CLR Windows PAL->ROCr fallback when PAL finds no device (rocm-systems) | P1 | Without it, gfx9 on Windows gets NO device by default (`device.cpp` forces `GPU_ENABLE_PAL=1`, PAL has no gfx9): every tool/test crashes at startup (0xC0000409) unless the user sets `GPU_ENABLE_PAL=0`. With it, gfx9 works out of the box; RDNA-on-PAL untouched (numDevices>0 guard). Part 1 VALIDATED on the gfx90c box (unset env: unpatched=no device, patched=gfx90c enumerates + GETRI 84/84). |

## Correctness fixes (compiler / headers / libraries)

| change (repo) | prio | effect if absent (observed) |
|---|---|---|
| device-libs `dots.cl` gfx90c + fdot2 regression (llvm-project) | P1 | dot builtins emit opcodes the part lacks or are deleted -> wrong math (`hipTestNativeHalf`, `Rtc_MathFunctions/fp16`); fdot2 regression hits gfx900/902/904/909/1010 too. OS-independent. |
| HIP headers LLP64: `1ull<<lane`, `__builtin_ctzll` (rocm-systems) | P1 | wave64-on-Windows (= gfx9): `__reduce_*`/scan generic path wrong for lanes >=32; `__lastbit_u32_u64` truncates. Wrong results in any kernel using them. |
| MIOpen fused-conv grouped path (rocm-libraries) | P1 | `ConvHipDirectFwdFused` computes grouped convolutions as ungrouped: wrong results and reads past the weight buffer. Upstream bug, all GPUs this solver runs on (Linux and Windows). |
| LLVM `s_endpgm` after `s_trap 2` (llvm-project) | P1 (safety) | Where no trap handler can be installed (gfx90c legacy KMD), a device `assert`/`__builtin_trap` runs off the end: garbage, engine reset, poisoned GPU needing a reboot. With it, the wave ends cleanly. |
| MIOpen legacy-CK gfx9-APU macro (rocm-libraries) | P2 | `#error No CK_AMD_GPU_GFX*` for gfx902/909/90c: Reduce and RNN kernels fail to compile. All OSes. |
| MIOpen MultiMarginLoss host `long`->`int64_t` (rocm-libraries) | P2 | Host/kernel type mismatch: every MultiMarginLoss case fails on every Windows GPU (PAL and ROCr). |
| HIP header `_wassert` device-assert message (rocm-systems) | P2 | A failing device `assert()` on Windows prints nothing (silent trap): no diagnostic for the developer. |
| hip-tests warp-reduce LLP64 (rocm-systems) | P3 | Test-only mirror of the header LLP64 bug; the tests themselves are wrong on Windows (WarpTest 13 failures). |
| MIOpen gtest uncharacterized-arch (rocm-libraries) | P3 | Test harness throws `unknown_gpu` from every solver test SetUp on gfx90c (382 test failures); test-side only. |

## CI / test-configuration

| change (repo) | prio | effect if absent (observed) |
|---|---|---|
| TheRock prefer artifact DLLs over System32 (TheRock) | P1 | On Windows, test exes outside `bin\` load the driver's `amdhip64_7.dll`: on gfx9 every libhipcxx test and the rocprim/hipcub/rocthrust resource-spec fail; on other archs they silently test the driver, not the artifact. |
| TheRock skip hipBLASLt on unsupported Windows families (TheRock) | P3 | hipblaslt/hipblasltprovider jobs scheduled on Windows families with no hipBLASLt kernels can only fail; CI noise, no functional effect. |
| pick up newer submodule pin for #8974/#9385/#9633/#9652 (rocm-systems) | P1 | Five shared PM4-path hip-tests fail (EventIpc, NoCU_MulStrm, BatchAsync x3); already fixed upstream after the nightly, so only a pin bump is needed, no patch. |

## Experimental / opt-in (default-off or prototype)

| change (repo) | prio | effect if absent |
|---|---|---|
| CPU-side stream wait, `GPU_STREAMOPS_HOST_WAIT` (rocm-systems) | P2 | `hipStreamWaitValue_Default` deadlocks (GPU spin-wait on a driver without compute preemption). Opt-in; needs rebase onto current develop. |
| dxg honor CU mask on PM4 path (rocm-systems) | P2 | CU masks (`hipExtStreamCreateWithCUMask`, green/exec contexts) silently ignored. Opt-in. |
| dxg internal blit queue on COMPUTE1 (rocm-systems) | P2 | Alternative mempool-contention mitigation; superseded by fix 9 for the mempool tests. Opt-in. |
| dxg device-trap handler prototype (rocm-systems) | P3 | Reports device traps to the host; cannot be installed on gfx90c's legacy KMD (escape refused). Needs a driver that accepts the set-trap escape. |

## Notes on cross-arch scope

- **gfx9-general** (would apply to gfx908/gfx90a if they ran the Windows dxg path): fixes 2, 3, 6, 8;
  LLP64 headers; device-libs dots; LLVM trap. Fix 6 mirrors Linux `gfx_v9_0_emit_mem_sync` (the
  generic gfx9 cache-sync), so it is not gfx90c-specific.
- **Client-APU-specific** (gfx902/909/90c, not gfx908/90a): fix 7 (those parts are XNACK-unsupported;
  gfx908/90a support XNACK), fix 9's APU VRAM-carve-out trigger (gfx908/90a are large-VRAM dGPUs),
  legacy-CK macro.
- **arch-independent**: MIOpen fused-conv, MultiMarginLoss, device-assert message, all CI fixes.

## Empirical cross-ISA confirmation (gfx906, 2026-10-08)

The scoping above is confirmed on real gfx906 (4x MI50, Linux KFD) vs gfx90c (Windows dxg). See
`compare/A906vsA7.md`. hip-tests catch: 0 tests fail on both ISAs, and all 23 gfx90c failures our
fixes target pass on gfx906. The 336 component gtest suites (rocPRIM/rocThrust/rocRAND/hipCUB:
17816 subtests) pass with 0 correctness failures, the direct control for fix 6 (those components,
broken on gfx90c-Windows by the L1-cache bug, are clean on Linux where the dxg ACQUIRE_MEM path is
not taken). No gfx906 failure is attributable to our changes. gfx90a/gfx900 were not run (gfx906 is
the closest ISA and was deemed sufficient).
