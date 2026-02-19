    .section .text
    .globl _start

/* ------------------------------------------------------------
 * RISC-V (subset & commented) sorting program for verification
 *
 * Please note that the original .s is generated in the
 * python script, this is just a documentation of the generated assembly code.
 * (We don't write it locally as it might exceed the file size limit in github! Also, most
 * of the code is just repeated compare-swap blocks anyways).
 *
 * Memory convention used by the testbench:
 *   - Data RAM is mapped so address 0x00000000 is DRAM[0].
 *   - The Python host writes 32 signed integers to:
 *         0x00, 0x04, 0x08, ... , 0x7C   (32 words, since BRAM requires 4-byte aligned accesses).
 *   - Program sorts these 32 integers in-place (same addresses).
 *   - Completion flag ("magic value") is written to:
 *         0x100 (byte address) = DRAM[0x100/4] = DRAM[64]
 *     Python polls this address until it gets 0xDEADBEAF.
 * ------------------------------------------------------------ */

_start:
    /* Compare-swap for j=0 (first adjacent pair)
     * a = mem[0], b = mem[4]
     * if (b < a), swap
     */
    lw   x7, 0(x0)          /* x7 = A[0]  (load word at 0x00) */
    lw   x8, 4(x0)          /* x8 = A[1]  (load word at 0x04) */
    slt  x9, x8, x7         /* x9 = (A[1] < A[0]) ? 1 : 0 (ternary op) */
    beq  x9, x0, noswap_0   /* if x9==0 => no swap, skips stores */
    sw   x8, 0(x0)          /* A[0] = old A[1] address */
    sw   x7, 4(x0)          /* A[1] = old A[0] address */
noswap_0:

    /* Compare-swap for j=1
     * a = mem[4], b = mem[8]
     * if (b < a) swap
     */
    lw   x7, 4(x0)          /* x7 = A[1] */
    lw   x8, 8(x0)          /* x8 = A[2] */
    slt  x9, x8, x7         /* x9 = (A[2] < A[1]) */
    beq  x9, x0, noswap_1
    sw   x8, 4(x0)          /* A[1] = A[2] */
    sw   x7, 8(x0)          /* A[2] = A[1] */
noswap_1:

    /* compare-swap blocks repeated...
     * generator produces bubble-sort passes:
     *   pass p=0: j = 0..30
     *   pass p=1: j = 0..29
     *   ...
     *   pass p=30: j = 0..0
     *
     * This is bubble sort unrolled into
     * many adjacent compare-swap steps.
     */

    /* ============================================================
     * Explanation of DONE FLAG / MAGIC VALUE write
     * ============================================================
     *
     * Write 0xDEADBEAF into DRAM at byte address 0x100.
     * The Python host polls DRAM[0x100] until it sees 0xDEADBEAF.
     *
     * We can’t do `addi x12, x0, 0xDEADBEAF` because it doesn’t fit
     * in a 12-bit immediate. So we build with LUI + ADDI:
     *
     *   lui  x12, 0xDEADC        -> x12 = 0xDEADC000
     *   addi x12, x12, -337      -> x12 = 0xDEADC000 - 0x151 (337 in decimal)
     *                                = 0xDEADBEAF
     *
     * Then store it:
     *   sw x12, 256(x0)          -> mem[0x100] = 0xDEADBEAF
     */

    lui  x12, 0xDEADC        /* x12 = 0xDEADC000 (upper 20 bits) */
    addi x12, x12, -337      /* x12 = 0xDEADBEAF (finish constant) */
    sw   x12, 256(x0)        /* DONE_FLAG @ address 0x100 */

halt:
    beq  x0, x0, halt        /* infinite loop: core stays “done” */
