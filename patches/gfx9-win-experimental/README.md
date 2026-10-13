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
| `0001-clr-pm4-host-stream-wait.patch` | on by default for PM4-emulated queues; `GPU_STREAMOPS_HOST_WAIT=0` disables | validated at the 7.15 pin; rebased, compiles on Linux |
| `0002-dxg-gfx9-isolate-internal-queue-on-compute1.patch` | gfx9 without HWS | validated at the 7.15 pin; rebased (also skipped under `ROCR_USE_PM4=1`), dxg part not rebuilt |
| `0003-dxg-pm4-honor-cu-mask.patch` | emulated queues | validated at the 7.15 pin; rebased, not rebuilt |
| `0004-dxg-gfx9-trap-handler.patch` | `DXG_TRAP=1`, gfx9 | built at the 7.15 pin; legacy KMD refuses the escape; rebased, ROCr part compiles on Linux, dxg part not rebuilt |

The dxg thunk only builds for Windows (or WSL with the DirectX headers), so the dxg parts of 0002 to
0004 have not been compiled since the rebase. Rebuild and rerun the catalog's checks on a Windows gfx9
box before relying on them. The trap handler source and probe are in `docs/gfx9-windows/trap-prototype/`.
