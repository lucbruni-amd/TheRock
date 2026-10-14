# gfx10 on Windows: experimental (opt-in) patches

Not applied by `fetch_sources.py`, which only applies `patches/amd-mainline/`. Apply them on top of the
carry after `fetch_sources.py`:

```bash
git -C rocm-systems am "$PWD"/patches/gfx10-win-experimental/rocm-systems/*.patch
```

| patch | scope | status |
|---|---|---|
| `0001-clr-pm4-host-stream-wait.patch` | `hipStreamWaitValue*` on host memory on PM4-emulated queues waits on the CPU instead of in a GPU spin kernel; `GPU_STREAMOPS_HOST_WAIT=0` disables | validated on gfx90c (gfx9-win); the gfx103X Windows `Wait_Blocking` hang has the same cause; not yet run on gfx10 |
| `0002-dxg-pm4-honor-cu-mask.patch` | CU masks were silently ignored on PM4-emulated queues | validated on gfx90c (gfx9-win); not yet run on gfx10 |

Both come from the gfx9-win branch (`patches/gfx9-win-experimental/`), re-exported at this branch's pins.
