objectWithProperties = (obj) =>
  if obj.properties
    Object.defineProperties obj, obj.properties
    delete obj.properties
  obj

class CPU

  buffer: null
  memory: null
  breakpoints: null

  regs: objectWithProperties
    flags:  {}
    A: 0, B: 0, C: 0, D: 0, E: 0
    H: 0, L: 0
    PC: 0, SP: 0

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
          @flags.Z = if value & 0x80 then 1 else 0
          @flags.N = if value & 0x40 then 1 else 0
          @flags.H = if value & 0x20 then 1 else 0
          @flags.C = if value & 0x10 then 1 else 0

      AF:
        get: -> (@A << 8) + @F
        set: (value) ->
          @F = value & 0xFF
          @A = (value >> 8) & 0xFF

      BC:
        get: -> (@B << 8) + @C
        set: (value) ->
          @C = value & 0xFF
          @B = (value >> 8) & 0xFF

      DE:
        get: -> (@D << 8) + @E
        set: (value) ->
          @E = value & 0xFF
          @D = (value >> 8) & 0xFF

      HL:
        get: -> (@H << 8) + @L
        set: (value) ->
          @L = value & 0xFF
          @H = (value >> 8) & 0xFF

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

    @memory = new Array(0xFFFF + 1)

    @regs.flags =
      Z: null
      N: null
      H: null
      C: null

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

  DEC_rr: (reg, reg2) ->
    @regs[reg2] = (@regs[reg2] - 1) & 0xFF
    if @regs[reg2] == 0xFF
      @regs[reg] = (@regs[reg]- 1) & 0xFF

  INC_rr: (reg, reg2) ->
    @regs[reg2] = (@regs[reg2] + 1) & 0xFF
    if !@regs[reg2]
      @regs[reg] = (@regs[reg] + 1) & 0xFF

  doDiff: ->
    if @disassembler? and !@disassembler.disassembly[@regs.PC]?
      @disassembler.buffer = @memory;
      @disassembler.trackCodeAtAddress @regs.PC
      @disassembler.disassemble()

      @something()
      return false
    true

  # Opcodes are gathered from:
  #   - http://meatfighter.com/gameboy/GBCPUman.pdf
  #   - http://imrannazar.com/Gameboy-Z80-Opcode-Map
  #
  # As a convention, an uppercase 'N' in the function's
  # name denotes a pointer.
  #
  # rr denotes a register pair.

  INC_n: (reg) ->
    @regs[reg] = (@regs[reg] + 1) & 0xFF
    @regs.flags.Z = unless @regs[reg] then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = unless @regs[reg] & 0xF then 1 else 0

  INC_RR: (reg) ->
    @memory[@regs[reg]] = (@memory[@regs[reg]] + 1) & 0xFF
    @regs.flags.Z = unless @memory[@regs[reg]] then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = unless @memory[@regs[reg]] & 0xF then 1 else 0

  DEC_n: (reg) ->
    @regs[reg] = (@regs[reg] - 1) & 0xFF
    @regs.flags.Z = unless @regs[reg] then 1 else 0
    @regs.flags.N = 1
    @regs.flags.H = if @regs[reg] & 0xF == 0xF  then 1 else 0

  DEC_RR: (reg) ->
    @memory[@regs[reg]] = (@memory[@regs[reg]] - 1) & 0xFF
    @regs.flags.Z = unless @memory[@regs[reg]] then 1 else 0
    @regs.flags.N = 1
    @regs.flags.H = if @memory[@regs[reg]] & 0xF == 0xF  then 1 else 0

  ADD_A_n: (reg) ->
    @regs.flags.N = 0
    @regs.flags.H = ((@regs.A & 0xF) + (@regs[reg] & 0xF)) & 0x10
    @regs.flags.C = if @regs.A + @regs[reg] > 0xFF then 1 else 0
    @regs.A += @regs[reg] & 0xFF
    @regs.flags.Z = unless @regs.A then 1 else 0

  ADD_A_RR: (reg) ->
    @regs.flags.N = 0
    @regs.flags.H = ((@regs.A & 0xF) + (@memory[@regs[reg]] & 0xF)) & 0x10
    @regs.flags.C = if @regs.A + @memory[@regs[reg]] > 0xFF then 1 else 0
    @regs.A = (@regs.A + @memory[@regs[reg]]) & 0xFF
    @regs.flags.Z = unless @regs.A then 1 else 0




  #### NEW OPCODES HERE

  LD_r_n: (reg) ->
    @regs[reg] = @getUint8()

  LD_R_n: (reg) ->
    @memory[@regs[reg]] = @getUint8()

  LD_r_r2: (reg, reg2) ->
    @regs[reg] = @regs[reg2]

  LD_r_R2: (reg, reg2) ->
    @regs[reg] = @memory[@regs[reg2]]

  LD_R_r2: (reg, reg2) ->
    @memory[@regs[reg]] = @memory[reg2]

  LD_A_r: (reg) ->
    @regs.A = @regs[reg]

  LD_A_R: (reg) ->
    @regs.A = @memory[@regs[reg]]

  LD_A_NN: (reg) ->
    @regs.A = @memory[@getUint16()]

  LD_A_imm: ->
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
    n = @getUint8()

    @regs.flags.Z = 0
    @regs.flags.N = 0
    @regs.flags.H = if ((@regs.SP & 0x800) + n) & 0x1000 then 1 else 0 # Bit 11 to 12
    @regs.flags.C = if (@regs.SP + n) & 0x10000 then 1 else 0           # Bit 15 to 16

    @regs.HL = (@regs.SP + n) & 0xFFFF

  LD_NN_SP: ->
    address = @getUint16()
    @memory[address]     = @regs.SP & 0xFF
    @memory[address + 1] = (@regs.SP >> 8) & 0xFF

  PUSH_r: (reg) ->
    @regs.SP--
    @memory[@regs.SP] = @regs[reg] & 0xFF
    @regs.SP--
    @memory[@regs.SP] = (@regs[reg] >> 8) & 0xFF

  POP_r: (reg) ->
    @regs[reg] = @memory[@regs.SP] << 8
    @regs.SP++
    @regs[reg] += @memory[@regs.SP]
    @regs.SP++

  ADD_A_r: (reg) ->
    n = @regs[reg]

    @regs.flags.Z = unless (@regs.A + n) & 0xFF then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = if ((@regs.A & 0xF) + (n & 0xF)) & 0x10 then 1 else 0 # Bit 3 to 4
    @regs.flags.C = if (@regs.A + n) & 0x100 then 1 else 0                # Bit 7 to 8

    @regs.A = (@regs.A + n) & 0xFF

  ADD_A_R: (reg) ->
    n = @memory[@regs[reg]]

    @regs.flags.Z = unless (@regs.A + n) & 0xFF then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = if ((@regs.A & 0xF) + (n & 0xF)) & 0x10 then 1 else 0 # Bit 3 to 4
    @regs.flags.C = if (@regs.A + n) & 0x100 then 1 else 0                # Bit 7 to 8

    @regs.A = (@regs.A + n) & 0xFF

  ADD_A_imm: ->
    n = @getUint8()

    @regs.flags.Z = unless (@regs.A + n) & 0xFF then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = if ((@regs.A & 0xF) + (n & 0xF)) & 0x10 then 1 else 0 # Bit 3 to 4
    @regs.flags.C = if (@regs.A + n) & 0x100 then 1 else 0                # Bit 7 to 8

    @regs.A = (@regs.A + n) & 0xFF

  ADC_A_r: (reg) ->
    n  = @regs[reg]
    n += if @regs.flags.C then 1 else 0
    n &= 0xFF

    @regs.flags.Z = unless (@regs.A + n) & 0xFF then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = if ((@regs.A & 0xF) + (n & 0xF)) & 0x10 then 1 else 0 # Bit 3 to 4
    @regs.flags.C = if (@regs.A + n) & 0x100 then 1 else 0                # Bit 7 to 8

    @regs.A = (@regs.A + n) & 0xFF

  ADC_A_R: (reg) ->
    n  = @memory[@regs[reg]]
    n += if @regs.flags.C then 1 else 0
    n &= 0xFF

    @regs.flags.Z = unless (@regs.A + n) & 0xFF then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = if ((@regs.A & 0xF) + (n & 0xF)) & 0x10 then 1 else 0 # Bit 3 to 4
    @regs.flags.C = if (@regs.A + n) & 0x100 then 1 else 0                # Bit 7 to 8

    @regs.A = (@regs.A + n) & 0xFF

  ADC_A_imm: ->
    n  = @getUint8()
    n += if @regs.flags.C then 1 else 0
    n &= 0xFF

    @regs.flags.Z = unless (@regs.A + n) & 0xFF then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = if ((@regs.A & 0xF) + (n & 0xF)) & 0x10 then 1 else 0 # Bit 3 to 4
    @regs.flags.C = if (@regs.A + n) & 0x100 then 1 else 0                # Bit 7 to 8

    @regs.A = (@regs.A + n) & 0xFF

  OR_r: (reg) ->
    @regs.A |= @regs[reg]

    @regs.flags.Z = unless @regs.A then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

  OR_R: (reg) ->
    @regs.A |= @memory[@regs[reg]]

    @regs.flags.Z = unless @regs.A then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

  OR_imm: ->
    @regs.A |= @getUint8()

    @regs.flags.Z = unless @regs.A then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

  XOR_r: (reg) ->
    @regs.A ^= @regs[reg]

    @regs.flags.Z = unless @regs.A then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

  XOR_R: (reg) ->
    @regs.A ^= @memory[@regs[reg]]

    @regs.flags.Z = unless @regs.A then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

  XOR_imm: ->
    @regs.A ^= @getUint8()

    @regs.flags.Z = unless @regs.A then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

  SUB_r: (reg) ->
    n = @regs.A - @regs[reg]

    @regs.flags.Z = unless n & 0xFF then 1 else 0
    @regs.flags.N = 1
    @regs.flags.H = if (@regs.A & 0xF) < (@regs[reg] & 0xF) then 1 else 0
    @regs.flags.C = if @regs.A < @regs[reg] then 1 else 0

    @regs.A = (@regs.A - @regs[reg]) & 0xFF

  SUB_imm: ->
    n = @getUint8()

    @regs.flags.Z = unless (@regs.A - n) & 0xFF then 1 else 0
    @regs.flags.N = 1
    @regs.flags.H = if (@regs.A & 0xF) < (n & 0xF) then 1 else 0
    @regs.flags.C = if @regs.A < n then 1 else 0

    @regs.A = (@regs.A - n) & 0xFF

  SBC_A_r: (reg) ->
    toSub = @regs[reg] + if @regs.flags.C then 1 else 0

    n = @regs.A - toSub

    @regs.flags.Z = unless n & 0xFF then 1 else 0
    @regs.flags.N = 1
    @regs.flags.H = if (@regs.A & 0xF) < (toSub & 0xF) then 1 else 0
    @regs.flags.C = if @regs.A < toSub then 1 else 0

    @regs.A = (@regs.A - toSub) & 0xFF

  SBC_A_imm: ->
    n = @getUint8()
    n += if @regs.flags.C then 1 else 0

    @regs.flags.Z = unless (@regs.A - n) & 0xFF then 1 else 0
    @regs.flags.N = 1
    @regs.flags.H = if (@regs.A & 0xF) < (n & 0xF) then 1 else 0
    @regs.flags.C = if @regs.A < n then 1 else 0

    @regs.A = (@regs.A - n) & 0xFF

  SRL_r: (reg) ->
    @regs.flags.Z = unless @regs[reg] then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = @regs[reg] & 1
    @regs[reg] = @regs[reg] >> 1

  RR_r: (reg) ->
    newC = @regs[reg] & 1
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs[reg] = ((@regs[reg] >> 1) + @regs.flags.C) & 0xFF
    @regs.flags.C = newC
    @regs.flags.Z = if @regs[reg] == 0 then 1 else 0

  ADD_HL_r: (reg) ->
    @regs.flags.N = 0
    @regs.flags.H = if (@regs.HL + @regs[reg]) & 0x800 then 1 else 0
    @regs.flags.C = if ((@regs.HL & 0x7FF) + (@regs[reg] & 0x7FF)) & 0x8000 then 1 else 0
    @regs.HL = (@regs.HL + @regs[reg]) & 0xFFFF

  SWAP_r: (reg) ->
    tmp = @regs[reg] & 0xF
    @regs[reg] = @regs[reg] >> 4
    @regs[reg] |= (tmp << 4)
    @regs.flags.Z = unless @regs[reg] then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0


  executeOpcode: ->
    opcode = @getUint8()
    unless opcode?
      return false


    switch opcode

      when 0x1F then @RR_r('A')

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
      when 0x3E then @LD_A_imm()

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
      when 0xC6 then @ADD_A_imm()

      # ADC A, n
      when 0x8F then @ADC_A_r('A')
      when 0x88 then @ADC_A_r('B')
      when 0x89 then @ADC_A_r('C')
      when 0x8A then @ADC_A_r('D')
      when 0x8B then @ADC_A_r('E')
      when 0x8C then @ADC_A_r('H')
      when 0x8D then @ADC_A_r('L')
      when 0x8E then @ADC_A_R('HL')
      when 0xCE then @ADC_A_imm()

      # SUB n
      when 0x97 then @SUB_r('A')
      when 0x90 then @SUB_r('B')
      when 0x91 then @SUB_r('C')
      when 0x92 then @SUB_r('D')
      when 0x93 then @SUB_r('E')
      when 0x94 then @SUB_r('H')
      when 0x95 then @SUB_r('L')
      when 0x96 then @SUB_r('HL')
      when 0xD6 then @SUB_imm()

      # SBC A, n
      when 0x9F then @SBC_A_r('A')
      when 0x98 then @SBC_A_r('B')
      when 0x99 then @SBC_A_r('C')
      when 0x9A then @SBC_A_r('D')
      when 0x9B then @SBC_A_r('E')
      when 0x9C then @SBC_A_r('H')
      when 0x9D then @SBC_A_r('L')
      when 0x9E then @SBC_A_r('HL')
      when 0xDE then @SBC_A_imm()

      # OR n
      when 0xB7 then @OR_r('A')
      when 0xB0 then @OR_r('B')
      when 0xB1 then @OR_r('C')
      when 0xB2 then @OR_r('D')
      when 0xB3 then @OR_r('E')
      when 0xB4 then @OR_r('H')
      when 0xB5 then @OR_r('L')
      when 0xB6 then @OR_R('HL')
      when 0xF6 then @OR_imm()

      # XOR n
      when 0xAF then @XOR_r('A')
      when 0xA8 then @XOR_r('B')
      when 0xA9 then @XOR_r('C')
      when 0xAA then @XOR_r('D')
      when 0xAB then @XOR_r('E')
      when 0xAC then @XOR_r('H')
      when 0xAD then @XOR_r('L')
      when 0xAE then @XOR_R('HL')
      when 0xEE then @XOR_imm()

      # INC BC
      when 0x03 then @INC_rr('B', 'C')

      # CP (HL)
      when 0xBE
        test = @regs.A - @memory[@regs.HL]
        @regs.flags.Z = unless test then 1 else 0
        @regs.flags.N = 1

      # DI
      when 0xF3
        console.log 'DI'


      # INC n
      when 0x3C then @INC_n('A')
      when 0x04 then @INC_n('B')
      when 0x0C then @INC_n('C')
      when 0x14 then @INC_n('D')
      when 0x1C then @INC_n('E')
      when 0x24 then @INC_n('H')
      when 0x2C then @INC_n('L')
      when 0x34 then @INC_RR('HL')

      # DEC n
      when 0x3D then @DEC_n('A')
      when 0x05 then @DEC_n('B')
      when 0x0D then @DEC_n('C')
      when 0x15 then @DEC_n('D')
      when 0x1D then @DEC_n('E')
      when 0x25 then @DEC_n('H')
      when 0x2D then @DEC_n('L')
      when 0x35 then @DEC_RR('HL')

      when 0xFB then console.log 'EI'

      # ADD HL, n
      when 0x09 then @ADD_HL_r('BC')
      when 0x19 then @ADD_HL_r('DE')
      when 0x29 then @ADD_HL_r('HL')
      when 0x39 then @ADD_HL_r('SP')

      # SUB n, A
      when 0x97
        @regs.A -= @regs.A

      # AND #
      when 0xE6
        @regs.A = @regs.A & @getUint8()
        @regs.flags.Z = if @regs.A == 0 then 1 else 0
        @regs.flags.N = 0
        @regs.flags.H = 1
        @regs.flags.C = 0

      when 0x00 # NOP
        console.log 'nop'

      # JR NC, n
      when 0x30
        address = @getRelInt8JmpAddress()
        unless @regs.flags.C
          @regs.PC = address
          return false unless @doDiff()

      # JR C, n
      when 0x38
        address = @getRelInt8JmpAddress()
        if @regs.flags.C
          @regs.PC = address
          return false unless @doDiff()

      # JP NZ, nn
      when 0xC2
        address = @getUint16()
        unless @regs.flags.Z
          @regs.PC = address
          return false unless @doDiff()

      # JP nn
      when 0xC3
        @regs.PC = @getUint16()
        return false unless @doDiff()

      # JP (HL)
      when 0xE9
        @regs.PC = @regs.HL
        return false unless @doDiff()
      
      # RLCA
      when 0x07
        @regs.A = @regs.A << 1
        @regs.flags.C = if @regs.A & 0x100 then 1 else 0
        @regs.A = @regs.A & 0xFF
        @regs.flags.N = 0
        @regs.flags.H = 0

      # # # # # #
      # Old implementations
      # # # # # #


      # XOR A
      when 0xAF
        @regs.A ^= @regs.A
        @regs.flags.Z = @regs.A == 0
        @regs.flags.N = 0
        @regs.flags.H = 0
        @regs.flags.C = 0

      # JR NZ, *
      when 0x20
        address = @getRelInt8JmpAddress()
        unless @regs.flags.Z
          @regs.PC = address
          return false unless @doDiff()


      # JR Z, *
      when 0x28
        address = @getRelInt8JmpAddress()
        if @regs.flags.Z
          @regs.PC = address
          return false unless @doDiff()

      # JR n
      when 0x18
        @regs.PC = @getRelInt8JmpAddress()
        return false unless @doDiff()

      # SUB B
      when 0x90
        @regs.A -= @regs.B

      # INC C
      when 0x0C
        @regs.C++
        @regs.flags.Z == @regs.C == 0
        @regs.flags.N = 0
        @regs.flags.H = ((@regs.C >> 3) & 1) == 1

      # CALL nn
      when 0xCD
        address = @getUint16()
        @PUSH_r('PC')
        @regs.PC = address
        return false unless @doDiff()

      # CALL NZ, nn
      when 0xC4
        address = @getUint16()
        unless @regs.flags.Z
          @PUSH_r('PC')
          @regs.PC = address
          return false unless @doDiff()

      # RLA
      when 0x17
        newC= @regs.A >> 7
        @regs.flags.N = 0
        @regs.flags.H = 0
        @regs.A = ((@regs.A << 1) + @regs.flags.C) & 0xFF
        @regs.flags.C = newC
        @regs.flags.Z = if @regs.A == 0 then 1 else 0

      when 0x9
        n = @regs.BC

        @regs.flags.Z = 0
        @regs.flags.N = 0
        @regs.flags.H = if ((@regs.SP & 0x800) + (n & 0x800)) & 0x1000 then 1 else 0 # Bit 11 to 12
        @regs.flags.C = if (@regs.SP + n) & 0x10000 then 1 else 0           # Bit 15 to 16

        @regs.HL = (@regs.HL + n) & 0xFFFF

      when 0x19
        n = @regs.DE

        @regs.flags.Z = 0
        @regs.flags.N = 0
        @regs.flags.H = if ((@regs.SP & 0x800) + (n & 0x800)) & 0x1000 then 1 else 0 # Bit 11 to 12
        @regs.flags.C = if (@regs.SP + n) & 0x10000 then 1 else 0           # Bit 15 to 16

        @regs.HL = (@regs.HL + n) & 0xFFFF

      # DEC B
      when 0x05
        @regs.B--
        @regs.flags.Z = if @regs.B == 0 then 1 else 0
        @regs.flags.N = 1
        #@regs.flags.H = ?? I don't understand this flag yet :)

      # DEC A
      when 0x3D
        @regs.A--
        @regs.flags.Z = if @regs.A == 0 then 1 else 0
        @regs.flags.N = 1
        #@regs.flags.H = ?? I don't understand this flag yet :)

      # DEC C
      when 0x0D
        @regs.C--
        @regs.flags.Z = if @regs.C == 0 then 1 else 0
        @regs.flags.N = 1
        #@regs.flags.H = ?? I don't understand this flag yet :)

      # INC HL
      when 0x23
        @regs.L = (@regs.L + 1) & 255
        if !@regs.L
          @regs.H = (@regs.H + 1) & 255

      # INC DE
      when 0x13
        @regs.E = (@regs.E + 1) & 255
        if !@regs.E
          @regs.D = (@regs.D + 1) & 255

      # RET
      when 0xC9
        @POP_r('PC')
        return false unless @doDiff()

      # RET Z
      when 0xC8
        if @regs.flags.Z
          @POP_r('PC')
          return false unless @doDiff()

      # RET C
      when 0xD8
        if @regs.flags.C
          @POP_r('PC')
          return false unless @doDiff()

      # RET NC
      when 0xD0
        unless @regs.flags.C
          @POP_r('PC')
          return false unless @doDiff()

      # CP #
      when 0xFE
        data = @getUint8()
        result = @regs.A - data
        @regs.flags.Z = if result == 0 then 1 else 0
        @regs.flags.N = 1
        #flags.H ??
        @regs.flags.C = if @regs.A < data then 1 else 0

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
          # when 0x36 then @SWAP_r('(HL)')

          # BIT 7, H
          when 0x7C
            @regs.flags.Z = (@regs.H >> 7) == 0
            @booya = @regs.H
            @regs.flags.N = 0
            @regs.flags.H = 1

          # RL C
          when 0x11
            newC = @regs.C >> 7
            @regs.flags.N = 0
            @regs.flags.H = 0
            @regs.C = ((@regs.C << 1) + @regs.flags.C) & 0xFF
            @regs.flags.C = newC
            @regs.flags.Z = if @regs.C == 0 then 1 else 0


          # RR n
          when 0x1F then @RR_r('A')
          when 0x18 then @RR_r('B')
          when 0x19 then @RR_r('C')
          when 0x1A then @RR_r('D')
          when 0x1B then @RR_r('E')
          when 0x1C then @RR_r('H')
          when 0x1D then @RR_r('L')
          when 0x1E then @RR_r('HL')

          # SRL n
          when 0x3F then @SRL_r('A')
          when 0x38 then @SRL_r('B')
          when 0x39 then @SRL_r('C')
          when 0x3A then @SRL_r('D')
          when 0x3B then @SRL_r('E')
          when 0x3C then @SRL_r('H')
          when 0x3D then @SRL_r('L')
          when 0x3E then @SRL_r('HL')

          else
            throw "Unknown opcode: 0xCB 0x#{opcode2.toString(16)}"

      else
        throw "Unknown opcode: 0x#{opcode.toString(16)}"

    if @breakpoints?[@regs.PC]
      return false
    true



window.CPU = CPU
