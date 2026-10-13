# gfx9 on Windows: experimental (opt-in) patches

These are NOT applied by `fetch_sources.py`, which only applies `patches/amd-mainline/`. They are
prototypes kept with the branch so nothing lives only on a test box. See
`docs/gfx9-windows/CATALOG.md` section 3 for what each one does and how it was validated.

Apply them on top of the `amd-mainline` carry (after `fetch_sources.py`), in order:

```bash
git -C rocm-systems am "$PWD"/patches/gfx9-win-experimental/rocm-systems/*.patch
```

| patch | env / scope | status |
|---|---|---|
| `0001-clr-pm4-host-stream-wait.patch` | on by default for PM4-emulated queues; `GPU_STREAMOPS_HOST_WAIT=0` disables | validated at the current pin (WaitValue_Default 2/2, 22/22 stream-value tests) |
| `0002-dxg-gfx9-isolate-internal-queue-on-compute1.patch` | gfx9 without HWS; skipped under `ROCR_USE_PM4=1` | validated at the current pin (4 async mempool tests: crash -> pass) |
| `0003-dxg-pm4-honor-cu-mask.patch` | emulated queues | validated at the current pin (CU mask probe 8/8/8 -> 8/1/2) |
| `0004-dxg-gfx9-trap-handler.patch` | `DXG_TRAP=1`, gfx9 | builds and runs clean at the current pin; KMD 2319 refuses the escape, so the handler stays unbound |

Details: `docs/gfx9-windows/CATALOG.md` section 1b. The trap handler source and probe are in
`docs/gfx9-windows/trap-prototype/`.
