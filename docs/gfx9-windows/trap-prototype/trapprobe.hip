// Device-trap probe for the dxg trap-handler prototype: trapprobe <mode>
//   ok      plain kernel (no trap), must pass in every configuration
//   asm     s_trap 2 followed by s_endpgm: ends cleanly even if the trap is ignored
//   builtin __builtin_trap() (s_trap 2 is the kernel's last instruction)
//   assert  device assert(false)
// Every wave stores 1 before the trap and 2 after it, so the output shows how far waves got.
#undef NDEBUG
#include <hip/hip_runtime.h>
#include <cassert>
#include <cstdio>
#include <cstring>

__global__ void k_ok(int* p) { p[threadIdx.x] = 2; }
__global__ void k_asm(int* p) {
  p[threadIdx.x] = 1;
  __asm__ volatile("s_trap 2\n\ts_endpgm" ::: "memory");
  p[threadIdx.x] = 2;
}
__global__ void k_builtin(int* p) {
  p[threadIdx.x] = 1;
  if (p[64] == 0) __builtin_trap();
  p[threadIdx.x] = 2;
}
__global__ void k_assert(int* p) {
  p[threadIdx.x] = 1;
  assert(p[64] != 0);
  p[threadIdx.x] = 2;
}

int main(int argc, char** argv) {
  const char* mode = argc > 1 ? argv[1] : "ok";
  int* d = nullptr;
  if (hipMalloc(&d, 65 * sizeof(int)) != hipSuccess) { printf("hipMalloc failed\n"); return 2; }
  hipMemset(d, 0, 65 * sizeof(int));
  hipDeviceSynchronize();
  if (!strcmp(mode, "asm")) hipLaunchKernelGGL(k_asm, dim3(1), dim3(64), 0, 0, d);
  else if (!strcmp(mode, "builtin")) hipLaunchKernelGGL(k_builtin, dim3(1), dim3(64), 0, 0, d);
  else if (!strcmp(mode, "assert")) hipLaunchKernelGGL(k_assert, dim3(1), dim3(64), 0, 0, d);
  else hipLaunchKernelGGL(k_ok, dim3(1), dim3(64), 0, 0, d);
  printf("launch: %s\n", hipGetErrorString(hipGetLastError()));
  fflush(stdout);
  hipError_t e = hipDeviceSynchronize();
  int h[64] = {0};
  hipError_t e2 = hipMemcpy(h, d, sizeof(h), hipMemcpyDeviceToHost);
  int ones = 0, twos = 0;
  for (int v : h) { ones += (v == 1); twos += (v == 2); }
  printf("mode=%s sync=%s memcpy=%s  lanes at 1 (stopped)=%d  at 2 (ran past)=%d\n", mode,
         hipGetErrorString(e), hipGetErrorString(e2), ones, twos);
  return e == hipSuccess ? 0 : 1;
}
