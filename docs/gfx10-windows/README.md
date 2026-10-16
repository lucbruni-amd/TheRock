# gfx10 (RDNA1 / RDNA2) on Windows: enablement carry toward official support

This branch (`gfx10-win`) collects the fixes needed to move gfx101X (gfx1010/1011/1012) and gfx103X
(gfx1030-gfx1036) on Windows from "builds nightly" to an officially supported, tested release. It is
based on TheRock `main` `248a92b` (2026-10-14) and carries patches with `fetch_sources.py` the same way
`main` does. Nothing here has been posted upstream.

## Where gfx10 on Windows stands today (TheRock `main`, 2026-10-14)

- **Builds:** `gfx101X-dgpu` and `gfx103X-all` build on Windows every night; tarballs, `rocm-sdk-device-gfx10xx`
  wheels and `amd-torch-device-gfx10xx` PyTorch wheels are published to the nightly indexes.
- **Libraries excluded on every OS** (`cmake/therock_amdgpu_targets.cmake`): hipBLASLt (#1062), hipSPARSELt
  (#2042), composable_kernel (#1245 for gfx101X, #4836 for gfx103X), rocWMMA (#1944), hipTensor (#2074).
  aotriton has no gfx10 (#1925), so PyTorch has no flash / mem-efficient SDPA there.
- **rocBLAS:** gfx103X has tuned `asm_full` logic per target (navi21-24, Van Gogh, Rembrandt, Raphael);
  gfx101X has none and runs the generic fallback kernels.
- **Testing:** only gfx103X is tested, on Azure V620 VMs (`windows-gfx1030-gpu-rocm`), libraries on PAL and
  hip-tests on both PAL and ROCr. gfx101X has no Windows test runner. The gfx103X runners were turned off
  on 2026-10-13 (therock-ci-config #57, 27% failure rate). Last full run (rockrel 38346599616): 15 of 58
  jobs fail. `SUPPORTED_GPUS.md` lists all of these as "Release Ready", which the test results do not
  support yet.

### gfx103X Windows test failures (rockrel run 38346599616) and what this branch does about them

| failing job | signature | status on this branch |
|---|---|---|
| hip-tests (ROCR), 4 shards | ctest discovery crashes in `__hipRegisterFatBinary` (access violation / 0xc0000374) on V620 | reproduced on our box with only the gfx1201 dGPU visible: multi-adapter host memory bug, **fixed by rocm-systems 0008**. V620 runners are single-adapter, so their crash may differ: needs a V620 debug log and dump (#4641) |
| hip-tests (PAL), 2 shards | `Unit_hipStreamValue_Wait_Blocking` hangs, GPU wedged, rest of shard times out | **excluded on Windows gfx103X-all** (as gfx110X already is); real fix: opt-in 0001 |
| hipblaslt, hipblasltprovider | "Could not load TensileLibrary_lazy_gfx1030.dat", kpack kernel not found | **test jobs skipped** (no hipBLASLt kernels for gfx10, #1062); load failures now logged (rocm-libraries 0004) |
| miopen (4 shards) | GPU_MultiMarginLoss FP32/FP16; ImplicitGemm WrW tolerance; bnorm regression | **MultiMarginLoss: expected fixed** (rocm-libraries 0002, LLP64; same failure fixed on gfx1036, 0/32 -> 32/32); ImplicitGemm WrW: **test tolerance fixed** (rocm-libraries 0005); bnorm FP32 open: backward spatial batchnorm precision on wave32, predates rocm-libraries#12889 (also Linux) |
| miopenprovider | ConvolutionFwdPointwise fp32 nchw wrong results | these are grouped convs hitting `ConvHipDirectFwdFused`: **expected fixed by rocm-libraries 0001** (validated on gfx908; not re-run on gfx103X) |
| rocfft (2 shards) | no failures, 60 min timeout | open: V620 speed; tier or timeout change |
| hipsparse 1/3 | `spsv_csr_reuse_descr` f64 intermittent | open |

## What this branch carries

Carried patches (applied by `fetch_sources.py`, `patches/amd-mainline/`). Most come from the gfx9-on-Windows
work, where they were validated on gfx90c and on the gfx1036 (RDNA2 iGPU) control; they are not
gfx9-specific.

| patch | what it fixes | why it matters for gfx10 | origin |
|---|---|---|---|
| rocm-systems 0002 | memory pool VM heap on Windows APUs; failure-path double free (TheRock#7988) | gfx1033/1035/1036 APUs; #7988 everywhere | gfx9-win F9, validated on gfx1036 |
| rocm-systems 0003 | process hangs at exit if GPU work is in flight (Windows ROCr PM4 path) | reproduced on RDNA2 (gfx1036) with the official nightly | gfx9-win F8 |
| rocm-systems 0004 | 64-bit lane masks in HIP headers (LLP64) | `__lastbit_u32_u64` wrong on all Windows targets; wave64 masks | gfx9-win H1 |
| rocm-systems 0005 | device `assert()` prints nothing on Windows | all Windows GPUs | gfx9-win H3 |
| rocm-systems 0006 | same LLP64 bug in hip-tests | test side of 0004 | gfx9-win H2 |
| rocm-systems 0007 | unknown dxg queue errors misread as "insufficient scratch", then access violation | Windows ROCr, any arch | gfx9-win F3 |
| rocm-systems 0008 | every GPU but the first hangs on Windows ROCr (iGPU + dGPU) | Ryzen gfx1036 iGPU next to any dGPU; exposed by the wkmi update that enumerates gfx103X APUs | gfx9-win F11; **local only, not for upstream** (multi-GPU is owned elsewhere) |
| rocm-libraries 0001 | MIOpen fused direct conv computes grouped convs as ungrouped | all GPUs this solver runs on | gfx9-win L5 |
| rocm-libraries 0002 | MIOpen MultiMarginLoss `long` vs `int64_t` (LLP64) | matches the gfx1030 Windows MultiMarginLoss CI failures (fixed the same failure on gfx1036) | gfx9-win L4 |
| rocm-libraries 0003 | MIOpen gtests throw `unknown_gpu` on uncharacterized archs | gfx1036 and other gfx10 iGPUs | gfx9-win L2 |
| rocm-systems 0009 | since rocm-systems#11344 (`f36603ec78`, 2026-10-09) the dxg PM4 path waits for a packet index instead of the submission fence on adapters without platform atomics; every signal after a merged run stalls 30 s and reports an aperture violation | gfx1036 iGPU: `Unit_hipStreamCreateWithPriority*` 0/7 -> 11/13 (as PAL and pre-regression); still on rocm-systems `develop` | new, bisected over 193 commits on gfx1036 |
| rocm-systems 0010 | `hipMemGetAccess` fails on pool allocations made without the VM heap (APUs after 0002, IPC pools) | fixes the 0002 regression found in the full run | new |
| rocm-systems 0011 | since rocm-systems#11344 the dxg PM4 path polls the fence with a 50 ms sleep; tests with many small submissions run hundreds of times slower | gfx1036: two hip-tests from >600 s to ~1 s / 16 s | new |
| rocm-libraries 0004 | hipBLASLt silently returns nullptr when a Tensile library fails to load | turns the gfx1030 "Could not load TensileLibrary" failures into a stated cause | community: rocm-libraries#9219 (GrecAndrei, closed unmerged) |
| rocm-libraries 0005 | MIOpen ImplicitGemm V4R1/V4R4 WrW tests use FLT_EPSILON on gfx103X; only gfx908/gfx90a get the relaxed tolerance | measured on gfx1036: 30x and 1.3x, within the existing 40x / 2x | new |
| llvm-project 0001 | device-libs dot builtins on targets without dot instructions; fdot2 regression | **gfx1010 fdot2 regression; gfx1013 missing from the software lists** | gfx9-win C1 |
| llvm-project 0002 | `llvm.trap` runs off when no trap handler is installed | the gfx1030 V620 ROCr log shows "SetTrapHandler rejected by KMD" | gfx9-win C2 |

TheRock CI changes (on the branch directly):

- hipBLASLt / hipBLASLt provider test jobs skipped on Windows `gfx101X-dgpu` and `gfx103X-all` (from gfx9-win T1).
  Windows families have no `fetch-gfx-targets`, so per-target excludes such as `"gfx1030"` never match on
  Windows; family strings are used instead.
- Test executables outside `bin\` load TheRock's runtime instead of the display driver's System32
  `amdhip64_7.dll` (gfx9-win T2, TheRock#7132).
- `Unit_hipStreamValue_Wait_Blocking` excluded on Windows `gfx103X-all`, as for gfx110X.

Opt-in prototypes (`patches/gfx10-win-experimental/`, not applied automatically; see the README there):
CPU-side stream wait on PM4-emulated queues (the real fix for the Wait_Blocking hang) and CU masks on
PM4 queues.

Deliberately not carried from gfx9-win: the gfx9-only fixes (wkmi family table, dxg user queue, ACQUIRE_MEM,
CLR XNACK table, MIOpen legacy CK, rocPRIM gfx90X) and the PAL to ROCr fallback (PAL drives gfx10).

## Community survey (2026-10-14)

Almost no community gfx10-on-Windows work is a ROCm source patch. It is per-arch kernel packs, app-level
workarounds and packaging. What it tells us:

- **`HSA_OVERRIDE_GFX_VERSION` does nothing on Windows by default.** CLR uses PAL unless `GPU_ENABLE_PAL=0`, and
  only ROCr's dxg thunk reads the override. The RX 6000 projects (sebastianmechno-sys/vllm-rocm-windows-rdna2,
  TheRock#7480/#7341) claim gfx1030/1032 work through it; their own issues #2 and #7 show "Cannot read
  TensileLibrary.dat for gfx1030". Official packages must ship exact code objects per target (TheRock already
  builds gfx1030-1036 separately).
- **Library coverage packs** (likelovewant/ROCmLibs-for-gfx1103-AMD780M-APU, brknsoul/ROCmLibs, koboldcpp-rocm,
  ollama-for-amd) fill gaps of the classic HIP SDK that TheRock's per-target builds already cover for gfx103X.
  The Tensile fallback-arch patch they carried is already upstream.
- **Framework gaps:** PyTorch TunableOp and `torch._int_mm` call hipBLASLt on archs without it (TheRock#8782);
  no SDPA kernels (aotriton #1925); vLLM/Triton crash on RDNA2 (#7341).

## Roadmap (not yet on the branch)

| # | item | source | target | notes |
|---|---|---|---|---|
| R1 | Reproduce and fix the hip-tests ROCr crash at `__hipRegisterFatBinary` | TheRock#4641, V620 logs | rocm-systems | two-GPU case fixed (0008); found and fixed a PM4 fence regression on the way (0009); V620 single-adapter crash still needs V620 logs |
| R2 | hipBLASLt for gfx103X: add gfx1031-1036 to the tensilelite `Processor` enum and supported architectures, then drop the exclude | rocm-libraries#9075, #9076 | rocm-libraries, TheRock | **ported** (6 patches incl. fp32/fp64 bring-up logic from upstream gfx1103 non-matrix files); builds on Linux for gfx1030/1031; held off the branch until run on hardware; fp16/bf16/int8 have no kernels |
| R3 | Gate PyTorch TunableOp / `_int_mm` hipBLASLt use on supported archs, rocBLAS int8 fallback | TheRock#8782; vallicgrr/rx6800-comfyui | ROCm/pytorch | |
| R4 | rocBLAS `asm_full` logic for gfx101X | jc1122/rocblas-gfx1010 (no license), likelovewant (GPL-3.0) | rocm-libraries | **cannot copy either: license**; regenerate (navi21-derived, drop I8) and validate |
| R5 | CK on RDNA1: `__gfx101__` buffer resource dword, FMAC-only | jc1122/pytorch-gfx1010 (no license) | rocm-libraries | reimplement; CK is excluded on gfx10 anyway |
| R6 | rocBLAS GEMM invalid launch grid (M about 12M, N=1, K=8) on gfx1030 | vallicgrr lab report | rocm-libraries | reproduce first |
| R7 | rocPRIM select/unique/scan reported broken on gfx1010 | jc1122/pytorch-gfx1010 | rocm-libraries | unverified; no gfx101X runner |
| R8 | MIOpen bnorm FP32 regression on gfx103X | rockrel logs, gfx1036 repro | rocm-libraries | ImplicitGemm (0005) and #12990 (0001) addressed; bnorm needs an MIOpen rebuild to work on |
| R9 | Windows test runner for gfx101X; re-enable gfx103X runners with this branch's exclusions | therock-ci-config | infra | |
| R10 | SDPA for gfx10 | aotriton #1925; 2kiss/flash-attention-rdna2 (Apache-2.0) | aotriton / pytorch | evaluate |
| R11 | `SUPPORTED_GPUS.md` / `windows_support.md` accuracy (Release Ready vs test evidence; ROCr marked unsupported) | this survey | TheRock docs | |

## Validation status

- All carried patches and the opt-in prototypes apply with plain `git am` at the pins of TheRock `248a92b`
  (rocm-systems `b2d4b1ec26`, rocm-libraries `3dc098eb2d`, amd-llvm `bdc35841c9`).
- The patches inherited from gfx9-win were validated on gfx90c and gfx1036 at earlier pins (see the gfx9-win
  branch, `docs/gfx9-windows/CATALOG.md`). Not yet rebuilt at these pins as a whole.
- 2026-10-15: the rocm-systems carry (0001-0008) plus 0009 was built at the `b2d4b1ec26` pin and run on the gfx1036 iGPU and gfx1201 dGPU (ROCr): hip-tests discovery OK on every device combination, StreamCreateWithPriority 11/13 (matches PAL). Full hip-tests: see below.
- 2026-10-16, full hip-tests on the gfx1036 iGPU (official 10.2.0a20261014 test tarball, 4119 tests, CI settings,
  only gfx1036 visible). Per-test results in `results/`.

  | runtime | pass | fail | timeout | crash | time |
  |---|---|---|---|---|---|
  | this branch (rocm-systems 0001-0009), ROCr | 2606 | 27 | 2 | 1 | ~4.5 h |
  | official nightly, ROCr | 2327 | 253 | 34 | 22 | ~10.5 h |
  | official nightly, PAL (CI configuration) | 3210 | 19 | 0 | 0 | 21 min |

  - 287 tests fixed by this branch (`results/fixed_by_gfx10win.txt`); 286 are the 30 s stall from
    rocm-systems `f36603ec78`, fixed by rocm-systems 0009.
  - Regression from rocm-systems 0002: `Contract_MemLocationPool_HipMemGetAccess_Default` (hipMemGetAccess on a
    pooled allocation fails with the VM heap off). **Fixed by rocm-systems 0010** (mempool/access subset 98/99 -> 99/99 on gfx1036, 99/99 on gfx1201).
  - `Unit_hipGraph_BasicFunctional`, `Unit_hipMultiStream_multimeDevice` hang on ROCr in both runtimes since
    `f36603ec78`, even with 0009. Not a hang: #11344 replaced the blocking fence wait with a 50 ms sleep poll, so every
    CPU-completed signal costs up to 50 ms. **Fixed by rocm-systems 0011** (KMD-signalled event wait with the same
    fault timeout): BasicFunctional >600 s -> 0.97 s, multimeDevice >600 s -> 16 s; 1046 stream/graph/mempool/event
    tests on the fixed build show no regressions vs the full run.
  - Box-build artifacts, not patches: 4 printf tests (fail on any runtime built on the test box), 3
    `hipEnvGpuEnablePal` tests (box build has no PAL).
  - 19 test-side failures in all three configurations (`results/common_failures.txt`): grid dimension 0 in
    tiled-partition/warp tests, too few CUs for execution-context tests.
- Hardware we have: gfx1036 iGPU + gfx1201 dGPU on 10.6.177.171 (Windows 11). No discrete RDNA2 or any RDNA1.
