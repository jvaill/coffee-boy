#
# Responsible for holding the core's registers and flags.
# Also defines properties used mainly as input to instructions (hence params).
#
# These properties are:
#   - register pairs:       AF, BC, DE, HL
#   - immediate reads:      UI8, SI8, UI16
#   - pointers into memory: (AF), (BC), (DE), (HL), (UI16)
#
class Params
  REG_PAIRS = ['AF', 'BC', 'DE', 'HL']

  MMU: null

  # Registers
  PC: 0, SP: 0
  A: 0, B: 0, C: 0, D: 0, E: 0
  H: 0, L: 0

  Flags:
    Z: 0, N: 0, H: 0, C: 0

  properties:
    F:
      get: ->
        flags = 0
        if @Flags.Z then flags |= 0x80
        if @Flags.N then flags |= 0x40
        if @Flags.H then flags |= 0x20
        if @Flags.C then flags |= 0x10
        flags

      set: (value) ->
        @Flags.Z = (value & 0x80) > 0
        @Flags.N = (value & 0x40) > 0
        @Flags.H = (value & 0x20) > 0
        @Flags.C = (value & 0x10) > 0

    # Immediates
    UI8:  get: -> n = @MMU.Get(@PC);       @PC += 1; n
    SI8:  get: -> n = @MMU.GetInt8(@PC);   @PC += 1; n
    UI16: get: -> n = @MMU.GetUint16(@PC); @PC += 2; n

    # Immediate as a pointer into memory
    '(UI16)':
      get:         -> @MMU.Get @UI16
      set: (value) -> @MMU.Set @UI16, value

  constructor: ->
    Object.defineProperties this, this.properties
    delete this.properties

    # Create properties for register pairs.
    for regPair in REG_PAIRS
      [regA, regB] = [regPair[0], regPair[1]]

      # Register pair
      do (regA, regB) =>
        property =
          get: ->
            (@[regA] << 8) + @[regB]

          set: (value) ->
            @[regA] = (value >> 8) & 0xFF
            @[regB] = value & 0xFF

        Object.defineProperty this, regPair, property

      # Register pair as a pointer into memory
      do (regPair) =>
        property =
          get: ->
            @MMU.Get @[regPair]

          set: (value) ->
            @MMU.Set @[regPair], value

        Object.defineProperty this, "(#{regPair})", property

  Reset: =>
    for reg in ['A', 'B', 'C', 'D', 'E', 'H', 'L', 'F', 'PC', 'SP']
      @[reg] = 0

    for flag in ['Z', 'N', 'H', 'C']
      @Flags[flag] = 0

  CheckFlag: (cond) =>
    switch cond
      when 'Z'  then @Flags.Z
      when 'C'  then @Flags.C
      when 'NZ' then !@Flags.Z
      when 'NC' then !@Flags.C
      else true

# The almighty core!
class CPU
  Breakpoints: null
  params:      new Params()
  mmu:         null

  properties:
    MMU:
      get:         -> @mmu
      set: (value) -> @mmu = @params.MMU = value

  constructor: ->
    Object.defineProperties this, this.properties
    delete this.properties

  LoadCode: (buffer) ->
    unless buffer instanceof Uint8Array
      throw 'Input buffer must be of type Uint8Array.'

    # Kind of map the ROM where it belongs
    for i in [0...buffer.byteLength]
      @mmu.Set i, buffer[i]

    @params.Reset()

  getRelInt8JmpAddress: ->
    # Order matters
    @params.SI8 + @params.PC

  # Opcodes are gathered from:
  #   - http://meatfighter.com/gameboy/GBCPUman.pdf
  #   - http://imrannazar.com/Gameboy-Z80-Opcode-Map
  #   - http://www.scribd.com/doc/39999184/GameBoy-Programming-Manual
  #
  # As conventions:
  #   - 'r' represents a parameter (see Params object)
  #   - 'n' represents a byte
  #   - 'rr' represents a 16 bit parameter (see Params object)
  #   - 'nn' represents a 16 bit integer
  #   - Uppercase characters denote a pointer

  LD_r_r2: (reg, reg2) ->
    @params[reg] = @params[reg2]

  LDH_A_C: ->
    @params.A = @mmu.Get(0xFF00 + @params.C)

  LDH_C_A: ->
    @mmu.Set 0xFF00 + @params.C, @params.A

  LDD_A_HL: ->
    @params.A = @mmu.Get(@params.HL)
    @params.HL--

  LDD_HL_A: ->
    @mmu.Set @params.HL, @params.A
    @params.HL--

  LDI_A_HL: ->
    @params.A = @mmu.Get(@params.HL)
    @params.HL++

  LDI_HL_A: ->
    @mmu.Set @params.HL, @params.A
    @params.HL++

  LDH_N_A: ->
    @mmu.Set 0xFF00 + @params.UI8, @params.A

  LDH_A_N: ->
    @params.A = @mmu.Get(0xFF00 + @params.UI8)

  LDHL_SP_n: ->
    n = @params.SI8

    @params.Flags.Z = 0
    @params.Flags.N = 0
    @params.Flags.H = (((@params.SP & 0xF)  + (n & 0xF))  & 0x10)  > 0
    @params.Flags.C = (((@params.SP & 0xFF) + (n & 0xFF)) & 0x100) > 0

    @params.HL = (@params.SP + n) & 0xFFFF

  LD_NN_SP: ->
    address = @params.UI16
    @mmu.Set address,     @params.SP & 0xFF
    @mmu.Set address + 1, (@params.SP >> 8) & 0xFF

  PUSH_r: (reg) ->
    @params.SP--
    @mmu.Set @params.SP, (@params[reg] >> 8) & 0xFF
    @params.SP--
    @mmu.Set @params.SP, @params[reg] & 0xFF

  POP_r: (reg) ->
    byte  = @mmu.Get(@params.SP)
    @params.SP++
    byte2 = @mmu.Get(@params.SP)
    @params.SP++
    @params[reg] = byte | (byte2 << 8)

  ADD_A_r: (reg) ->
    n   = @params[reg]
    sum = (@params.A + n) & 0xFF

    @params.Flags.Z = sum == 0
    @params.Flags.N = 0
    @params.Flags.H = (((@params.A & 0xF)  + (n & 0xF))  & 0x10)  > 0
    @params.Flags.C = (((@params.A & 0xFF) + (n & 0xFF)) & 0x100) > 0

    @params.A = sum

  ADC_A_r: (reg) ->
    n   = @params[reg]
    sum = (@params.A + n + @params.Flags.C) & 0xFF

    @params.Flags.Z = sum == 0
    @params.Flags.N = 0
    @params.Flags.H = (((@params.A & 0xF)  + (n & 0xF)  + @params.Flags.C) & 0x10)  > 0
    @params.Flags.C = (((@params.A & 0xFF) + (n & 0xFF) + @params.Flags.C) & 0x100) > 0

    @params.A = sum

  SUB_r: (reg) ->
    n    = @params[reg]
    diff = (@params.A - n) & 0xFF

    @params.Flags.Z = diff == 0
    @params.Flags.N = 1
    @params.Flags.H = (@params.A & 0xF) < (n & 0xF)
    @params.Flags.C = @params.A < n

    @params.A = diff

  SBC_A_r: (reg) ->
    n    = @params[reg]
    diff = (@params.A - n - @params.Flags.C) & 0xFF

    @params.Flags.Z = diff == 0
    @params.Flags.N = 1
    @params.Flags.H = (@params.A & 0xF) < (n & 0xF) + @params.Flags.C
    @params.Flags.C = @params.A < n + @params.Flags.C

    @params.A = diff

  AND_r: (reg) ->
    @params.A &= @params[reg]

    @params.Flags.Z = @params.A == 0
    @params.Flags.N = 0
    @params.Flags.H = 1
    @params.Flags.C = 0

  OR_r: (reg) ->
    @params.A |= @params[reg]

    @params.Flags.Z = @params.A == 0
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = 0

  XOR_r: (reg) ->
    @params.A ^= @params[reg]

    @params.Flags.Z = @params.A == 0
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = 0

  CP_r: (reg) ->
    n    = @params[reg]
    diff = (@params.A - n) & 0xFF

    @params.Flags.Z = diff == 0
    @params.Flags.N = 1
    @params.Flags.H = (@params.A & 0xF) < (n & 0xF)
    @params.Flags.C = @params.A < n

  INC_r: (reg) ->
    n = (@params[reg] + 1) & 0xFF

    @params.Flags.Z = n == 0
    @params.Flags.N = 0
    @params.Flags.H = !(n & 0xF)

    @params[reg] = n

  DEC_r: (reg) ->
    n = (@params[reg] - 1) & 0xFF

    @params.Flags.Z = n == 0
    @params.Flags.N = 1
    @params.Flags.H = (n & 0xF) == 0xF

    @params[reg] = n

  ADD_HL_r: (reg) ->
    n   = @params[reg]
    sum = (@params.HL + @params[reg]) & 0xFFFF

    @params.Flags.N = 0
    @params.Flags.H = (((@params.HL & 0xFFF)  + (n & 0xFFF))  & 0x1000)  > 0
    @params.Flags.C = (((@params.HL & 0xFFFF) + (n & 0xFFFF)) & 0x10000) > 0

    @params.HL = sum

  ADD_SP_n: ->
    n   = @params.SI8
    sum = (@params.SP + n) & 0xFFFF

    @params.Flags.Z = 0
    @params.Flags.N = 0
    @params.Flags.H = (((@params.SP & 0xF)  + (n & 0xF))  & 0x10)  > 0
    @params.Flags.C = (((@params.SP & 0xFF) + (n & 0xFF)) & 0x100) > 0

    @params.SP = sum

  INC_rr: (reg) ->
    @params[reg] = (@params[reg] + 1) & 0xFFFF

  DEC_rr: (reg) ->
    @params[reg] = (@params[reg] - 1) & 0xFFFF

  DAA: ->
    # Based on: http://forums.nesdev.com/viewtopic.php?t=9088
    n = @params.A

    unless @params.Flags.N
      if @params.Flags.H || (n & 0xF) > 9
        n += 0x06

      if @params.Flags.C || (n > 0x9F)
        n += 0x60
    else
      if @params.Flags.H
        n = (n - 6) & 0xFF

      if @params.Flags.C
        n -= 0x60

    if (n & 0x100) == 0x100
      @params.Flags.C = 1

    n &= 0xFF

    @params.Flags.Z = n == 0
    @params.Flags.H = 0

    @params.A = n

  CPL: ->
    @params.Flags.N = 1
    @params.Flags.H = 1
    @params.A ^= 0xFF

  CCF: ->
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = !@params.Flags.C

  SCF: ->
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = 1

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
    carry = @params.A >> 7
    n     = ((@params.A << 1) | carry) & 0xFF

    @params.Flags.Z = 0
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = carry

    @params.A = n

  RLA: ->
    carry = @params.A >> 7
    n     = ((@params.A << 1) | @params.Flags.C) & 0xFF

    @params.Flags.Z = 0
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = carry

    @params.A = n

  RRCA: ->
    carry = @params.A & 0x1
    n     = ((@params.A >> 1) | (carry << 7)) & 0xFF

    @params.Flags.Z = 0
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = carry

    @params.A = n

  RRA: ->
    carry = @params.A & 1
    n     = ((@params.A >> 1) | (@params.Flags.C << 7)) & 0xFF

    @params.Flags.Z = 0
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = carry

    @params.A = n

  JP_nn: (cond) ->
    address = @params.UI16
    if @params.CheckFlag(cond)
      @params.PC = address

  JP_HL: ->
    @params.PC = @params.HL

  JR_n: (cond) ->
    address = @getRelInt8JmpAddress()
    if @params.CheckFlag(cond)
      @params.PC = address

  CALL_nn: (cond) ->
    address = @params.UI16
    if @params.CheckFlag(cond)
      @PUSH_r('PC')
      @params.PC = address

  RST: ->
    console.log 'RST is not implemented!'

  RET: (cond) ->
    if @params.CheckFlag(cond)
      @POP_r('PC')

  RETI: ->
    console.log 'RETI is not implemented!'

  SWAP_r: (reg) ->
    n      = @params[reg]
    result = ((n << 4) | (n >> 4)) & 0xFF

    @params.Flags.Z = result == 0
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = 0

    @params[reg] = result

  RLC_r: (reg) ->
    carry = @params[reg] >> 7
    n     = ((@params[reg] << 1) | carry) & 0xFF

    @params.Flags.Z = n == 0
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = carry

    @params[reg] = n

  RL_r: (reg) ->
    carry = (@params[reg] >> 7) & 0x1
    n     = ((@params[reg] << 1) | (@params.Flags.C)) & 0xFF

    @params.Flags.Z = n == 0
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = carry

    @params[reg] = n

  RRC_r: (reg) ->
    carry = @params[reg] & 0x1
    n     = ((@params[reg] >> 1) | (carry << 7)) & 0xFF

    @params.Flags.Z = n == 0
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = carry

    @params[reg] = n

  RR_r: (reg) ->
    carry = @params[reg] & 1
    n     = ((@params[reg] >> 1) | (@params.Flags.C << 7)) & 0xFF

    @params.Flags.Z = n == 0
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = carry

    @params[reg] = n

  SLA_r: (reg) ->
    n      = @params[reg] << 1
    result = n & 0xFF

    @params.Flags.Z = result == 0
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = (n & 0x100) > 0

    @params[reg] = result

  SRA_r: (reg) ->
    carry = @params[reg] & 1
    msb   = @params[reg] >> 7
    n     = ((msb << 7) | (@params[reg] >> 1)) & 0xFF

    @params.Flags.Z = n == 0
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = carry

    @params[reg] = n

  SRL_r: (reg) ->
    carry = @params[reg] & 1
    n     = @params[reg] >> 1

    @params.Flags.Z = n == 0
    @params.Flags.N = 0
    @params.Flags.H = 0
    @params.Flags.C = carry

    @params[reg] = n

  BIT_b_r: (bit, reg) ->
    n = @params[reg] & (1 << bit)

    @params.Flags.Z = n == 0
    @params.Flags.N = 0
    @params.Flags.H = 1

  SET_b_r: (bit, reg) ->
    @params[reg] |= (1 << bit)

  RES_b_r: (bit, reg) ->
    @params[reg] &= ~(1 << bit)

  executeOpcode: ->
    opcode = @params.UI8
    unless opcode?
      return false

    switch opcode

      # LD nn, n
      when 0x06 then @LD_r_r2('B', 'UI8')
      when 0x0E then @LD_r_r2('C', 'UI8')
      when 0x16 then @LD_r_r2('D', 'UI8')
      when 0x1E then @LD_r_r2('E', 'UI8')
      when 0x26 then @LD_r_r2('H', 'UI8')
      when 0x2E then @LD_r_r2('L', 'UI8')
      when 0x36 then @LD_r_r2('(HL)', 'UI8')

      # LD r1, r2

      when 0x40 then @LD_r_r2('B', 'B')
      when 0x41 then @LD_r_r2('B', 'C')
      when 0x42 then @LD_r_r2('B', 'D')
      when 0x43 then @LD_r_r2('B', 'E')
      when 0x44 then @LD_r_r2('B', 'H')
      when 0x45 then @LD_r_r2('B', 'L')
      when 0x46 then @LD_r_r2('B', '(HL)')

      when 0x48 then @LD_r_r2('C', 'B')
      when 0x49 then @LD_r_r2('C', 'C')
      when 0x4A then @LD_r_r2('C', 'D')
      when 0x4B then @LD_r_r2('C', 'E')
      when 0x4C then @LD_r_r2('C', 'H')
      when 0x4D then @LD_r_r2('C', 'L')
      when 0x4E then @LD_r_r2('C', '(HL)')

      when 0x50 then @LD_r_r2('D', 'B')
      when 0x51 then @LD_r_r2('D', 'C')
      when 0x52 then @LD_r_r2('D', 'D')
      when 0x53 then @LD_r_r2('D', 'E')
      when 0x54 then @LD_r_r2('D', 'H')
      when 0x55 then @LD_r_r2('D', 'L')
      when 0x56 then @LD_r_r2('D', '(HL)')

      when 0x58 then @LD_r_r2('E', 'B')
      when 0x59 then @LD_r_r2('E', 'C')
      when 0x5A then @LD_r_r2('E', 'D')
      when 0x5B then @LD_r_r2('E', 'E')
      when 0x5C then @LD_r_r2('E', 'H')
      when 0x5D then @LD_r_r2('E', 'L')
      when 0x5E then @LD_r_r2('E', '(HL)')

      when 0x60 then @LD_r_r2('H', 'B')
      when 0x61 then @LD_r_r2('H', 'C')
      when 0x62 then @LD_r_r2('H', 'D')
      when 0x63 then @LD_r_r2('H', 'E')
      when 0x64 then @LD_r_r2('H', 'H')
      when 0x65 then @LD_r_r2('H', 'L')
      when 0x66 then @LD_r_r2('H', '(HL)')

      when 0x68 then @LD_r_r2('L', 'B')
      when 0x69 then @LD_r_r2('L', 'C')
      when 0x6A then @LD_r_r2('L', 'D')
      when 0x6B then @LD_r_r2('L', 'E')
      when 0x6C then @LD_r_r2('L', 'H')
      when 0x6D then @LD_r_r2('L', 'L')
      when 0x6E then @LD_r_r2('L', '(HL)')

      when 0x70 then @LD_r_r2('(HL)', 'B')
      when 0x71 then @LD_r_r2('(HL)', 'C')
      when 0x72 then @LD_r_r2('(HL)', 'D')
      when 0x73 then @LD_r_r2('(HL)', 'E')
      when 0x74 then @LD_r_r2('(HL)', 'H')
      when 0x75 then @LD_r_r2('(HL)', 'L')

      # LD A, n
      when 0x7F then @LD_r_r2('A', 'A')
      when 0x78 then @LD_r_r2('A', 'B')
      when 0x79 then @LD_r_r2('A', 'C')
      when 0x7A then @LD_r_r2('A', 'D')
      when 0x7B then @LD_r_r2('A', 'E')
      when 0x7C then @LD_r_r2('A', 'H')
      when 0x7D then @LD_r_r2('A', 'L')
      when 0x0A then @LD_r_r2('A', '(BC)')
      when 0x1A then @LD_r_r2('A', '(DE)')
      when 0x7E then @LD_r_r2('A', '(HL)')
      when 0xFA then @LD_r_r2('A', '(UI16)')
      when 0x3E then @LD_r_r2('A', 'UI8')

      # LD n, A
      when 0x47 then @LD_r_r2('B', 'A')
      when 0x4F then @LD_r_r2('C', 'A')
      when 0x57 then @LD_r_r2('D', 'A')
      when 0x5F then @LD_r_r2('E', 'A')
      when 0x67 then @LD_r_r2('H', 'A')
      when 0x6F then @LD_r_r2('L', 'A')
      when 0x02 then @LD_r_r2('(BC)', 'A')
      when 0x12 then @LD_r_r2('(DE)', 'A')
      when 0x77 then @LD_r_r2('(HL)', 'A')
      when 0xEA then @LD_r_r2('(UI16)', 'A')

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
      when 0x01 then @LD_r_r2('BC', 'UI16')
      when 0x11 then @LD_r_r2('DE', 'UI16')
      when 0x21 then @LD_r_r2('HL', 'UI16')
      when 0x31 then @LD_r_r2('SP', 'UI16')

      # LD SP, HL
      when 0xF9 then @LD_r_r2('SP', 'HL')
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
      when 0x86 then @ADD_A_r('(HL)')
      when 0xC6 then @ADD_A_r('UI8')

      # ADC A, n
      when 0x8F then @ADC_A_r('A')
      when 0x88 then @ADC_A_r('B')
      when 0x89 then @ADC_A_r('C')
      when 0x8A then @ADC_A_r('D')
      when 0x8B then @ADC_A_r('E')
      when 0x8C then @ADC_A_r('H')
      when 0x8D then @ADC_A_r('L')
      when 0x8E then @ADC_A_r('(HL)')
      when 0xCE then @ADC_A_r('UI8')

      # SUB n
      when 0x97 then @SUB_r('A')
      when 0x90 then @SUB_r('B')
      when 0x91 then @SUB_r('C')
      when 0x92 then @SUB_r('D')
      when 0x93 then @SUB_r('E')
      when 0x94 then @SUB_r('H')
      when 0x95 then @SUB_r('L')
      when 0x96 then @SUB_r('(HL)')
      when 0xD6 then @SUB_r('UI8')

      # SBC A, n
      when 0x9F then @SBC_A_r('A')
      when 0x98 then @SBC_A_r('B')
      when 0x99 then @SBC_A_r('C')
      when 0x9A then @SBC_A_r('D')
      when 0x9B then @SBC_A_r('E')
      when 0x9C then @SBC_A_r('H')
      when 0x9D then @SBC_A_r('L')
      when 0x9E then @SBC_A_r('(HL)')
      when 0xDE then @SBC_A_r('UI8')

      # AND n
      when 0xA7 then @AND_r('A')
      when 0xA0 then @AND_r('B')
      when 0xA1 then @AND_r('C')
      when 0xA2 then @AND_r('D')
      when 0xA3 then @AND_r('E')
      when 0xA4 then @AND_r('H')
      when 0xA5 then @AND_r('L')
      when 0xA6 then @AND_r('(HL)')
      when 0xE6 then @AND_r('UI8')

      # OR n
      when 0xB7 then @OR_r('A')
      when 0xB0 then @OR_r('B')
      when 0xB1 then @OR_r('C')
      when 0xB2 then @OR_r('D')
      when 0xB3 then @OR_r('E')
      when 0xB4 then @OR_r('H')
      when 0xB5 then @OR_r('L')
      when 0xB6 then @OR_r('(HL)')
      when 0xF6 then @OR_r('UI8')

      # XOR n
      when 0xAF then @XOR_r('A')
      when 0xA8 then @XOR_r('B')
      when 0xA9 then @XOR_r('C')
      when 0xAA then @XOR_r('D')
      when 0xAB then @XOR_r('E')
      when 0xAC then @XOR_r('H')
      when 0xAD then @XOR_r('L')
      when 0xAE then @XOR_r('(HL)')
      when 0xEE then @XOR_r('UI8')

      # CP n
      when 0xBF then @CP_r('A')
      when 0xB8 then @CP_r('B')
      when 0xB9 then @CP_r('C')
      when 0xBA then @CP_r('D')
      when 0xBB then @CP_r('E')
      when 0xBC then @CP_r('H')
      when 0xBD then @CP_r('L')
      when 0xBE then @CP_r('(HL)')
      when 0xFE then @CP_r('UI8')

      # INC n
      when 0x3C then @INC_r('A')
      when 0x04 then @INC_r('B')
      when 0x0C then @INC_r('C')
      when 0x14 then @INC_r('D')
      when 0x1C then @INC_r('E')
      when 0x24 then @INC_r('H')
      when 0x2C then @INC_r('L')
      when 0x34 then @INC_r('(HL)')

      # DEC n
      when 0x3D then @DEC_r('A')
      when 0x05 then @DEC_r('B')
      when 0x0D then @DEC_r('C')
      when 0x15 then @DEC_r('D')
      when 0x1D then @DEC_r('E')
      when 0x25 then @DEC_r('H')
      when 0x2D then @DEC_r('L')
      when 0x35 then @DEC_r('(HL)')

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
      when 0xC2 then @JP_nn('NZ')
      when 0xCA then @JP_nn('Z')
      when 0xD2 then @JP_nn('NC')
      when 0xDA then @JP_nn('C')

      # JP (HL)
      when 0xE9 then @JP_HL()
      # JR n
      when 0x18 then @JR_n()

      # JR cc, n
      when 0x20 then @JR_n('NZ')
      when 0x28 then @JR_n('Z')
      when 0x30 then @JR_n('NC')
      when 0x38 then @JR_n('C')

      # CALL nn
      when 0xCD then @CALL_nn()

      # CALL cc, nn
      when 0xC4 then @CALL_nn('NZ')
      when 0xCC then @CALL_nn('Z')
      when 0xD4 then @CALL_nn('NC')
      when 0xDC then @CALL_nn('C')

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
      when 0xC0 then @RET('NZ')
      when 0xC8 then @RET('Z')
      when 0xD0 then @RET('NC')
      when 0xD8 then @RET('C')

      # RETI
      when 0xD9 then @RETI()

      # Ext ops
      when 0xCB
        opcode2 = @params.UI8

        switch opcode2

          # SWAP n
          when 0x37 then @SWAP_r('A')
          when 0x30 then @SWAP_r('B')
          when 0x31 then @SWAP_r('C')
          when 0x32 then @SWAP_r('D')
          when 0x33 then @SWAP_r('E')
          when 0x34 then @SWAP_r('H')
          when 0x35 then @SWAP_r('L')
          when 0x36 then @SWAP_r('(HL)')

          # RLC n
          when 0x07 then @RLC_r('A')
          when 0x00 then @RLC_r('B')
          when 0x01 then @RLC_r('C')
          when 0x02 then @RLC_r('D')
          when 0x03 then @RLC_r('E')
          when 0x04 then @RLC_r('H')
          when 0x05 then @RLC_r('L')
          when 0x06 then @RLC_r('(HL)')

          # RL n
          when 0x17 then @RL_r('A')
          when 0x10 then @RL_r('B')
          when 0x11 then @RL_r('C')
          when 0x12 then @RL_r('D')
          when 0x13 then @RL_r('E')
          when 0x14 then @RL_r('H')
          when 0x15 then @RL_r('L')
          when 0x16 then @RL_r('(HL)')

          # RRC n
          when 0x0F then @RRC_r('A')
          when 0x08 then @RRC_r('B')
          when 0x09 then @RRC_r('C')
          when 0x0A then @RRC_r('D')
          when 0x0B then @RRC_r('E')
          when 0x0C then @RRC_r('H')
          when 0x0D then @RRC_r('L')
          when 0x0E then @RRC_r('(HL)')

          # RR n
          when 0x1F then @RR_r('A')
          when 0x18 then @RR_r('B')
          when 0x19 then @RR_r('C')
          when 0x1A then @RR_r('D')
          when 0x1B then @RR_r('E')
          when 0x1C then @RR_r('H')
          when 0x1D then @RR_r('L')
          when 0x1E then @RR_r('(HL)')

          # SLA n
          when 0x27 then @SLA_r('A')
          when 0x20 then @SLA_r('B')
          when 0x21 then @SLA_r('C')
          when 0x22 then @SLA_r('D')
          when 0x23 then @SLA_r('E')
          when 0x24 then @SLA_r('H')
          when 0x25 then @SLA_r('L')
          when 0x26 then @SLA_r('(HL)')

          # SRA n
          when 0x2F then @SRA_r('A')
          when 0x28 then @SRA_r('B')
          when 0x29 then @SRA_r('C')
          when 0x2A then @SRA_r('D')
          when 0x2B then @SRA_r('E')
          when 0x2C then @SRA_r('H')
          when 0x2D then @SRA_r('L')
          when 0x2E then @SRA_r('(HL)')

          # SRL n
          when 0x3F then @SRL_r('A')
          when 0x38 then @SRL_r('B')
          when 0x39 then @SRL_r('C')
          when 0x3A then @SRL_r('D')
          when 0x3B then @SRL_r('E')
          when 0x3C then @SRL_r('H')
          when 0x3D then @SRL_r('L')
          when 0x3E then @SRL_r('(HL)')

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

            @["#{command}_b_r"](bit, register)

      else
        throw "Unknown opcode: 0x#{opcode.toString(16)}"

    !@Breakpoints?[@params.PC]

window.CPU = CPU
