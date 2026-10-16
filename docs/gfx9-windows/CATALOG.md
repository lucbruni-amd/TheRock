# gfx9 on Windows (ROCr backend): every fix and change, in one place

**STATUS 2026-10-09: ACHIEVED on gfx90c** (functional via ROCr; ~270k test executions, no unexplained gfx9 defect; prototype/opt-in items and upstream submission remain). **Re-validated 2026-10-13 at the current TheRock pins (section 1b).** Nothing here has been posted publicly; upstreaming is sequenced (wkmi first) and tracked internally.

This branch is the source of truth for the code: every carried change is a patch under
`patches/amd-mainline/` with an upstream-ready commit message (Conventional Commits title, why,
evidence), and the opt-in prototypes are under `patches/gfx9-win-experimental/`.

Per-change priority and "what breaks without it" live in `../CHANGE-IMPACT.md`.

Base: TheRock nightly 7.15.0a20260728 (TheRock `fe040db0`, rocm-systems `44be71b5`, rocm-libraries
`baa93758`, wkmi `331b1985`). Hardware: gfx90c (Ryzen 7 5700G iGPU), Windows 11 26200, legacy
driver 31.0.21925.1001 (kmd 2319). Controls: gfx1036 iGPU (same PM4-emulation queue path, Windows),
gfx908 (Linux, official nightly). Every patch was checked to apply to the relevant `develop` /
`amd-staging` branch on 2026-10-06/07 unless noted.

Fix 10 (PAL->ROCr fallback) removes the need to set `GPU_ENABLE_PAL=0` by hand; validated in its
first form on 2026-10-09 and in its refined form at the current pin on 2026-10-13 (section 1b).
Historical recommended runtime at the 7.15 nightly pin: fixes
1-4 + 6 (full) + 7 + 8 + 9, built at the nightly pin
(dllstash `P2_final_vmm`, 48623BCC, which also contains P2 and the opt-in experimental changes);
`P2_final_bp` (FF1DF124) adds the section 2c upstream backport (A8: 2585/25/335, no regressions).
Official hip-tests (2945, CI env): 2581 pass / 30 fail / 334 skip, identical on every test before
and after fixes 6-9 (A4/A5/A6/A7). Of the 30: 17 pass once rebuilt with the section 2 fixes, 3 are
PAL-only tests, 5 are fixed upstream after the nightly (section 2c), 1 is the box SDK, and 4 are
cross-queue waits (section 7; 2 of them TheRock ignores on gfx110X).

## 1. Runtime fixes (required)

| # | patch | repo / file | what it fixes | scope | validated |
|---|---|---|---|---|---|
| 1 | `../rebased/wkmi-331b1985-gfx9-fixes-1-4.patch` | AMD-ROCm-Internal/wkmi `wkmi.cpp` | `DetectGfxIpVersion` has no FAMILY_AI / FAMILY_RV entries, so no gfx9 GPU is enumerated ("No WDDM adapters found", hipInfo "no ROCm-capable device") | gfx9 Windows | gfx90c enumerates; hip-tests A3-A6 |
| 2 | `0011-rocr-dxg-gfx9-umd-allocated-user-queue.patch` (carried since 2026-10-13; before that only `../rebased/rocm-systems-44be71b5-gfx9-fixes-2-3.patch`) | rocm-systems dxg `device.h` | `AllocUserQueueMemFromUMD` true only for major 10; gfx9 also needs the UMD-allocated user queue, else every submit fails with c01e0200 | gfx9 Windows | first kernel dispatch; hip-tests |
| 3 | `0012-rocr-dxg-report-unknown-queue-errors-as-exception.patch` | rocm-systems dxg `queue.cpp` | `HandleError` reports unknown queue errors as -1 (all error bits), which ROCr misreads as "insufficient scratch" and then access-violates; use 0x80000000 (HSA_STATUS_ERROR_EXCEPTION) | Windows ROCr | queue errors reported cleanly |
| 4 | `../rebased/wkmi-331b1985-gfx9-fixes-1-4.patch` | wkmi `wkmi.cpp` | GPU clock attributes about 100x too large for kmd < 2510 | Windows, legacy KMD | kmd 2319 and 2510/2520 branches |
| 5 | (dropped) | rocm-systems dxg | `hipMemGetInfo` failed on APUs; superseded by the upstream librocdxg sync (rocm-systems #8012, 2026-07-03), already in the nightly | - | - |
| 6 | `dxg-gfx9-acquire-mem-invalidate-vector-l1.patch` (**full variant, chosen**); `...-MINIMAL.patch` kept for reference | rocm-systems dxg `cmd_util.cpp` | gfx9 ACQUIRE_MEM never invalidates the vector L1 (or touches L2): stale cross-kernel reads, wrong results, runaway kernels, engine-reset storms, one 0x10E bugcheck | gfx9 Windows | 30-line repro; rocprim, rocthrust, hipsolver (11746/11746 vs 8095 fail + reset), hipfft, hipdnn; hip-tests 0 regressions; `dxg-gfx9-acquire-mem-evidence/` |
| 7 | `clr-isa-gfx9-client-apus-xnack-unsupported.patch` | rocm-systems CLR `rocclr/device/device.cpp` | CLR's ISA table was not updated when ROCr made gfx902/909/90c XNACK-unsupported (#2669, #8237), so every `:xnack-` code object (MIOpen asm kernels) is rejected: "no kernel image is available" | gfx902/909/90c, Windows **and Linux** | hipDNN conv samples, miopenprovider 788 -> 2 failures (Windows); patched vs unpatched CLR on Linux; `clr-isa-evidence/` |
| 9 | `clr-mempool-windows-apu-vmheap-and-7988-rollback.patch` | rocm-systems CLR `rocdevice.cpp`, `vmheap.cpp` | on Windows APUs the memory-pool VM heap commits 128 MiB VMM chunks from the small carve-out the thunk uses for VMM memory, so `hipMallocAsync` fails early; the failure path then frees a still-linked block (TheRock#7988) and the heap corrupts itself (SEH flood, garbage sizes, hangs) | Windows ROCr APUs (gfx90c, gfx1036); the #7988 part on all OSes | hipsparse 509 OK + OOM + SEH + timeout -> 22,207/22,207; rocsparse 933 OK + OOM -> 18,642/18,642 (default settings); `clr-mempool-evidence/` |
| 8 | `clr-win-exit-hang-skip-unregister-on-process-exit.patch` | rocm-systems CLR `hip_runtime.cpp`, `hip_platform.cpp` | a process with a HIP DLL hangs forever at exit if GPU work is in flight (`__hipUnregisterFatBinary` drains streams after Windows killed the thunk's helper threads) | Windows ROCr PM4 path: gfx9 **and RDNA2 (official nightly)** | repro and fix on gfx90c and gfx1036; `clr-win-exit-hang-evidence/` |
| 10 | `0004-clr-windows-pal-fallback-to-rocr-when-no-device.patch` (refined 2026-10-13 for the Phase 2 PR: switches only when ROCr registers a GPU, HIP only, no ROCr offline devices; PAL-less branch validated on gfx90c at the current pin, PAL-on branch by inspection) | rocm-systems CLR `rocclr/device/device.cpp` | `Device::init()` forces `GPU_ENABLE_PAL=1` on Windows when the flag is default; PAL has no gfx9, so gfx9 gets no device unless the user sets `GPU_ENABLE_PAL=0`. Two parts: (1) PAL-less builds (ROCCLR_ENABLE_PAL=OFF, incl. the box) force `GPU_ENABLE_PAL=0` on Windows default (the default 2 trips `rocdevice.cpp`'s "disable HSA except gfx942" `==2` guard, so ROCr inits but registers no device); (2) PAL-on builds (shipped TheRock, =ON) fall back to ROCr when the Windows-default PAL path registers no online device | gfx9 Windows (works out of the box) | **Part 1 VALIDATED** on gfx90c box (PAL-OFF): with `GPU_ENABLE_PAL` unset, unpatched = "No devices found", patched = gfx90c enumerates + GETRI 84/84 pass. Part 2 correct-by-inspection (box cannot build PAL-ON). RDNA-on-PAL untouched (numDevices>0 guard); `clr-windows-pal-fallback-evidence/` |
| 11 | `0010-rocr-dxg-map-system-memory-to-peer-adapters.patch` | rocm-systems dxg thunk `memory.cpp`, `wddm/gpu_memory.{h,cpp}` | host (CPU-node) allocations are created on one WDDM adapter (`default_node`, always the first GPU) and `hsaKmtMapMemoryToGPUNodes` returned success for the other GPUs without mapping anything. Every GPU but the first gets unmapped kernarg/staging/host-pool VAs and hangs on its first operation. Exposed by the 2026-07-10 wkmi update (rocm-systems 5190f14b56), which enumerates gfx103X APUs under ROCr, so the iGPU became node 1 (bisected 7.15.0a20260711 good, 0713 bad). Fix: mirror each kSystem allocation onto every requested peer adapter over the same CPU pages, at the same SVM address (already reserved on all adapters) | Windows ROCr, any multi-adapter system (common: Ryzen iGPU + dGPU); not gfx9-specific | gfx1036 + gfx1201: gfx1201 HANG -> OK; both GPUs in one process incl. cross-device via pinned host OK; both ownership orders OK; 300-iteration alloc/use/free stress 0 mismatches (stock 10.1 hangs); single-GPU gfx1100 unchanged. Built from the box's older source tree (ported line for line; the Lock2 line has no equivalent there) |

| 9b | `0013-fix-clr-report-pool-access-in-hipMemGetAccess-without-the-VM-heap.patch` | rocm-systems CLR `hip_vm.cpp`, `hip_mempool_impl.*` | fix 9 turns the memory-pool VM heap off on Windows APUs, after which `hipMemGetAccess` on a pool allocation fails (it only asked for VMM access). Report the owning pool's access instead. Found by the gfx10-win full hip-tests run (`Contract_MemLocationPool_HipMemGetAccess_Default`) | Windows ROCr APUs; IPC pools on all OSes | gfx1036: 98/99 -> 99/99 mempool/access subset; gfx1201 99/99. Validated at the gfx10-win pin, applies clean here; not rebuilt at this pin |

Also found while root-causing fix 11 (not patched): the thunk's `ROCR_VISIBLE_DEVICES` handling in
`init_vars_from_env()` sets `default_node`, but topology init runs later and overwrites it with
`numa_node_count_`, so that code never takes effect (and its comment's "+1" is not implemented).

## 1b. Re-validation at the current pins (2026-10-13)

The carry (`patches/amd-mainline/rocm-systems/` 0001-0012) and the opt-in patches were rebuilt on the
gfx90c box against the rocm-systems pin of this branch (`6c654d4ff9`), with wkmi `bba4d03` (the wkmi
that pin consumes; its interop `wkmi.h` is byte-identical) plus fixes 1 and 4. PAL off, flags as in
TheRock `core/CMakeLists.txt`, toolchain 7.15.0a20260728. GPU tests run one at a time, one process per
test.

| check | A: carry | B: carry + opt-in 0001-0004 | C: carry, fix 10 refined |
|---|---|---|---|
| build | OK | OK (all 4 apply clean) | OK |
| vadd canary, `GPU_ENABLE_PAL` unset / =0 | OK / OK | OK / OK | OK / OK |
| `GPU_ENABLE_PAL=1` explicit | no device (respected) | not run | no device (respected) |
| hipInfo | gfx90c, 8 CUs, 1000 / 1067 MHz | same | same |
| CU mask probe, distinct CUs default / 0x1 / 0x3 | 8 / 8 / 8 | 8 / 1 / 2 | 8 / 8 / 8 |
| `DXG_TRAP=1` | n/a | KMD refuses the escape, bound=0, runs clean | n/a |
| 4 `hipMalloc[FromPool]Async_Basic_*` | crash (queue error) | 4/4 pass | |
| `Unit_hipStreamWaitValue_Default` u32/u64 | 2 fail (watchdog) | 2/2 pass | |
| 121 StreamTest cases except Wait_Blocking | 2 fail + the 2 above | the same 2 fail only | |

- Fix 2 (0011): kernel dispatch works at the pin. Fix 3 (0012): the watchdog resets in A are reported
  as a clean `HSA_STATUS_ERROR_EXCEPTION` (0x1016), no scratch misread, no access violation.
- The 2 StreamTest failures in every state (`InChildProcess`, `TwoThreadsDiffOpSpt`) are open
  (section 7).
- Running several stream tests in one process gives misleading failures (negative tests leave a sticky
  `hipGetLastError`); only per-process results count.
- Fix 10's PAL-on branch cannot be built on the box (PAL is DVC-only); it is correct by inspection.
- Not rerun at the pin: the full hip-tests suite (about 1.5 h; earlier full runs used 7.15).
- Linux full build of this branch (gfx1201): rocminfo, vadd, a `__builtin_trap` kernel (clean
  `HSA_STATUS_ERROR_EXCEPTION`), rocRAND 44/44, hipRAND 85/85.

## 2. Compiler, header, library and test fixes (correct results)

| patch | repo / file | what it fixes | scope | validated |
|---|---|---|---|---|
| `device-libs-dots-gfx90c-and-fdot2-regression.patch` | ROCm/llvm-project device-libs `ockl/src/dots.cl` | dot builtins emit missing opcodes or are silently deleted on gfx90c/gfx1013; fdot2 regression on gfx900/902/904/909/1010 from 6f5e729 | OS-independent, current nightlies | 33 targets x 7 functions; hipTestNativeHalf; Rtc_MathFunctions_header and Rtc_fp16_header through hiprtc (LLVM_PATH A/B) |
| `hip-headers-llp64-warp-reduce-and-lastbit.patch` | rocm-systems CLR public headers | `1ul << laneId` (warp reduce/scan generic path) and `__builtin_ctzl` in `__lastbit_u32_u64` are 32-bit on Windows | wave64 on Windows (= gfx9); lastbit all archs on Windows | device IR diff Linux vs Windows; reduceprobe3; Rtc_ReduceRandom with rebuilt hiprtc |
| `hip-tests-warp-reduce-llp64.patch` | rocm-systems hip-tests | same LLP64 bug in the tests | Windows | WarpTest 13 -> 0 failures |
| `miopen-multimarginloss-windows-llp64.patch` | rocm-libraries MIOpen `multimarginloss/invoke_params.hpp` | host `long p` vs kernel `int64_t p`: all MultiMarginLoss cases fail on every Windows GPU (PAL and ROCr) | Windows, all GPUs | gfx1036 PAL+ROCr 0/32 -> 32/32 (embedded-kernel A/B); `miopen-windows-gfx9-evidence/` |
| `miopen-legacy-ck-gfx9-apus.patch` | MIOpen legacy CK `utility/config.hpp` | `#error No CK_AMD_GPU_GFX* macro defined` for gfx902/909/90c: Reduce and RNN kernels fail to compile | gfx9 APUs, all OSes | gfx90c Reduce/RNN 8/20 -> 20/20 (embedded-header A/B) |
| `miopen-tests-uncharacterized-arch.patch` | MIOpen gtest `gtest_common.cpp`, `handle_test.cpp` | `unknown_gpu` thrown from every solver test SetUp on gfx90c (382 failures); arch-name test list lacks gfx90c/gfx1036 | test-side | code review |
| `hip-headers-windows-device-assert-message.patch` | rocm-systems CLR public header `hip_assert.h` | on Windows `assert()` calls `_wassert`, which was only `__builtin_trap()`, so a failing device assert printed nothing | all GPUs on Windows | gfx90c: message printed per failing thread; `hip-headers-windows-device-assert-evidence/` |
| `miopen-fused-conv-grouped-path.patch` (stopgap: `...-reject-groups-STOPGAP.patch`) | rocm-libraries MIOpen fused kernel `MIOpenConvDirBatchNormActivHip.cpp` | `ConvHipDirectFwdFused` computes grouped convolutions as ungrouped (wrong results; reads past the weight buffer) | all GPUs this solver runs on, Linux and Windows (upstream bug) | hipDNN grouped conv+bias+activ on Linux gfx908: FAIL -> OK with the patched kernel, control unchanged; whole hipDNN MIOpen smoke suite 1329/2 fail -> 1331/0 fail; `miopen-fused-conv-evidence/` |
| `llvm-amdgpu-trap-endpgm-fallback.patch` | ROCm/llvm-project `amd-staging` AMDGPU backend (`SIISelLowering.cpp`, `AMDGPULegalizerInfo.*`, `AMDGPUUsage.rst`, 6 tests) | `llvm.trap` (`__builtin_trap`, failed device `assert`) is a bare `s_trap 2`; where no trap handler can be installed (gfx90c's legacy KMD refuses the escape) it is a no-op and the wave runs whatever follows: garbage, TDR, a poisoned GPU. Now followed by the existing `ENDPGM_TRAP` fallback (`s_endpgm`), unreachable when a handler exists | every target with the AMDHSA trap handler ABI that runs without a handler; the runtime-side handler stays an open item | llc: 28 trap tests (6 regenerated) and all 5145 `CodeGen/AMDGPU` tests pass; code-object A/B disassembly; gfx90c: `__builtin_trap` and `assert` now stop all 64 lanes at the trap and the GPU stays healthy (before: lanes ran past, engine reset, poisoned GPU); `llvm-amdgpu-trap-endpgm-evidence/` |

The 17 official hip-tests these fix still fail in the official binaries (they embed the old
headers / bitcode); with the fixes rebuilt they pass.

## 2b. CI and test-configuration fixes

| patch | repo / file | what it fixes | validated |
|---|---|---|---|
| `therock-ci-skip-hipblaslt-on-windows-unsupported-families.patch` | TheRock `build_tools/github_actions/fetch_test_configurations.py` | hipblaslt and hipblasltprovider jobs are scheduled on Windows for families whose targets all exclude hipBLASLt (TheRock#1062), e.g. the existing gfx103X-all Windows runner, where they can only fail; Linux already lists gfx1030. Adds the Windows family strings (gfx900, gfx906, gfx90c, gfx101X-dgpu, gfx103X-all) | local matrix run: Windows gfx103X-all 29 -> 27 jobs (both dropped), gfx110X/120X/1151 unchanged at 30; module tests 66 passed |
| `rocprim-tests-gfx90X-windows-quick-partition.patch` | rocm-libraries rocPRIM `test/test_categories.yaml` | `test_device_partition` passes on gfx90c (85/85) but takes 6.3 min against the 300 s quick timeout; the 1 KiB-element cases are ~190 s of it. Windows-only gfx90X block drops `RocprimDevicePartitionTests/11.*` from the quick tier | full binary 85/85 in 6.3 min on gfx90c; remainder timing in chain2 |
| hiptensor quick-tier packaging | rocm-libraries hipTensor `test/CMakeLists.txt` | quick ctest entries use `./bin/<exe>` with an install-root working dir: all 57 "Not Run" on every GPU. **Already fixed upstream** (rocm-libraries 0d88e7b3008, #10712; first TheRock pin with it: cb2adb3ec, 2026-08-19) | equivalent CTestTestfile rewrite on gfx90c: component PASS (all cleanly skipped, hipTensor excludes gfx90c) |
| `therock-ci-windows-prefer-artifact-dlls-over-system32.patch` | TheRock `test_executable_scripts/` (`libhipcxx_utils.py`, `test_libhipcxx_amdclang.py`, `test_runner.py`, `test_hipthreads_examples.py`) | Windows searches System32 before PATH, so test executables outside `bin\` load the display driver's `amdhip64_7.dll` (TheRock#7132): all 2419 libhipcxx lit tests, and `generate_resource_spec.exe` in `bin\{rocprim,hipcub,rocthrust}`. With a driver runtime that lacks the GPU (gfx9) they fail outright; elsewhere they test the driver, not the artifact. Moves PR #7143's `SetDllDirectoryW` helper into the shared module and calls it in both places | probe: the setting reaches the exe through python -> ninja -> cmd -> lit -> spawn worker; generate_resource_spec A/B (no device vs gfx90c found, TheRock's runtime loaded); hipcub FAIL -> PASS; libhipcxx: all 2419 tests now run on TheRock's runtime and each reaches its expected result on gfx90c (2128 pass, 238 unsupported, 13 xfail in the suite run; the 32 that timed out or failed under GPU contention pass or xfail when run alone); Black clean; `therock-ci-windows-dll-evidence/` |

## 2c. Fixed upstream after the 7.15 nightly (no new patch; pick up a newer pin)

These hip-tests failures also fail on the gfx1036 control (shared Windows ROCr code, not gfx9), pass
in CI on the AQL/MES path, and TheRock does not ignore them. Each has an upstream fix that landed
after the nightly (2026-07-28). `BACKPORT-rocm-systems-8974-9385-9652-9633-onto-44be71b5.patch` puts
all four onto our tree: dllstash `P2_final_bp` (FF1DF124). On gfx90c the 19 BatchAsync/NoCU/EventIpc
tests all pass or skip as expected, and the full hip-tests run A8 is 2585 pass / 25 fail / 335 skip
vs A7 2581/30/334: the five move to pass (4) or the correct skip (EventIpc, emulated IPC events),
zero tests regress, and the run is 9 minutes shorter (no BatchAsync timeouts).

| test(s) | root cause (from gfx1036 logs and source) | upstream fix | first TheRock pin |
|---|---|---|---|
| `Unit_hipEventIpc_DestroyNonBlocking` | `roc::Device::createIpcSignal()` returns an object on Windows, so HIP picks ROCr IPC events, but the dxg thunk implements no memory sharing (`hsaKmtShareMemory` is NOT_IMPLEMENTED), so `hipIpcGetEventHandle` fails | rocm-systems #8974, 1555ce1abba (2026-07-31): emulated IPC events on Windows ROCr, like PAL | 4d7626337 (2026-08-03) |
| `Unit_hipMemcpyDeviceToDeviceNoCU_NoCU_MulStrm` | one SDMA engine on the APU; CLR assigns engines exclusively per stream, so the 2nd and 3rd streams' SDMA-only copies fail ("No unallocated SDMA engines", "shader fallback is not permitted") and are dropped while `hipMemcpyAsync` still returns success | rocm-systems #9652, 8c1053773ae (2026-08-06): share an engine once streams outnumber engines (it failed on Navi48 and Strix Halo too) | 093e43c94 (2026-08-06) |
| `Unit_hipMemcpyBatchAsync_{H2D,D2H}_Functional`, `_H2D_Pageable_Stream_SourceAccess` | 512 KiB pageable batch copies go to the SDMA batch path; on single-SDMA-engine APUs it never completes and `hipStreamSynchronize` spins forever | rocm-systems #9385, 23294c488fd (2026-08-04, TheRock#5514, Strix Halo): engine_offset check for 1-engine APUs + shader fallback; #9633, 6e6868c8176 (2026-08-14): pinned buffers released too early on ROCr-on-Windows | 30775f000 (2026-08-05), 54e4aa4e2 (2026-08-17) |

## 3. Experimental runtime changes (validated, opt-in)

Carried since 2026-10-13 under `patches/gfx9-win-experimental/rocm-systems/` (not applied by
`fetch_sources.py`; see the README there). All four were rebased onto the current pin; the CLR and
ROCr parts compile on Linux, the dxg parts have not been rebuilt since the rebase.

| patch | what | validated |
|---|---|---|
| `0002-dxg-gfx9-isolate-internal-queue-on-compute1.patch` (P2) | runtime's internal blit queue alone on COMPUTE1 so code-object uploads run while a user kernel occupies COMPUTE0 | 4 mempool tests fixed, 0 regressions (A4) |
| `0003-dxg-pm4-honor-cu-mask.patch` | CU masks (`hipExtStreamCreateWithCUMask`, `HSA_CU_MASK`, green/execution contexts) were silently ignored on the PM4 path | `__smid()` probe 8/8 -> 1/2 CUs; 68 related hip-tests unchanged |
| `0001-clr-pm4-host-stream-wait.patch` | `hipStreamWaitValue32/64` on PM4-emulated queues (ROCr `HSA_AMD_AGENT_INFO_PM4_EMULATION`) with host memory: a barrier that depends on a signal holds the stream (the PM4 emulation resolves it on the CPU) and a CPU thread polls the value and releases the signal, instead of a GPU spin kernel that holds the engine on a driver without compute preemption. `GPU_STREAMOPS_HOST_WAIT=0` disables it. Design and alternatives: `clr-pm4-host-stream-wait-evidence/` | dllstash `P2_final_hw` (C7ACB41D): `Unit_hipStreamWaitValue_Default` uint32/uint64 FAIL -> PASS (0.17 s), the other 21 stream-value tests unchanged (pass); every host-memory leaf of `Wait_Blocking` passes (9 conditions x 3 pointer kinds x 2 widths), its device-memory leaves still fail (GPU spin kernel kept there). Full hip-tests A9: 2587/23/335 vs A8 2585/25/335, zero regressions |
| `0004-dxg-gfx9-trap-handler.patch` (handler source and probe: `trap-prototype/`) | device traps (`assert`, `abort`, `__builtin_trap`): new gfx9 handler records the trap and ends the wave; the thunk enables it per dispatch and reports the error after the fence (env `DXG_TRAP=1`) | built (dllstash `P2_final_trap`); on gfx90c the KMD refuses the set-trap escape, so it stays disabled (bound=0). Kept for drivers that accept it |

## 4. Build workarounds (box-only, not part of any fix)

- Runtime build (`build44*.bat`): TheRock's Windows hip-clr flags, except `ROCCLR_ENABLE_PAL=OFF`
  and wkmi from source (both DVC-only libs); `HIP_DEVICE_LIB_PATH=<dist>\lib\llvm\amdgcn\bitcode`
  (clang treats `ROCM_PATH` as exclusive and TheRock keeps bitcode under `lib\llvm`).
- Older source build: `image/blit_src/CMakeLists.txt` needs `--rocm-device-lib-path` appended;
  `hiprtc/CMakeLists.txt` `find_program` needs `${ROCM_PATH}/lib/llvm/bin` in HINTS (else VS clang).
- Runtime build at the current pin (`pinval\buildpin.bat`): CLR also needs `projects/hrr` from the
  same rocm-systems tree (for `hrr/hrr_api_args.h`) and `HIP_DEVICE_LIB_PATH` set.
- hip-tests build: `-DHRR_CLR_DIR=<clr>/hipamd/src/hrr`, CMake 4.4.3 (3.31 fails on Catch2 with
  clang 23); hiprtc embeds headers twice, so rebuild both hiprtc DLLs after header fixes.
- Device-libs validation: full standalone device-libs build (splicing ockl.bc does not work).
- Linux CLR A/B: build in manylinux_2_28 (host builds need glibc 2.38; RHEL 8 has 2.28).

## 5. Test-harness settings used to reproduce TheRock CI on this box

- Scripts from TheRock `fe040db0` (`run_components.ps1` drives `test_runner.py` etc.), plus
  `version.json` in the scripts root (needed by libhipcxx).
- `GPU_ENABLE_PAL=0` (CI runs PAL; PAL has no gfx9), `HIP_PLATFORM=amd` (the box has the NVIDIA
  CUDA toolkit, so hipcc would pick nvcc), `OUTPUT_ARTIFACTS_DIR=<dist>`, `ROCM_PATH` unset for
  sanity (CI does not set it).
- The box's newest Windows SDK (10.0.28000.0, from the WDK) is partial: `INCLUDE` and `LIB` point
  at SDK 10.0.26100.0 and MSVC 14.44 (`run_components.ps1 -IncludeFix`). Fixes hiprtc `stddef.h`,
  sanity and hipdnn_install link errors.
- hip-tests: CI env (`THEROCK_REQUIRE_HIP_YAML_ENTRIES=1`, `DEBUG_HIP_GRAPH_MIN_OVERLAP=0`, same
  exclusions), `runci.ps1`, 180 s timeout.
- Standalone test dirs need `amd_comgr.dll` + `AMD.ROCM.Comgr.MANIFEST` + `rocm_kpack.dll` next to
  `amdhip64_7.dll` (CLR loads comgr from the runtime's own directory).
- Until 2026-10-07 the runtime DLLs were also hardlinked into `bin\{rocprim,hipcub,rocthrust}` so
  `generate_resource_spec.exe` found them. That masked the CI bug fixed in section 2b; the hardlinks
  are gone (official layout; kept in `C:\Users\rocm\dllval\hardlinks_backup`). Use the patched
  scripts in `C:\Users\rocm\tr715dll` (`run_components_v4.ps1 -Tr C:\Users\rocm\tr715dll`).
- Defender exclusions (it quarantines unsigned HIP DLLs): `cmpA2`, `install44`, `build44`,
  `kerneltest`, `dllstash`, `rk90c\bin`, `ht44` (gfx90c box); `rk103x`, `rk120x`, `cmpG2` (control).

## 6. Box state to restore when done

- gfx90c box: `HKLM\SYSTEM\CurrentControlSet\Control\CrashControl CrashDumpEnabled` is 2 (kernel
  dump, for the BSOD investigation); original value 3.
- `rk90c\bin\amdhip64_7.dll` and its hardlinks: currently our build; official copy is
  `amdhip64_7.official.dll`. HIP headers in `rk90c\include` restored to official.
- `rk90c\bin\amdhip64_7.dll`: now `P2_final_bp + fix 10 Part 1` (306F6837, from `install44`, used to
  validate fix 10; gfx90c works with `GPU_ENABLE_PAL` unset). Prior `P2_final_bp` (FF1DF124) kept as
  `rk90c\bin\amdhip64_7.pre-fix10.dll`. `src44` device.cpp has fix 10 Part 1; original `device.cpp.pre-fix10`.
  `cmpA2\catch_tests\amdhip64_7.dll`: `P2_final_hw` (C7ACB41D, used for A9).
- `src44`: section 2c backport applied; originals kept as `*.pre-bp`.
- GPU watchdog: `TdrDelay`/`TdrDdiDelay` under `...\GraphicsDrivers` are deleted again (Windows
  default 2 s), restored 2026-10-08 06:09 after the libhipcxx runs. A gfx9 iGPU CI runner would want
  ~30 s (section 7).
- `src44`: CPU-side stream wait prototype applied by chain7 (originals kept as `*.pre-hw`).
- Defender exclusion added for `C:\Users\rocm\trape2e` (LLVM trap check).
- 2026-10-13 re-validation: `C:\Users\rocm\pinval\` (sources `srcA/B/C` with a `drivers` junction to
  `srcbuild\drivers`, `installA/B/C`, test dirs `tA/B/C`, scripts and logs; build dirs deleted) and a
  Defender exclusion for it. Restore: `Remove-MpPreference -ExclusionPath C:\Users\rocm\pinval`, then
  delete the folder. Disk C: has about 3.4 GB free.
- The `rk90c\bin` and `cmpA2\catch_tests` `amdhip64_7.dll` hashes recorded above were not reproduced
  on 2026-10-13 (both read 34E653A2; possibly a different hash method). Re-check before relying on
  them.

## 7. Open items (not fixed yet)

- Device traps, runtime side: no trap handler can be installed on gfx90c (the legacy KMD refuses
  the escape). The compiler fallback (section 2, LLVM) makes traps end the wave cleanly instead of
  running off; the dxg prototype (section 3) reports them for drivers that accept the escape.
  gfx1036 (official runtime): traps hang the process and wedge the iGPU until a device restart.
- `hipStreamWaitValue_Default` (in scope, lower priority; `hipStreamValue_Wait_Blocking` is left,
  TheRock ignores it on gfx110X Windows). Root cause: CLR's default stream wait
  (`GPU_STREAMOPS_CP_WAIT=0`) is a GPU spin kernel. The legacy KMD has no compute preemption
  (dxdiag `Compute Preemption: DMA`; DisablePreemption=0 tested: no effect) and no hardware
  scheduling (dxdiag `Hardware Scheduling: DriverSupportState:AlwaysOff`), so the spin holds the
  engine while the write it waits for sits queued behind it on another queue, until the watchdog
  fires. Prototype fix: section 3 (`gfx9-win-experimental/rocm-systems/0001-clr-pm4-host-stream-wait.patch`).
- A slow gfx9 iGPU runner also needs a longer GPU watchdog and fewer parallel GPU tests: libhipcxx
  runs whole test bodies as single-thread kernels (up to ~7 s here), and lit starts the slowest
  saved tests first. 16 workers at once on a GPU that runs one context at a time (no hardware
  scheduling, DMA-level preemption) wedged it. With `TdrDelay=10` + `LIT_OPTS=-j8` the suite completes (90 min) but ~9 s bitset kernels running together still push 32 tests past their limits; about 30 s of watchdog and 4 workers is the safe setting.
- A gfx9 Windows runner needs `GPU_ENABLE_PAL=0`: `test_component.yml` defaults Windows to PAL, and
  so does the runtime itself (`device.cpp` forces `GPU_ENABLE_PAL=1` on Windows when unset). PAL
  has no gfx9, so end users must set it too. ADDRESSED by fix 10 (section 1, patch 0004): the runtime
  falls back to ROCr when the Windows-default PAL path finds no device, so gfx9 works without the env
  var (validated at the current pin, section 1b). `test_component.yml` still defaults Windows
  jobs to PAL, so the CI-side default is a separate (not-yet-made) change if a gfx9 Windows runner is
  added.
- `StreamTest InChildProcess` and `TwoThreadsDiffOpSpt` fail on gfx90c at the current pin, with and
  without the opt-in patches (section 1b). Not root-caused yet.
- hipBLASLt has no gfx90c (or gfx900/906/101X/103X) kernels by design (TheRock#1062); only the CI
  job selection needed fixing (section 2b).

## 8. Other pre-existing bugs found along the way

- `BlitSdma::AcquireWriteAddress` access-violates when a submit fails (failure unchecked).
- `WDDMDevice::CreateContext` returns c0000017 (STATUS_NO_MEMORY) on the SDMA fallback path.
- comgr's in-process clang has no resource dir on Windows unless `LLVM_PATH` is set, so hiprtc
  depends on the newest installed Windows SDK having UCRT headers.
- Defender's ML flags unsigned `amdhip64_7.dll` builds (official TheRock ones too) as
  `Trojan:Win32/Bearfoos.A!ml`; apps then silently load the driver's `System32` runtime.
- Windows CI never exercises the ROCr PM4-emulation path (gfx9, RDNA2): ROCR hip-tests jobs run only
  on MES parts.
- `rocm_openblas!blas_level1_thread` integer-divides-by-zero (SEH 0xC0000094) on Windows for small
  level-1 problems. Surfaced by the standalone `rocsolver-test checkin_lapack/LASWP` suite (48/192
  cases, the real-row-swap small-n ones) via its CPU reference `cpu_laswp`; cdb points the fault at
  `blas_level1_thread+0x197`. Host reference BLAS only, not rocSOLVER/kernel/runtime; the identical
  suite passes 192/192 on gfx906-Linux (Linux OpenBLAS). Affects any GPU running these tests on
  Windows. Belongs in the rocm OpenBLAS build, not this gfx9 package.

## Runtime builds on the box (`C:\Users\rocm\dllstash`)

`A2_fixes1-4` (F60276E3), `P2_clean` (2D385638), `P2_cachefix` (8B1461C7, fix 6 full), `P2_tcl1only`
(67C4D4F8, fix 6 minimal), `P2_cachefix_isa` (6845E505, + fix 7), `P2_cachefix_isa_exit` (12DCA7DD,
+ fix 8), `P2_final_cumask` (57ECB776, + CU mask), `P2_final_trap` (C5A5ABB9, + trap prototype),
`P2_final_vmm` (48623BCC, + fix 9), `P2_final_bp` (FF1DF124, + section 2c backport; current), `P2_final_hw` (C7ACB41D, + CPU-side stream wait prototype).
Never use `C3_p3` (routes a queue to the VR node, which hard-hung the box).

## 9. Upstream grouping and drift check (re-verified 2026-10-08 against current upstream)

Nothing is posted publicly. Since 2026-10-13: fixes 2 and 3 are carried (0011, 0012); fixes 7 and 10
were re-checked against rocm-systems `develop` `1f343ae3dc` and apply clean (fix 10 refined, section
1). Order of submission: wkmi (fixes 1, 4) first, internally; then enumeration (7, 10), dispatch (2,
3), correctness, gfx9 robustness and opt-in, and last the changes that are not gfx9-specific. Fix 11
(multi-adapter host memory) stays in this carry only. Dry-run `git apply --check` against each repo's
current tip.

| upstream repo (target) | patches | drift today |
|---|---|---|
| AMD-ROCm-Internal/wkmi | fixes 1+4 (`../rebased/wkmi-331b1985-gfx9-fixes-1-4.patch`): FAMILY_AI/RV table, legacy-KMD clocks | internal repo, not re-checked here |
| ROCm/rocm-systems `develop` (f36c15d) | dxg: fixes 2+3 (now carry 0011, 0012), fix 6 (cmd_util); CLR: fix 7, 8, 9, 10 (device.cpp PAL->ROCr fallback); CLR public headers: llp64 + device-assert; hip-tests: warp-reduce llp64 | all CLEAN except fix 9 = applies with offset+fuzz (re-check #7988 still live), stream-wait prototype = 4 hunks need rebase (rocvirtual drifted); fix 10 authored against 44be71b5, re-check offset vs device.cpp tip |
| ROCm/rocm-libraries `develop` (ade4d37) | MIOpen: multimarginloss, legacy-ck, tests-uncharacterized-arch, fused-conv-grouped; rocPRIM: test_categories gfx90X | all CLEAN (hipTensor already upstream, #10712) |
| ROCm/llvm-project `amd-staging` (f95f066) | AMDGPU trap-endpgm fallback; device-libs dots/fdot2 | both CLEAN (the GlobalISel form only differs on TheRock's *older* amd-llvm pin, not on amd-staging) |
| ROCm/TheRock `main` (2fb7b81) | CI: skip-hipblaslt-unsupported-families, prefer-artifact-dlls-over-system32 | both CLEAN |

Already upstream after the nightly, so these need only a newer submodule pin, no PR (section 2c):
rocm-systems #8974, #9385, #9633, #9652.

Natural PR grouping: one per concern, not one giant PR. gfx9-Windows runtime enablement (wkmi + dxg
fixes 1-4,6) is the headline; the LLP64 header bug, the device-assert message, the CLR ISA table,
the exit hang, the mempool heap, the LLVM trap fallback, the device-libs dot bug, each MIOpen fix,
and the two TheRock CI fixes are independently useful and reviewable on their own.

## 9b. Repository footprint and TheRock-fork carry

Every fix lands in one of **5 repositories** (only 5 because of the ROCm monorepo consolidation:
`rocm-systems` already bundles CLR, ROCr/dxg, HIP, comgr, hip-tests; `rocm-libraries` bundles MIOpen,
rocPRIM, etc. Pre-consolidation this would be ~10+ repos).

| repo | changes | TheRock relationship |
|---|---|---|
| ROCm/rocm-systems | dxg 2,3,6 · CLR 7,8,9,10 · HIP headers (LLP64, device-assert) · hip-tests warp-reduce | submodule `rocm-systems` |
| ROCm/rocm-libraries | MIOpen multimarginloss/legacy-ck/tests-arch/fused-conv · rocPRIM test_categories | submodule `rocm-libraries` |
| ROCm/llvm-project | AMDGPU trap-endpgm fallback · device-libs dots/fdot2 | submodule `compiler/amd-llvm` |
| ROCm/TheRock | CI: skip-hipBLASLt-unsupported-families · prefer-artifact-DLLs-over-System32 | the super-repo itself |
| AMD-ROCm-Internal/wkmi | fixes 1, 4 (FAMILY_AI/RV table, legacy-KMD clocks) | **NOT a TheRock submodule** |

**With a TheRock fork branch that carries patches, only 1 repository remains outside it: wkmi.**
`fetch_sources.py` applies `patches/<patch-tag>/<project>/*.patch` to submodules (the mechanism
supports any submodule, not just the `third-party/` deps currently present), so one fork branch can
carry 4 of the 5:
- TheRock itself: the two CI fixes land natively on the branch.
- rocm-systems, rocm-libraries, compiler/amd-llvm (llvm-project): carried as submodule patches under
  `patches/<tag>/`.

wkmi is the exception: it is not in `.gitmodules`, `fetch_sources.py` never fetches it, and TheRock
does not build it (internal Windows DVC/driver lib, pulled prebuilt). Fixes 1+4 cannot ride in the
TheRock fork and, being an internal-only repo, cannot be submitted as a public PR at all; they go
through AMD's internal driver process when cleared.

Caveat: a fork-plus-patches branch is a buildable CARRY (reproduces the whole stack except wkmi), not
upstreaming. For actual merge, all 5 repos still need their own PRs (wkmi internal) per the §9
grouping.
