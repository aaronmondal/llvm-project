// REQUIRES: aarch64
// RUN: llvm-mc -filetype=obj -triple=aarch64 %s -o %t.o
// RUN: echo "SECTIONS { \
// RUN:          .text : { *(.text) *(.text.*) *(.newisd) } \
// RUN:          .text2 : { *.(newos) } \
// RUN:          .data : { *(.data) } }" > %t.script
// RUN: ld.lld --script %t.script -fix-cortex-a53-843419 -verbose %t.o -o %t2 2>&1 \
// RUN:   | FileCheck -check-prefix=CHECK-PRINT %s
// RUN: llvm-objdump --no-print-imm-hex --triple=aarch64-linux-gnu -d %t2 | FileCheck %s

// Test cases for Cortex-A53 Erratum 843419 that involve interactions
// between the generated patches and the address of sections.

// See ARM-EPM-048406 Cortex_A53_MPCore_Software_Developers_Errata_Notice.pdf
// for full erratum details.
// In Summary
// 1.)
// ADRP (0xff8 or 0xffc).
// 2.)
// - load or store single register or either integer or vector registers.
// - STP or STNP of either vector or vector registers.
// - Advanced SIMD ST1 store instruction.
// - Must not write Rn.
// 3.) optional instruction, can't be a branch, must not write Rn, may read Rn.
// 4.) A load or store instruction from the Load/Store register unsigned
// immediate class using Rn as the base register.

// An aarch64 section can contain ranges of literal data embedded within the
// code, these ranges are encoded with mapping symbols. This tests that we
// can match the erratum sequence in code, but not data.
// - We can handle more than one patch per code range (denoted by mapping
//   symbols).
// - We can handle a patch in more than range of code, with literal data
//   inbetween.
// - We can handle redundant mapping symbols (two or more consecutive mapping
//   symbols with the same type).
// - We can ignore erratum sequences in multiple literal data ranges.

// CHECK-PRINT: detected cortex-a53-843419 erratum sequence starting at FF8 in unpatched output.
// CHECK: <t3_ff8_ldr>:
// CHECK-NEXT:      ff8:        d0000020        adrp    x0, 0x6000
// CHECK-NEXT:      ffc:        f9400021        ldr             x1, [x1]
// CHECK-NEXT:     1000:        14000ff9        b       0x4fe4
// CHECK-NEXT:     1004:        d65f03c0        ret
        .section .text.01, "ax", %progbits
        .balign 4096
        .space 4096 - 8
        .globl t3_ff8_ldr
        .type t3_ff8_ldr, %function
t3_ff8_ldr:
        adrp x0, dat
        ldr x1, [x1, #0]
        ldr x0, [x0, :got_lo12:dat]
        ret

        // create a redundant mapping symbol as we are already in a $x range
        // some object producers unconditionally generate a mapping symbol on
        // every symbol so we need to handle the case of $x $x.
        .local $x.999
$x.999:
// CHECK-PRINT-NEXT: detected cortex-a53-843419 erratum sequence starting at 1FFC in unpatched output.
// CHECK: <t3_ffc_ldrsimd>:
// CHECK-NEXT:     1ffc:        b0000020        adrp    x0, 0x6000
// CHECK-NEXT:     2000:        bd400021        ldr             s1, [x1]
// CHECK-NEXT:     2004:        14000bfa        b       0x4fec
// CHECK-NEXT:     2008:        d65f03c0        ret
        .globl t3_ffc_ldrsimd
        .type t3_ffc_ldrsimd, %function
        .space 4096 - 12
t3_ffc_ldrsimd:
        adrp x0, dat
        ldr s1, [x1, #0]
        ldr x2, [x0, :got_lo12:dat]
        ret

// Inline data containing bit pattern of erratum sequence, expect no patch.
        .globl t3_ffc_ldralldata
        .type t3_ff8_ldralldata, %function
        .space 4096 - 20
t3_ff8_ldralldata:
        // 0x90000000 = adrp x0, #0
        .byte 0x00
        .byte 0x00
        .byte 0x00
        .byte 0x90
        // 0xf9400021 = ldr x1, [x1]
        .byte 0x21
        .byte 0x00
        .byte 0x40
        .byte 0xf9
        // 0xf9400000 = ldr x0, [x0]
        .byte 0x00
        .byte 0x00
        .byte 0x40
        .byte 0xf9
        // Check that we can recognise the erratum sequence post literal data.

// CHECK-PRINT-NEXT: detected cortex-a53-843419 erratum sequence starting at 3FF8 in unpatched output.
// CHECK: <t3_ffc_ldr>:
// CHECK-NEXT:     3ff8:        f0000000        adrp    x0, 0x6000
// CHECK-NEXT:     3ffc:        f9400021        ldr             x1, [x1]
// CHECK-NEXT:     4000:        140003fd        b       0x4ff4
// CHECK-NEXT:     4004:        d65f03c0        ret
        .space 4096 - 12
        .globl t3_ffc_ldr
        .type t3_ffc_ldr, %function
 t3_ffc_ldr:
        adrp x0, dat
        ldr x1, [x1, #0]
        ldr x0, [x0, :got_lo12:dat]
        ret

// CHECK: <__CortexA53843419_1000>:
// CHECK-NEXT:     4fe4:        f9400c00        ldr     x0, [x0, #24]
// CHECK-NEXT:     4fe8:        17fff007        b       0x1004
// CHECK: <__CortexA53843419_2004>:
// CHECK-NEXT:     4fec:        f9400c02        ldr     x2, [x0, #24]
// CHECK-NEXT:     4ff0:        17fff406        b       0x2008
// CHECK: <__CortexA53843419_4000>:
// CHECK-NEXT:     4ff4:        f9400c00        ldr     x0, [x0, #24]
// CHECK-NEXT:     4ff8:        17fffc03        b       0x4004

        .section .text.02, "ax", %progbits
        .space 4096 - 36

        // Start a new InputSectionDescription (see Linker Script) so the
        // start address will be affected by any patches added to previous
        // InputSectionDescription.

// CHECK-PRINT-NEXT: detected cortex-a53-843419 erratum sequence starting at 4FFC in unpatched output
// CHECK: <t3_ffc_str>:
// CHECK-NEXT:     4ffc:        d0000000        adrp    x0, 0x6000
// CHECK-NEXT:     5000:        f9000021        str             x1, [x1]
// CHECK-NEXT:     5004:        140003fb        b       0x5ff0
// CHECK-NEXT:     5008:        d65f03c0        ret

        .section .newisd, "ax", %progbits
        .globl t3_ffc_str
        .type t3_ffc_str, %function
t3_ffc_str:
        adrp x0, dat
        str x1, [x1, #0]
        ldr x0, [x0, :got_lo12:dat]
        ret
        .space 4096 - 28

// CHECK: <__CortexA53843419_5004>:
// CHECK-NEXT:     5ff0:        f9400c00        ldr     x0, [x0, #24]
// CHECK-NEXT:     5ff4:        17fffc05        b       0x5008

        // Start a new OutputSection (see Linker Script) so the
        // start address will be affected by any patches added to previous
        // InputSectionDescription.

//CHECK-PRINT-NEXT: detected cortex-a53-843419 erratum sequence starting at 5FF8 in unpatched output
// CHECK: <t3_ff8_str>:
// CHECK-NEXT:     5ff8:        b0000000        adrp    x0, 0x6000
// CHECK-NEXT:     5ffc:        f9000021        str             x1, [x1]
// CHECK-NEXT:     6000:        14000003        b       0x600c
// CHECK-NEXT:     6004:        d65f03c0        ret

        .section .newos, "ax", %progbits
        .globl t3_ff8_str
        .type t3_ff8_str, %function
t3_ff8_str:
        adrp x0, dat
        str x1, [x1, #0]
        ldr x0, [x0, :got_lo12:dat]
        ret
        .globl _start
        .type _start, %function
_start:
        ret

// CHECK: <__CortexA53843419_6000>:
// CHECK-NEXT:     600c:        f9400c00        ldr     x0, [x0, #24]
// CHECK-NEXT:     6010:        17fffffd        b       0x6004

        .data
        .globl dat
dat:    .word 0
