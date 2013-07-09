class CPU
  REG_PAIRS = ['AF', 'BC', 'DE', 'HL']

  class Regs
    constructor: ->
      Object.defineProperties this, this.properties
      delete this.properties

      # Create a property for each register pair
      for regPair in REG_PAIRS
        [regA, regB] = [regPair[0], regPair[1]]

        do (regA, regB) =>
          property =
            get: -> (@[regA] << 8) + @[regB]
            set: (value) ->
              @[regA] = (value >> 8) & 0xFF
              @[regB] = value & 0xFF

          Object.defineProperty this, regPair, property

    # Registers
    PC: 0, SP: 0
    A: 0, B: 0, C: 0, D: 0, E: 0
    H: 0, L: 0

    flags:
      Z: 0, N: 0, H: 0, C: 0

    properties:
      F:
        get: ->
          flags = 0
          if @flags.Z then flags |= 0x80
          if @flags.N then flags |= 0x40
          if @flags.H then flags |= 0x20
          if @flags.C then flags |= 0x10
          flags

        set: (value) ->
          @flags.Z = (value & 0x80) > 0
          @flags.N = (value & 0x40) > 0
          @flags.H = (value & 0x20) > 0
          @flags.C = (value & 0x10) > 0

  regs:        new Regs()
  memory:      null
  buffer:      null
  breakpoints: null

  constructor: ->
    @reset()

  LoadCode: (buffer) ->
    unless buffer instanceof Uint8Array
      throw 'Input buffer must be of type Uint8Array.'

    @buffer = buffer

    # Kind of map the ROM where it belongs.
    for i in [0...@buffer.byteLength]
      @memory[i] = @buffer[i]

    # @reset()

  reset: ->
    # Reset registers.
    for reg in ['A', 'B', 'C', 'D', 'E', 'H', 'L', 'F', 'PC', 'SP']
      @regs[reg] = 0

    for flag in ['Z', 'N', 'H', 'C']
      @regs.flags[flag] = 0

    @memory = new Array(0xFFFF + 1)

  # Unsigned

  getUint8: ->
    @memory[@regs.PC++]

  getUint16: ->
    @getUint8() + (@getUint8() << 8)

  # Signed

  getInt8: ->
    byte = @getUint8()

    # Two's complement
    sign = (byte >> 7) & 0x1
    if sign
      byte = -((byte ^ 0xFF) + 1)

    byte

  getRelInt8JmpAddress: ->
    # Order matters
    @getInt8() + @regs.PC

  # Opcodes are gathered from:
  #   - http://meatfighter.com/gameboy/GBCPUman.pdf
  #   - http://imrannazar.com/Gameboy-Z80-Opcode-Map
  #   - http://www.scribd.com/doc/39999184/GameBoy-Programming-Manual
  #
  # As conventions:
  #   - 'r' represents a register
  #   - 'n' represents a byte
  #   - 'rr' represents a pair of registers
  #   - 'nn' represents a 16 bit integer
  #   - Uppercase characters denote a pointer

  LD_r_n: (reg) ->
    @regs[reg] = @getUint8()

  LD_R_n: (reg) ->
    @memory[@regs[reg]] = @getUint8()

  LD_r_r2: (reg, reg2) ->
    @regs[reg] = @regs[reg2]

  LD_r_R2: (reg, reg2) ->
    @regs[reg] = @memory[@regs[reg2]]

  LD_R_r2: (reg, reg2) ->
    @memory[@regs[reg]] = @regs[reg2]

  LD_A_r: (reg) ->
    @regs.A = @regs[reg]

  LD_A_R: (reg) ->
    @regs.A = @memory[@regs[reg]]

  LD_A_NN: (reg) ->
    @regs.A = @memory[@getUint16()]

  LD_A_n: ->
    @regs.A = @getUint8()

  LD_r_A: (reg) ->
    @regs[reg] = @regs.A

  LD_R_A: (reg) ->
    @memory[@regs[reg]] = @regs.A

  LD_NN_A: ->
    @memory[@getUint16()] = @regs.A

  LDH_A_C: ->
    @regs.A = @memory[0xFF00 + @regs.C]

  LDH_C_A: ->
    @memory[0xFF00 + @regs.C] = @regs.A

  LDD_A_HL: ->
    @regs.A = @memory[@regs.HL]
    @regs.HL--

  LDD_HL_A: ->
    @memory[@regs.HL] = @regs.A
    @regs.HL--

  LDI_A_HL: ->
    @regs.A = @memory[@regs.HL]
    @regs.HL++

  LDI_HL_A: ->
    @memory[@regs.HL] = @regs.A
    @regs.HL++

  LDH_N_A: ->
    @memory[0xFF00 + @getUint8()] = @regs.A

  LDH_A_N: ->
    @regs.A = @memory[0xFF00 + @getUint8()]

  LD_r_nn: (reg) ->
    @regs[reg] = @getUint16()

  LD_SP_HL: ->
    @regs.SP = @regs.HL

  LDHL_SP_n: ->
    n = @getInt8()

    @regs.flags.Z = 0
    @regs.flags.N = 0
    @regs.flags.H = (((@regs.SP & 0xF)  + (n & 0xF))  & 0x10)  > 0
    @regs.flags.C = (((@regs.SP & 0xFF) + (n & 0xFF)) & 0x100) > 0

    @regs.HL = (@regs.SP + n) & 0xFFFF

  LD_NN_SP: ->
    address = @getUint16()
    @memory[address]     = @regs.SP & 0xFF
    @memory[address + 1] = (@regs.SP >> 8) & 0xFF

  PUSH_r: (reg) ->
    @regs.SP--
    @memory[@regs.SP] = (@regs[reg] >> 8) & 0xFF
    @regs.SP--
    @memory[@regs.SP] = @regs[reg] & 0xFF

  POP_r: (reg) ->
    byte  = @memory[@regs.SP]
    @regs.SP++
    byte2 = @memory[@regs.SP]
    @regs.SP++
    @regs[reg] = byte | (byte2 << 8)

  ADD_A_r: (reg) ->
    n   = @regs[reg]
    sum = (@regs.A + n) & 0xFF

    @regs.flags.Z = sum == 0
    @regs.flags.N = 0
    @regs.flags.H = (((@regs.A & 0xF)  + (n & 0xF))  & 0x10)  > 0
    @regs.flags.C = (((@regs.A & 0xFF) + (n & 0xFF)) & 0x100) > 0

    @regs.A = sum

  ADD_A_R: (reg) ->
    n   = @memory[@regs[reg]]
    sum = (@regs.A + n) & 0xFF

    @regs.flags.Z = sum == 0
    @regs.flags.N = 0
    @regs.flags.H = (((@regs.A & 0xF)  + (n & 0xF))  & 0x10)  > 0
    @regs.flags.C = (((@regs.A & 0xFF) + (n & 0xFF)) & 0x100) > 0

    @regs.A = sum

  ADD_A_n: ->
    n   = @getUint8()
    sum = (@regs.A + n) & 0xFF

    @regs.flags.Z = sum == 0
    @regs.flags.N = 0
    @regs.flags.H = (((@regs.A & 0xF)  + (n & 0xF))  & 0x10)  > 0
    @regs.flags.C = (((@regs.A & 0xFF) + (n & 0xFF)) & 0x100) > 0

    @regs.A = sum

  ADC_A_r: (reg) ->
    n   = @regs[reg]
    sum = (@regs.A + n + @regs.flags.C) & 0xFF

    @regs.flags.Z = sum == 0
    @regs.flags.N = 0
    @regs.flags.H = (((@regs.A & 0xF)  + (n & 0xF)  + @regs.flags.C) & 0x10)  > 0
    @regs.flags.C = (((@regs.A & 0xFF) + (n & 0xFF) + @regs.flags.C) & 0x100) > 0

    @regs.A = sum

  ADC_A_R: (reg) ->
    n   = @memory[@regs[reg]]
    sum = (@regs.A + n + @regs.flags.C) & 0xFF

    @regs.flags.Z = sum == 0
    @regs.flags.N = 0
    @regs.flags.H = (((@regs.A & 0xF)  + (n & 0xF)  + @regs.flags.C) & 0x10)  > 0
    @regs.flags.C = (((@regs.A & 0xFF) + (n & 0xFF) + @regs.flags.C) & 0x100) > 0

    @regs.A = sum

  ADC_A_n: ->
    n   = @getUint8()
    sum = (@regs.A + n + @regs.flags.C) & 0xFF

    @regs.flags.Z = sum == 0
    @regs.flags.N = 0
    @regs.flags.H = (((@regs.A & 0xF)  + (n & 0xF)  + @regs.flags.C) & 0x10)  > 0
    @regs.flags.C = (((@regs.A & 0xFF) + (n & 0xFF) + @regs.flags.C) & 0x100) > 0

    @regs.A = sum

  SUB_r: (reg) ->
    n    = @regs[reg]
    diff = (@regs.A - n) & 0xFF

    @regs.flags.Z = diff == 0
    @regs.flags.N = 1
    @regs.flags.H = (@regs.A & 0xF) < (n & 0xF)
    @regs.flags.C = @regs.A < n

    @regs.A = diff

  SUB_R: (reg) ->
    n    = @memory[@regs[reg]]
    diff = (@regs.A - n) & 0xFF

    @regs.flags.Z = diff == 0
    @regs.flags.N = 1
    @regs.flags.H = (@regs.A & 0xF) < (n & 0xF)
    @regs.flags.C = @regs.A < n

    @regs.A = diff

  SUB_n: ->
    n    = @getUint8()
    diff = (@regs.A - n) & 0xFF

    @regs.flags.Z = diff == 0
    @regs.flags.N = 1
    @regs.flags.H = (@regs.A & 0xF) < (n & 0xF)
    @regs.flags.C = @regs.A < n

    @regs.A = diff

  SBC_A_r: (reg) ->
    n    = @regs[reg]
    diff = (@regs.A - n - @regs.flags.C) & 0xFF

    @regs.flags.Z = diff == 0
    @regs.flags.N = 1
    @regs.flags.H = (@regs.A & 0xF) < (n & 0xF) + @regs.flags.C
    @regs.flags.C = @regs.A < n + @regs.flags.C

    @regs.A = diff

  SBC_A_R: (reg) ->
    n    = @memory[@regs[reg]]
    diff = (@regs.A - n - @regs.flags.C) & 0xFF

    @regs.flags.Z = diff == 0
    @regs.flags.N = 1
    @regs.flags.H = (@regs.A & 0xF) < (n & 0xF) + @regs.flags.C
    @regs.flags.C = @regs.A < n + @regs.flags.C

    @regs.A = diff

  SBC_A_n: ->
    n    = @getUint8()
    diff = (@regs.A - n - @regs.flags.C) & 0xFF

    @regs.flags.Z = diff == 0
    @regs.flags.N = 1
    @regs.flags.H = (@regs.A & 0xF) < (n & 0xF) + @regs.flags.C
    @regs.flags.C = @regs.A < n + @regs.flags.C

    @regs.A = diff

  AND_r: (reg) ->
    @regs.A &= @regs[reg]

    @regs.flags.Z = @regs.A == 0
    @regs.flags.N = 0
    @regs.flags.H = 1
    @regs.flags.C = 0

  AND_R: (reg) ->
    @regs.A &= @memory[@regs[reg]]

    @regs.flags.Z = @regs.A == 0
    @regs.flags.N = 0
    @regs.flags.H = 1
    @regs.flags.C = 0

  AND_n: (reg) ->
    @regs.A &= @getUint8()

    @regs.flags.Z = @regs.A == 0
    @regs.flags.N = 0
    @regs.flags.H = 1
    @regs.flags.C = 0

  OR_r: (reg) ->
    @regs.A |= @regs[reg]

    @regs.flags.Z = @regs.A == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

  OR_R: (reg) ->
    @regs.A |= @memory[@regs[reg]]

    @regs.flags.Z = @regs.A == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

  OR_n: ->
    @regs.A |= @getUint8()

    @regs.flags.Z = @regs.A == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

  XOR_r: (reg) ->
    @regs.A ^= @regs[reg]

    @regs.flags.Z = @regs.A == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

  XOR_R: (reg) ->
    @regs.A ^= @memory[@regs[reg]]

    @regs.flags.Z = @regs.A == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

  XOR_n: ->
    @regs.A ^= @getUint8()

    @regs.flags.Z = @regs.A == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

  CP_r: (reg) ->
    n    = @regs[reg]
    diff = (@regs.A - n) & 0xFF

    @regs.flags.Z = diff == 0
    @regs.flags.N = 1
    @regs.flags.H = (@regs.A & 0xF) < (n & 0xF)
    @regs.flags.C = @regs.A < n

  CP_R: (reg) ->
    n    = @memory[@regs[reg]]
    diff = (@regs.A - n) & 0xFF

    @regs.flags.Z = diff == 0
    @regs.flags.N = 1
    @regs.flags.H = (@regs.A & 0xF) < (n & 0xF)
    @regs.flags.C = @regs.A < n

  CP_n: (reg) ->
    n    = @getUint8()
    diff = (@regs.A - n) & 0xFF

    @regs.flags.Z = diff == 0
    @regs.flags.N = 1
    @regs.flags.H = (@regs.A & 0xF) < (n & 0xF)
    @regs.flags.C = @regs.A < n

  INC_r: (reg) ->
    n = (@regs[reg] + 1) & 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = !(n & 0xF)

    @regs[reg] = n

  INC_R: (reg) ->
    n = (@memory[@regs[reg]] + 1) & 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = !(n & 0xF)

    @memory[@regs[reg]] = n

  DEC_r: (reg) ->
    n = (@regs[reg] - 1) & 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.N = 1
    @regs.flags.H = (n & 0xF) == 0xF

    @regs[reg] = n

  DEC_R: (reg) ->
    n = (@memory[@regs[reg]] - 1) & 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.N = 1
    @regs.flags.H = (n & 0xF) == 0xF

    @memory[@regs[reg]] = n

  ADD_HL_r: (reg) ->
    n   = @regs[reg]
    sum = (@regs.HL + @regs[reg]) & 0xFFFF

    @regs.flags.N = 0
    @regs.flags.H = (((@regs.HL & 0xFFF)  + (n & 0xFFF))  & 0x1000)  > 0
    @regs.flags.C = (((@regs.HL & 0xFFFF) + (n & 0xFFFF)) & 0x10000) > 0

    @regs.HL = sum

  ADD_SP_n: ->
    n   = @getInt8()
    sum = (@regs.SP + n) & 0xFFFF

    @regs.flags.Z = 0
    @regs.flags.N = 0
    @regs.flags.H = (((@regs.SP & 0xF)  + (n & 0xF))  & 0x10)  > 0
    @regs.flags.C = (((@regs.SP & 0xFF) + (n & 0xFF)) & 0x100) > 0

    @regs.SP = sum

  INC_rr: (reg) ->
    @regs[reg] = (@regs[reg] + 1) & 0xFFFF

  DEC_rr: (reg) ->
    @regs[reg] = (@regs[reg] - 1) & 0xFFFF

  DAA: ->
    # Based on: http://forums.nesdev.com/viewtopic.php?t=9088
    n = @regs.A

    unless @regs.flags.N
      if @regs.flags.H || (n & 0xF) > 9
        n += 0x06

      if @regs.flags.C || (n > 0x9F)
        n += 0x60
    else
      if @regs.flags.H
        n = (n - 6) & 0xFF

      if @regs.flags.C
        n -= 0x60

    if (n & 0x100) == 0x100
      @regs.flags.C = 1

    n &= 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.H = 0

    @regs.A = n

  CPL: ->
    @regs.flags.N = 1
    @regs.flags.H = 1
    @regs.A ^= 0xFF

  CCF: ->
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = !@regs.flags.C

  SCF: ->
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 1

  NOP: ->
    # Nothing to see here.

  HALT: ->
    console.log 'HALT is not implemented!'

  STOP: ->
    console.log 'STOP is not implemented!'

  DI: ->
    console.log 'DI is not implemented!'

  EI: ->
    console.log 'EI is not implemented!'

  RLCA: ->
    carry = @regs.A >> 7
    n     = ((@regs.A << 1) | carry) & 0xFF

    @regs.flags.Z = 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @regs.A = n

  RLA: ->
    carry = @regs.A >> 7
    n     = ((@regs.A << 1) | @regs.flags.C) & 0xFF

    @regs.flags.Z = 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @regs.A = n

  RRCA: ->
    carry = @regs.A & 0x1
    n     = ((@regs.A >> 1) | (carry << 7)) & 0xFF

    @regs.flags.Z = 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @regs.A = n

  RRA: ->
    carry = @regs.A & 1
    n     = ((@regs.A >> 1) | (@regs.flags.C << 7)) & 0xFF

    @regs.flags.Z = 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @regs.A = n

  JP_nn: ->
    @regs.PC = @getUint16()

  JP_nz_nn: ->
    address = @getUint16()
    unless @regs.flags.Z
      @regs.PC = address

  JP_z_nn: ->
    address = @getUint16()
    if @regs.flags.Z
      @regs.PC = address

  JP_nc_nn: ->
    address = @getUint16()
    unless @regs.flags.C
      @regs.PC = address

  JP_c_nn: ->
    address = @getUint16()
    if @regs.flags.C
      @regs.PC = address

  JP_HL: ->
    @regs.PC = @regs.HL

  JR_n: ->
    @regs.PC = @getRelInt8JmpAddress()

  JR_nz_n: ->
    address = @getRelInt8JmpAddress()
    unless @regs.flags.Z
      @regs.PC = address

  JR_z_n: ->
    address = @getRelInt8JmpAddress()
    if @regs.flags.Z
      @regs.PC = address

  JR_nc_n: ->
    address = @getRelInt8JmpAddress()
    unless @regs.flags.C
      @regs.PC = address

  JR_c_n: ->
    address = @getRelInt8JmpAddress()
    if @regs.flags.C
      @regs.PC = address

  CALL_nn: ->
    address = @getUint16()
    @PUSH_r('PC')
    @regs.PC = address

  CALL_nz_nn: ->
    address = @getUint16()
    unless @regs.flags.Z
      @PUSH_r('PC')
      @regs.PC = address

  CALL_z_nn: ->
    address = @getUint16()
    if @regs.flags.Z
      @PUSH_r('PC')
      @regs.PC = address

  CALL_nc_nn: ->
    address = @getUint16()
    unless @regs.flags.C
      @PUSH_r('PC')
      @regs.PC = address

  CALL_c_nn: ->
    address = @getUint16()
    if @regs.flags.C
      @PUSH_r('PC')
      @regs.PC = address

  RST: ->
    console.log 'RST is not implemented!'

  RET: ->
    @POP_r('PC')

  RET_nz: ->
    unless @regs.flags.Z
      @POP_r('PC')

  RET_z: ->
    if @regs.flags.Z
      @POP_r('PC')

  RET_nc: ->
    unless @regs.flags.C
      @POP_r('PC')

  RET_c: ->
    if @regs.flags.C
      @POP_r('PC')

  RETI: ->
    console.log 'RETI is not implemented!'

  SWAP_r: (reg) ->
    n      = @regs[reg]
    result = ((n << 4) | (n >> 4)) & 0xFF

    @regs.flags.Z = result == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

    @regs[reg] = result

  SWAP_R: (reg) ->
    n      = @memory[@regs[reg]]
    result = ((n << 4) | (n >> 4)) & 0xFF

    @regs.flags.Z = result == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

    @memory[@regs[reg]] = result

  RLC_r: (reg) ->
    carry = @regs[reg] >> 7
    n     = ((@regs[reg] << 1) | carry) & 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @regs[reg] = n

  RLC_R: (reg) ->
    carry = @memory[@regs[reg]] >> 7
    n     = ((@memory[@regs[reg]] << 1) | carry) & 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @memory[@regs[reg]] = n

  RL_r: (reg) ->
    carry = (@regs[reg] >> 7) & 0x1
    n     = ((@regs[reg] << 1) | (@regs.flags.C)) & 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @regs[reg] = n

  RL_R: (reg) ->
    carry = (@memory[@regs[reg]] >> 7) & 0x1
    n     = ((@memory[@regs[reg]] << 1) | (@regs.flags.C)) & 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @memory[@regs[reg]] = n

  RRC_r: (reg) ->
    carry = @regs[reg] & 0x1
    n     = ((@regs[reg] >> 1) | (carry << 7)) & 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @regs[reg] = n

  RRC_R: (reg) ->
    carry = @memory[@regs[reg]] & 0x1
    n     = ((@memory[@regs[reg]] >> 1) | (carry << 7)) & 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @memory[@regs[reg]] = n

  RR_r: (reg) ->
    carry = @regs[reg] & 1
    n     = ((@regs[reg] >> 1) | (@regs.flags.C << 7)) & 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @regs[reg] = n

  RR_R: (reg) ->
    carry = @memory[@regs[reg]] & 1
    n     = ((@memory[@regs[reg]] >> 1) | (@regs.flags.C << 7)) & 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @memory[@regs[reg]] = n

  SLA_r: (reg) ->
    n      = @regs[reg] << 1
    result = n & 0xFF

    @regs.flags.Z = result == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = (n & 0x100) > 0

    @regs[reg] = result

  SLA_R: (reg) ->
    n      = @memory[@regs[reg]] << 1
    result = n & 0xFF

    @regs.flags.Z = result == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = (n & 0x100) > 0

    @memory[@regs[reg]] = result

  SRA_r: (reg) ->
    carry = @regs[reg] & 1
    msb   = @regs[reg] >> 7
    n     = ((msb << 7) | (@regs[reg] >> 1)) & 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @regs[reg] = n

  SRA_R: (reg) ->
    carry = @memory[@regs[reg]] & 1
    msb   = @memory[@regs[reg]] >> 7
    n     = ((msb << 7) | (@memory[@regs[reg]] >> 1)) & 0xFF

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @memory[@regs[reg]] = n

  SRL_r: (reg) ->
    carry = @regs[reg] & 1
    n     = @regs[reg] >> 1

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @regs[reg] = n

  SRL_R: (reg) ->
    carry = @memory[@regs[reg]] & 1
    n     = @memory[@regs[reg]] >> 1

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = carry

    @memory[@regs[reg]] = n

  BIT_b_r: (bit, reg) ->
    n = @regs[reg] & (1 << bit)

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = 1

  BIT_b_R: (bit, reg) ->
    n = @memory[@regs[reg]] & (1 << bit)

    @regs.flags.Z = n == 0
    @regs.flags.N = 0
    @regs.flags.H = 1

  SET_b_r: (bit, reg) ->
    @regs[reg] |= (1 << bit)

  SET_b_R: (bit, reg) ->
    @memory[@regs[reg]] |= (1 << bit)

  RES_b_r: (bit, reg) ->
    @regs[reg] &= ~(1 << bit)

  RES_b_R: (bit, reg) ->
    @memory[@regs[reg]] &= ~(1 << bit)

  executeOpcode: ->
    opcode = @getUint8()
    unless opcode?
      return false


    switch opcode

      # LD nn, n
      when 0x06 then @LD_r_n('B')
      when 0x0E then @LD_r_n('C')
      when 0x16 then @LD_r_n('D')
      when 0x1E then @LD_r_n('E')
      when 0x26 then @LD_r_n('H')
      when 0x2E then @LD_r_n('L')
      when 0x36 then @LD_R_n('HL')

      # LD r1, r2

      when 0x40 then @LD_r_r2('B', 'B')
      when 0x41 then @LD_r_r2('B', 'C')
      when 0x42 then @LD_r_r2('B', 'D')
      when 0x43 then @LD_r_r2('B', 'E')
      when 0x44 then @LD_r_r2('B', 'H')
      when 0x45 then @LD_r_r2('B', 'L')
      when 0x46 then @LD_r_R2('B', 'HL')

      when 0x48 then @LD_r_r2('C', 'B')
      when 0x49 then @LD_r_r2('C', 'C')
      when 0x4A then @LD_r_r2('C', 'D')
      when 0x4B then @LD_r_r2('C', 'E')
      when 0x4C then @LD_r_r2('C', 'H')
      when 0x4D then @LD_r_r2('C', 'L')
      when 0x4E then @LD_r_R2('C', 'HL')

      when 0x50 then @LD_r_r2('D', 'B')
      when 0x51 then @LD_r_r2('D', 'C')
      when 0x52 then @LD_r_r2('D', 'D')
      when 0x53 then @LD_r_r2('D', 'E')
      when 0x54 then @LD_r_r2('D', 'H')
      when 0x55 then @LD_r_r2('D', 'L')
      when 0x56 then @LD_r_R2('D', 'HL')

      when 0x58 then @LD_r_r2('E', 'B')
      when 0x59 then @LD_r_r2('E', 'C')
      when 0x5A then @LD_r_r2('E', 'D')
      when 0x5B then @LD_r_r2('E', 'E')
      when 0x5C then @LD_r_r2('E', 'H')
      when 0x5D then @LD_r_r2('E', 'L')
      when 0x5E then @LD_r_R2('E', 'HL')

      when 0x60 then @LD_r_r2('H', 'B')
      when 0x61 then @LD_r_r2('H', 'C')
      when 0x62 then @LD_r_r2('H', 'D')
      when 0x63 then @LD_r_r2('H', 'E')
      when 0x64 then @LD_r_r2('H', 'H')
      when 0x65 then @LD_r_r2('H', 'L')
      when 0x66 then @LD_r_R2('H', 'HL')

      when 0x68 then @LD_r_r2('L', 'B')
      when 0x69 then @LD_r_r2('L', 'C')
      when 0x6A then @LD_r_r2('L', 'D')
      when 0x6B then @LD_r_r2('L', 'E')
      when 0x6C then @LD_r_r2('L', 'H')
      when 0x6D then @LD_r_r2('L', 'L')
      when 0x6E then @LD_r_R2('L', 'HL')

      when 0x70 then @LD_R_r2('HL', 'B')
      when 0x71 then @LD_R_r2('HL', 'C')
      when 0x72 then @LD_R_r2('HL', 'D')
      when 0x73 then @LD_R_r2('HL', 'E')
      when 0x74 then @LD_R_r2('HL', 'H')
      when 0x75 then @LD_R_r2('HL', 'L')

      # LD A, n
      when 0x7F then @LD_A_r('A')
      when 0x78 then @LD_A_r('B')
      when 0x79 then @LD_A_r('C')
      when 0x7A then @LD_A_r('D')
      when 0x7B then @LD_A_r('E')
      when 0x7C then @LD_A_r('H')
      when 0x7D then @LD_A_r('L')
      when 0x0A then @LD_A_R('BC')
      when 0x1A then @LD_A_R('DE')
      when 0x7E then @LD_A_R('HL')
      when 0xFA then @LD_A_NN()
      when 0x3E then @LD_A_n()

      # LD n, A
      when 0x47 then @LD_r_A('B')
      when 0x4F then @LD_r_A('C')
      when 0x57 then @LD_r_A('D')
      when 0x5F then @LD_r_A('E')
      when 0x67 then @LD_r_A('H')
      when 0x6F then @LD_r_A('L')
      when 0x02 then @LD_R_A('BC')
      when 0x12 then @LD_R_A('DE')
      when 0x77 then @LD_R_A('HL')
      when 0xEA then @LD_NN_A()

      # LDH A, (C)
      when 0xF2 then @LDH_A_C()
      # LDH (C), A
      when 0xE2 then @LDH_C_A()
      # LDD A, (HL)
      when 0x3A then @LDD_A_HL()
      # LDD (HL), A
      when 0x32 then @LDD_HL_A()
      # LDI A, (HL)
      when 0x2A then @LDI_A_HL()
      # LDI (HL), A
      when 0x22 then @LDI_HL_A()
      # LDH (n), A
      when 0xE0 then @LDH_N_A()
      # LDH A, (n)
      when 0xF0 then @LDH_A_N()

      # LD n, nn
      when 0x01 then @LD_r_nn('BC')
      when 0x11 then @LD_r_nn('DE')
      when 0x21 then @LD_r_nn('HL')
      when 0x31 then @LD_r_nn('SP')

      # LD SP, HL
      when 0xF9 then @LD_SP_HL()
      # LDHL SP, n
      when 0xF8 then @LDHL_SP_n()
      # LD (nn), SP
      when 0x08 then @LD_NN_SP()

      # PUSH nn
      when 0xF5 then @PUSH_r('AF')
      when 0xC5 then @PUSH_r('BC')
      when 0xD5 then @PUSH_r('DE')
      when 0xE5 then @PUSH_r('HL')

      # POP nn
      when 0xF1 then @POP_r('AF')
      when 0xC1 then @POP_r('BC')
      when 0xD1 then @POP_r('DE')
      when 0xE1 then @POP_r('HL')

      # ADD A, n
      when 0x87 then @ADD_A_r('A')
      when 0x80 then @ADD_A_r('B')
      when 0x81 then @ADD_A_r('C')
      when 0x82 then @ADD_A_r('D')
      when 0x83 then @ADD_A_r('E')
      when 0x84 then @ADD_A_r('H')
      when 0x85 then @ADD_A_r('L')
      when 0x86 then @ADD_A_R('HL')
      when 0xC6 then @ADD_A_n()

      # ADC A, n
      when 0x8F then @ADC_A_r('A')
      when 0x88 then @ADC_A_r('B')
      when 0x89 then @ADC_A_r('C')
      when 0x8A then @ADC_A_r('D')
      when 0x8B then @ADC_A_r('E')
      when 0x8C then @ADC_A_r('H')
      when 0x8D then @ADC_A_r('L')
      when 0x8E then @ADC_A_R('HL')
      when 0xCE then @ADC_A_n()

      # SUB n
      when 0x97 then @SUB_r('A')
      when 0x90 then @SUB_r('B')
      when 0x91 then @SUB_r('C')
      when 0x92 then @SUB_r('D')
      when 0x93 then @SUB_r('E')
      when 0x94 then @SUB_r('H')
      when 0x95 then @SUB_r('L')
      when 0x96 then @SUB_R('HL')
      when 0xD6 then @SUB_n()

      # SBC A, n
      when 0x9F then @SBC_A_r('A')
      when 0x98 then @SBC_A_r('B')
      when 0x99 then @SBC_A_r('C')
      when 0x9A then @SBC_A_r('D')
      when 0x9B then @SBC_A_r('E')
      when 0x9C then @SBC_A_r('H')
      when 0x9D then @SBC_A_r('L')
      when 0x9E then @SBC_A_R('HL')
      when 0xDE then @SBC_A_n()

      # AND n
      when 0xA7 then @AND_r('A')
      when 0xA0 then @AND_r('B')
      when 0xA1 then @AND_r('C')
      when 0xA2 then @AND_r('D')
      when 0xA3 then @AND_r('E')
      when 0xA4 then @AND_r('H')
      when 0xA5 then @AND_r('L')
      when 0xA6 then @AND_R('HL')
      when 0xE6 then @AND_n()

      # OR n
      when 0xB7 then @OR_r('A')
      when 0xB0 then @OR_r('B')
      when 0xB1 then @OR_r('C')
      when 0xB2 then @OR_r('D')
      when 0xB3 then @OR_r('E')
      when 0xB4 then @OR_r('H')
      when 0xB5 then @OR_r('L')
      when 0xB6 then @OR_R('HL')
      when 0xF6 then @OR_n()

      # XOR n
      when 0xAF then @XOR_r('A')
      when 0xA8 then @XOR_r('B')
      when 0xA9 then @XOR_r('C')
      when 0xAA then @XOR_r('D')
      when 0xAB then @XOR_r('E')
      when 0xAC then @XOR_r('H')
      when 0xAD then @XOR_r('L')
      when 0xAE then @XOR_R('HL')
      when 0xEE then @XOR_n()

      # CP n
      when 0xBF then @CP_r('A')
      when 0xB8 then @CP_r('B')
      when 0xB9 then @CP_r('C')
      when 0xBA then @CP_r('D')
      when 0xBB then @CP_r('E')
      when 0xBC then @CP_r('H')
      when 0xBD then @CP_r('L')
      when 0xBE then @CP_R('HL')
      when 0xFE then @CP_n()

      # INC n
      when 0x3C then @INC_r('A')
      when 0x04 then @INC_r('B')
      when 0x0C then @INC_r('C')
      when 0x14 then @INC_r('D')
      when 0x1C then @INC_r('E')
      when 0x24 then @INC_r('H')
      when 0x2C then @INC_r('L')
      when 0x34 then @INC_R('HL')

      # DEC n
      when 0x3D then @DEC_r('A')
      when 0x05 then @DEC_r('B')
      when 0x0D then @DEC_r('C')
      when 0x15 then @DEC_r('D')
      when 0x1D then @DEC_r('E')
      when 0x25 then @DEC_r('H')
      when 0x2D then @DEC_r('L')
      when 0x35 then @DEC_R('HL')

      # ADD HL, n
      when 0x09 then @ADD_HL_r('BC')
      when 0x19 then @ADD_HL_r('DE')
      when 0x29 then @ADD_HL_r('HL')
      when 0x39 then @ADD_HL_r('SP')

      # ADD SP, n
      when 0xE8 then @ADD_SP_n()

      # INC nn
      when 0x03 then @INC_rr('BC')
      when 0x13 then @INC_rr('DE')
      when 0x23 then @INC_rr('HL')
      when 0x33 then @INC_rr('SP')

      # DEC nn
      when 0x0B then @DEC_rr('BC')
      when 0x1B then @DEC_rr('DE')
      when 0x2B then @DEC_rr('HL')
      when 0x3B then @DEC_rr('SP')

      # DAA
      when 0x27 then @DAA()
      # CPL
      when 0x2F then @CPL()
      # CCF
      when 0x3F then @CCF()
      # SCF
      when 0x37 then @SCF()
      # NOP
      when 0x00 then @NOP()
      # HALT
      when 0x76 then @HALT()
      # STOP
      when 0x10 then @STOP()
      # DI
      when 0xF3 then @DI()
      # EI
      when 0xFB then @EI()
      # RLCA
      when 0x07 then @RLCA()
      # RLA
      when 0x17 then @RLA()
      # RRCA
      when 0x0F then @RRCA()
      # RRA
      when 0x1F then @RRA()

      # JP nn
      when 0xC3 then @JP_nn()

      # JP cc, nn
      when 0xC2 then @JP_nz_nn()
      when 0xCA then @JP_z_nn()
      when 0xD2 then @JP_nc_nn()
      when 0xDA then @JP_c_nn()

      # JP (HL)
      when 0xE9 then @JP_HL()
      # JR n
      when 0x18 then @JR_n()

      # JR cc, n
      when 0x20 then @JR_nz_n()
      when 0x28 then @JR_z_n()
      when 0x30 then @JR_nc_n()
      when 0x38 then @JR_c_n()

      # CALL nn
      when 0xCD then @CALL_nn()

      # CALL cc, nn
      when 0xC4 then @CALL_nz_nn()
      when 0xCC then @CALL_z_nn()
      when 0xD4 then @CALL_nc_nn()
      when 0xDC then @CALL_c_nn()

      # RST n
      when 0xC7 then @RST(0x00)
      when 0xCF then @RST(0x08)
      when 0xD7 then @RST(0x10)
      when 0xDF then @RST(0x18)
      when 0xE7 then @RST(0x20)
      when 0xEF then @RST(0x28)
      when 0xF7 then @RST(0x30)
      when 0xFF then @RST(0x38)

      # RET
      when 0xC9 then @RET()

      # RET cc
      when 0xC0 then @RET_nz()
      when 0xC8 then @RET_z()
      when 0xD0 then @RET_nc()
      when 0xD8 then @RET_c()

      # RETI
      when 0xD9 then @RETI()

      # Ext ops
      when 0xCB
        opcode2 = @getUint8()

        switch opcode2

          # SWAP n
          when 0x37 then @SWAP_r('A')
          when 0x30 then @SWAP_r('B')
          when 0x31 then @SWAP_r('C')
          when 0x32 then @SWAP_r('D')
          when 0x33 then @SWAP_r('E')
          when 0x34 then @SWAP_r('H')
          when 0x35 then @SWAP_r('L')
          when 0x36 then @SWAP_R('HL')

          # RLC n
          when 0x07 then @RLC_r('A')
          when 0x00 then @RLC_r('B')
          when 0x01 then @RLC_r('C')
          when 0x02 then @RLC_r('D')
          when 0x03 then @RLC_r('E')
          when 0x04 then @RLC_r('H')
          when 0x05 then @RLC_r('L')
          when 0x06 then @RLC_R('HL')

          # RL n
          when 0x17 then @RL_r('A')
          when 0x10 then @RL_r('B')
          when 0x11 then @RL_r('C')
          when 0x12 then @RL_r('D')
          when 0x13 then @RL_r('E')
          when 0x14 then @RL_r('H')
          when 0x15 then @RL_r('L')
          when 0x16 then @RL_R('HL')

          # RRC n
          when 0x0F then @RRC_r('A')
          when 0x08 then @RRC_r('B')
          when 0x09 then @RRC_r('C')
          when 0x0A then @RRC_r('D')
          when 0x0B then @RRC_r('E')
          when 0x0C then @RRC_r('H')
          when 0x0D then @RRC_r('L')
          when 0x0E then @RRC_R('HL')

          # RR n
          when 0x1F then @RR_r('A')
          when 0x18 then @RR_r('B')
          when 0x19 then @RR_r('C')
          when 0x1A then @RR_r('D')
          when 0x1B then @RR_r('E')
          when 0x1C then @RR_r('H')
          when 0x1D then @RR_r('L')
          when 0x1E then @RR_R('HL')

          # SLA n
          when 0x27 then @SLA_r('A')
          when 0x20 then @SLA_r('B')
          when 0x21 then @SLA_r('C')
          when 0x22 then @SLA_r('D')
          when 0x23 then @SLA_r('E')
          when 0x24 then @SLA_r('H')
          when 0x25 then @SLA_r('L')
          when 0x26 then @SLA_R('HL')

          # SRA n
          when 0x2F then @SRA_r('A')
          when 0x28 then @SRA_r('B')
          when 0x29 then @SRA_r('C')
          when 0x2A then @SRA_r('D')
          when 0x2B then @SRA_r('E')
          when 0x2C then @SRA_r('H')
          when 0x2D then @SRA_r('L')
          when 0x2E then @SRA_R('HL')

          # SRL n
          when 0x3F then @SRL_r('A')
          when 0x38 then @SRL_r('B')
          when 0x39 then @SRL_r('C')
          when 0x3A then @SRL_r('D')
          when 0x3B then @SRL_r('E')
          when 0x3C then @SRL_r('H')
          when 0x3D then @SRL_r('L')
          when 0x3E then @SRL_R('HL')

          else
            unless opcode2 >= 0x40
              throw "Unknown opcode: 0xCB 0x#{opcode2.toString(16)}"

            # Command
            command =
              if opcode2 >= 0x40 and opcode2 <= 0x7F
                'BIT'
              else if opcode2 >= 0x80 and opcode2 <= 0xBF
                'RES'
              else if opcode2 >= 0xC0 and opcode2 <= 0xFF
                'SET'

            # Bit
            bit = (opcode2 >> 3) & 0x7

            # Register
            registers = ['B', 'C', 'D', 'E', 'H', 'L', '(HL)', 'A']
            register  = registers[opcode2 & 0x7]

            unless register == '(HL)'
              @["#{command}_b_r"](bit, register)
            else
              @["#{command}_b_R"](bit, 'HL')

      else
        throw "Unknown opcode: 0x#{opcode.toString(16)}"

    !@breakpoints?[@regs.PC]

window.CPU = CPU
