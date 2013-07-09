CoffeeBoy
==========

A Game Boy emulator written in CoffeeScript.

CoffeeBoy currently includes a complete disassembler and a mostly complete, very accurate, CPU core. Interrupts, timers, and most hardware is yet to be implemented with the exception of basic graphics.

With CoffeeScript installed, run ```cake build``` to see available tasks.

### Blargg's CPU instructions test ROM

Blargg's test ROMs are a good indicator of an emulator's accuracy [with most emulators failing some tests.](http://gbdev.gg8.se/wiki/articles/Test_ROMs) CoffeeBoy's CPU core already performs better than a large percentage of emulators.

```
Passed: 01-special
Failed: 02-interrupts
Passed: 03-op sp,hl
Passed: 04-op r,imm
Passed: 05-op rp
Passed: 06-ld r,r
Failed: 07-jr,jp,call,ret,rst
Passed: 08-misc instrs
Passed: 09-op r,r
Passed: 10-bit ops
Passed: 11-op a,(hl)
```
