# Cross-arch comparison (prefix Unit_)

## Per-arch coverage and pass rate

| arch | tests run | pass | fail | skip/notrun | pass-rate (of run-non-skip) |
|---|---|---|---|---|---|
| gfx90c-win-ourfixes | 2939 | 2576 | 30 | 333 | 98.8% |
| gfx1101-win-nightly | 3482 | 2110 | 0 | 1372 | 100.0% |
| gfx120X-win-nightly | 3484 | 2121 | 0 | 1363 | 100.0% |
| gfx906-linux | 4199 | 3962 | 9 | 228 | 99.8% |

## Deltas vs baseline `gfx1101-win-nightly` (shared test names)

### gfx90c-win-ourfixes vs gfx1101-win-nightly
- shared tests: 2871; only in gfx1101-win-nightly: 611; only in gfx90c-win-ourfixes: 68
- FAIL on gfx90c-win-ourfixes but PASS on gfx1101-win-nightly: 27
  - Unit_Rtc_MathFunctions_header
  - Unit_Rtc_ReduceRandom
  - Unit_Rtc_fp16_header
  - Unit_hipEnvGpuEnablePal_Default_UsesPlatformDefault
  - Unit_hipEnvGpuEnablePal_EmptyString_UsesPlatformDefault
  - Unit_hipEnvGpuEnablePal_ExplicitValues_WorkCorrectly
  - Unit_hipMemcpyBatchAsync_D2H_Functional
  - Unit_hipMemcpyBatchAsync_H2D_Functional
  - Unit_hipMemcpyBatchAsync_H2D_Pageable_Stream_SourceAccess
  - Unit_hipMemcpyDeviceToDeviceNoCU_NoCU_MulStrm
  - Unit_hipReduceMultipleMasks - double
  - Unit_hipReduceMultipleMasks - float
  - Unit_hipReduceMultipleMasks - half
  - Unit_hipReduceMultipleMasks - int
  - Unit_hipReduceMultipleMasks - long long
  - Unit_hipReduceMultipleMasks - unsigned int
  - Unit_hipReduceMultipleMasks - unsigned long long
  - Unit_hipReduceRandom
  - Unit_hipReduceSingleMasks - half
  - Unit_hipReduceSingleMasks - int
  - Unit_hipReduceSingleMasks - long long
  - Unit_hipReduceSingleMasks - unsigned int
  - Unit_hipReduceSingleMasks - unsigned long long
  - Unit_hipStreamWaitValue_Default - uint32_t
  - Unit_hipStreamWaitValue_Default - uint64_t
  - Unit_hipTestNativeHalf
  - Unit_hiprtc_stdheaders

### gfx120X-win-nightly vs gfx1101-win-nightly
- shared tests: 3482; only in gfx1101-win-nightly: 0; only in gfx120X-win-nightly: 2
- FAIL on gfx120X-win-nightly but PASS on gfx1101-win-nightly: 0

### gfx906-linux vs gfx1101-win-nightly
- shared tests: 3013; only in gfx1101-win-nightly: 469; only in gfx906-linux: 1186
- FAIL on gfx906-linux but PASS on gfx1101-win-nightly: 3
  - Unit_hipExtModuleLaunchKernel_UniformWorkGroup
  - Unit_hipModuleLoadData_Positive_Basic
  - Unit_hipModuleLoadFatBinary_PosiiveTsts


## Interpretation (2026-10-09)

Sources: gfx90c-win = our-fixes build run A7 (hip-tests catch, our exclusions); gfx1101/gfx120X-win
= TheRock nightly CI (`azure-windows-11-gfx1101/gfx120X` runners, known-good references); gfx906-linux
= our self-built run A906. `Unit_` prefix = the hip-tests catch suite (apples-to-apples core).

### Tests passing
- gfx90c 98.8% (30 fail), gfx11-nightly 100% (0 fail), gfx906 99.8% (9 fail).
- All 30 gfx90c failures are either our-fix-targeted (device-libs dots, LLP64 ReduceMasks,
  StreamWaitValue, NoCU_MulStrm, BatchAsync = section 2c) or the 3 `Unit_hipEnvGpuEnablePal_*`
  tests. The latter are directly about GPU_ENABLE_PAL handling and A7 predates fix 10; they are the
  one new, fix-10-relevant item to re-test with the fix-10 runtime.

### Compute coverage (tests actually run)
- gfx906-linux 4199 > gfx11-win-nightly 3482 > gfx90c-win 2939. gfx90c runs ~543-611 fewer `Unit_`
  tests than the gfx11 Windows nightly.
- The 611 tests gfx11 runs but gfx90c does not, by family: Thread 105, Coalesced 47, Warp 20,
  hipStreamBeginCapture 17, coop 16, hipDeviceFlushGPUDirectRDMAWrites 14, hipMemSetAccess 13,
  hipMemcpyBatchAsync 13, hipGraphExecUpdate 12, deviceAllocation 9, hipMemcpy2D 9, hipMemMap 7, ...
- Split: feature-gated-on-APU (GPUDirect RDMA, clusters, managed memory, some cooperative/graph) are
  legitimate skips; the generic Thread/Coalesced/Warp families should run on gfx90c and are a real
  coverage gap, most likely from our harness exclusions / `THEROCK_REQUIRE_HIP_YAML_ENTRIES` gating,
  not a gfx9 limitation.

### Next actions from this comparison
1. Re-run the 3 `Unit_hipEnvGpuEnablePal_*` tests on the fix-10 runtime (expect PASS; closes the only
   non-catalogued gfx90c-vs-gfx11 failure delta).
2. Re-run gfx90c hip-tests with the nightly's full test selection (drop our extra exclusions) to pull
   in Thread/Coalesced/Warp and close the generic coverage gap; re-diff.
3. Add the component/library level (rocBLAS, rocPRIM, MIOpen, ...): diff gfx90c complogs vs the gfx11
   nightly component ctest counts, the "our libraries" coverage+pass comparison.

## Resolution of the 3 `hipEnvGpuEnablePal` failures (2026-10-09)

Re-tested `EnvironmentTest.exe "Unit_hipEnvGpuEnablePal*"` before/after the fix-10 runtime on gfx90c:
- before fix 10: 3/3 fail, 11/14 assertions.
- after fix 10: 3/3 fail, 13/16 assertions (fix 10 lets more of each test run; the device is now found).

Root cause (from the after log): the tests `REQUIRE( palInitialized == true )`
(`hipEnvGpuEnablePal.cc:63/102/...`), i.e. they assert the Windows platform default backend is PAL.
With fix 10 the gfx90c device IS enumerated ("Gfx Major/Minor/Stepping: 9/0/12",
`hipGetDeviceCount: Returned hipSuccess`), but via ROCr, since PAL has no gfx9. So the failure is a
**test-side PAL-default assumption that does not hold for gfx9**, not a runtime defect: fix 10 is
working (GPU usable via ROCr). On the PAL-on reference (gfx11) PAL initializes, so the test passes.

Options: update the tests to assert "platform default backend is available" (not PAL-specifically) or
skip them on ROCr-only / gfx9 Windows. Candidate test-side fix, sibling to the MIOpen-tests-arch and
hip-tests-warp-reduce-llp64 entries; left uncatalogued pending a decision. NET: the entire
gfx90c-vs-gfx11 `Unit_` failure delta is now fully explained (fix-targeted, section-2c, or this PAL
test assumption); no unexplained gfx9-Windows hip-tests failure remains.

## Coverage-gap root cause (2026-10-09): version skew + feature-gating, not harness exclusions

Checked whether the 611 "gfx11-only" `Unit_` tests exist in our gfx90c catch build:
- `Unit_Thread`: our build has 6 (coopGrpTest 5, UnitDeviceTests 1); the nightly ran 105.
- `Unit_Coalesced`: our build has 12 (all in coopGrpTest); nightly ran 47.
- `Unit_Warp`: our build has 23 (WarpTest); nightly's "Warp" gap was ~20 (near parity here).

So the gap is two things, neither a harness exclusion we can just drop:
1. **Version skew**: our pinned 7.15 hip-tests source is older than the nightly, which has many more
   tests (105 vs 6 Thread). Closing this needs rebuilding the catch suite from the nightly's source pin.
2. **Feature-gating**: the Thread/Coalesced families are cooperative-group tests (`coopGrpTest.exe`);
   cooperative launch needs MES/multi-grid sync the gfx90c legacy driver lacks, so they skip on gfx90c
   even when present. Likewise GPUDirect-RDMA, clusters, managed-memory families are APU/feature skips.

Implication: the trustworthy comparison metric is the **pass rate on the shared tests both arches run**
(gfx90c 98.8% vs gfx11 100%, delta fully explained), not raw test counts. To raise gfx90c's absolute
coverage toward the nightly, rebuild catch at the nightly pin; expect a chunk to still skip (no MES).

## Windows A/B extended with gfx1201 (RX 9070 XT, RDNA4) hip-tests (2026-10-09)

Added the gfx1201-Windows catch suite (53 Catch2 exes, 7627 testcases) as a second Windows arch.

| arch | Unit_ run | pass | fail | skip | pass-rate |
|---|---|---|---|---|---|
| gfx90c-win (our fixes) | 2939 | 2576 | 30 | 333 | 98.8% |
| gfx1201-win | 7621 | 7366 | 21 | 234 | 99.7% |
| gfx1101-win-nightly | 3482 | 2110 | 0 | 1372 | 100% |
| gfx906-linux | 4199 | 3962 | 9 | 228 | 99.8% |

Findings:
- gfx1201-win agrees with the gfx1101 nightly on every shared test (0 fail-on-nightly/pass-on-1201),
  validating gfx1201 as a known-good Windows reference and our harness against it.
- **gfx90c FAIL / gfx1201 PASS = 16**, all explained: our-fix-targeted (Rtc dots, ReduceMasks,
  StreamWaitValue/Wait_Blocking, NoCU_MulStrm, BatchAsync, TestNativeHalf) + the 3
  `hipEnvGpuEnablePal` tests. The latter PASS on gfx1201 precisely because gfx1201 uses PAL as the
  Windows platform default (so `palInitialized == true` holds), whereas gfx9 uses ROCr, this confirms
  those tests encode a PAL-default assumption, not a gfx90c defect.
- gfx1201 runs far more Unit_ tests (7621) than gfx90c (2939): newer dist + RDNA4 supports feature
  families (cooperative/graph/VMM) the gfx90c APU skips. Same coverage-gap root cause as before
  (version + feature-gating), not harness exclusions.
- gfx1201 has 21 of its own Unit_ failures (DeviceTest/EventTest/ExecutionContext/MemoryTest1/
  ModuleTest/StreamTest/UnitDeviceTests), reference-arch-specific, not relevant to the gfx9 work.

Net: the Windows A/B is complete at both the library (rocSOLVER, byte-identical 56,801/48) and
hip-tests level. gfx90c-Windows with our fixes sits at a 98.8% pass rate whose entire gap to the
supported Windows references is explained and fix-attributed.

## gfx1201-Windows own hip-tests failures (21), characterized

The reference arch (gfx1201/RDNA4, build-passing not sanity-tested on Windows) has 21 of its own
Unit_ failures, by family: ExecutionContext/resource-split (6, a newer API family), Stream (6:
CUMask callback, MultiStream, AddCallback, priority, StreamWaitValue_Default-uint32), Memory (4:
Memcpy2D/3D/Param2D D2H, HostRegister), Event (2), DeviceProperties (1), Module (1), mbcnt (1).
These are reference-arch maturity issues, unrelated to the gfx9 work. Cross-cutting note:
`hipStreamWaitValue_Default` fails on gfx1201-Windows as well as gfx90c, so it is a broader Windows
PM4-path issue (addressed by the experimental CPU-side stream-wait fix), not gfx9-specific.
