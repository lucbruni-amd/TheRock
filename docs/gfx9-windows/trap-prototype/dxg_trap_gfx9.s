// gfx9 trap handler for ROCr on the Windows dxg (PM4-emulated queue) path.
// Records the trap in a host-visible mailbox and ends the wave, so the dispatch retires and the
// thunk can report the error after the fence. The mailbox address is stored at handler+0x100 by
// ROCr, so the handler does not depend on how the kernel driver passes TBA/TMA. The wave is ended,
// so its SGPRs can be used as scratch; the ttmps are recorded before anything else touches them.
//
// Mailbox layout: +0x00 trap count; +0x40 + slot * 0x80 (slots 0-3): ttmp0-15, STATUS, TRAPSTS,
// HW_ID, magic 'TRAP'.
  .text
  .globl dxg_trap_handler
dxg_trap_handler:
  s_getpc_b64       s[0:1]
  s_add_u32         s0, s0, 0xfc
  s_addc_u32        s1, s1, 0
  s_load_dwordx2    s[2:3], s[0:1], 0x0 glc
  s_waitcnt         lgkmcnt(0)
  s_mov_b32         s4, 1
  s_atomic_add      s4, s[2:3], 0x0 glc
  s_waitcnt         lgkmcnt(0)
  s_cmp_ge_u32      s4, 4
  s_cbranch_scc1    .done
  s_lshl_b32        s4, s4, 7
  s_add_u32         s4, s4, 0x40
  s_add_u32         s2, s2, s4
  s_addc_u32        s3, s3, 0
  s_store_dwordx4   ttmp[0:3], s[2:3], 0x00 glc
  s_store_dwordx4   ttmp[4:7], s[2:3], 0x10 glc
  s_store_dwordx4   ttmp[8:11], s[2:3], 0x20 glc
  s_store_dwordx4   ttmp[12:15], s[2:3], 0x30 glc
  s_getreg_b32      s4, hwreg(HW_REG_STATUS)
  s_getreg_b32      s5, hwreg(HW_REG_TRAPSTS)
  s_getreg_b32      s6, hwreg(HW_REG_HW_ID)
  s_mov_b32         s7, 0x50415254
  s_store_dwordx4   s[4:7], s[2:3], 0x40 glc
.done:
  s_dcache_wb
  s_waitcnt         lgkmcnt(0)
  s_endpgm
