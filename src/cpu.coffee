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
          @flags.Z = if value & 0x80 then 1 else 0
          @flags.N = if value & 0x40 then 1 else 0
          @flags.H = if value & 0x20 then 1 else 0
          @flags.C = if value & 0x10 then 1 else 0

  buffer: null
  memory: null
  breakpoints: null
  regs: new Regs()

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

  doDiff: ->
    if @disassembler? and !@disassembler.disassembly[@regs.PC]?
      @disassembler.buffer = @memory;
      @disassembler.trackCodeAtAddress @regs.PC
      @disassembler.disassemble()

      @something()
      true
    true

  # Opcodes are gathered from:
  #   - http://meatfighter.com/gameboy/GBCPUman.pdf
  #   - http://imrannazar.com/Gameboy-Z80-Opcode-Map
  #
  # As a convention, an uppercase 'N' in the function's
  # name denotes a pointer.
  #
  # rr denotes a register pair.

  LD_r_n: (reg) ->
    @regs[reg] = @getUint8()

  LD_r_r2: (reg, reg2) ->
    @regs[reg] = @regs[reg2]

  LD_r_R2: (reg, reg2) ->
    @regs[reg] = @memory[@regs[reg2]]

  LD_A_r: (reg) ->
    @regs.A = @regs[reg]

  LD_A_R: (reg) ->
    @regs.A = @memory[@regs[reg]]

  LD_A_NN: (reg) ->
    @regs.A = @memory[@getUint16()]

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

  ADD_A_imm: ->
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

  ADC_A_imm: ->
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

  SUB_imm: ->
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

  SBC_A_imm: ->
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

  AND_imm: (reg) ->
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

  OR_imm: ->
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

  XOR_imm: ->
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

  CP_imm: (reg) ->
    n    = @getUint8()
    diff = (@regs.A - n) & 0xFF

    @regs.flags.Z = diff == 0
    @regs.flags.N = 1
    @regs.flags.H = (@regs.A & 0xF) < (n & 0xF)
    @regs.flags.C = @regs.A < n

















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
    @regs.flags.H = if (@regs[reg] & 0xF) == 0xF then 1 else 0

  DEC_RR: (reg) ->    
    @memory[@regs[reg]] = (@memory[@regs[reg]] - 1) & 0xFF
    @regs.flags.Z = unless @memory[@regs[reg]] then 1 else 0
    @regs.flags.N = 1
    @regs.flags.H = if (@memory[@regs[reg]] & 0xF) == 0xF then 1 else 0

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

  LD_R_n: (reg) ->
    @memory[@regs[reg]] = @getUint8()

  LD_R_r2: (reg, reg2) ->
    @memory[@regs[reg]] = @regs[reg2]

  LD_A_imm: ->
    @regs.A = @getUint8()




  SRL_r: (reg) ->
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = @regs[reg] & 1
    @regs[reg] = @regs[reg] >> 1
    @regs.flags.Z = unless @regs[reg] then 1 else 0

  SRL_R: (reg) ->
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = @memory[@regs[reg]] & 1
    @memory[@regs[reg]] = @memory[@regs[reg]] >> 1
    @regs.flags.Z = unless @memory[@regs[reg]] then 1 else 0

  RL_r: (reg) ->
    newC = (@regs[reg] >> 7) & 0x1
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs[reg] = ((@regs[reg] << 1) + (@regs.flags.C)) & 0xFF
    @regs.flags.C = newC
    @regs.flags.Z = if @regs[reg] == 0 then 1 else 0

  RL_R: (reg) ->
    newC = (@memory[@regs[reg]] >> 7) & 0x1
    @regs.flags.N = 0
    @regs.flags.H = 0
    @memory[@regs[reg]] = ((@memory[@regs[reg]] << 1) + (@regs.flags.C)) & 0xFF
    @regs.flags.C = newC
    @regs.flags.Z = if @memory[@regs[reg]] == 0 then 1 else 0

  RR_r: (reg) ->
    newC = @regs[reg] & 1
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs[reg] = ((@regs[reg] >> 1) | (@regs.flags.C << 7)) & 0xFF
    @regs.flags.C = newC
    @regs.flags.Z = unless @regs[reg] then 1 else 0

  RR_R: (reg) ->
    newC = @memory[@regs[reg]] & 1
    @regs.flags.N = 0
    @regs.flags.H = 0
    @memory[@regs[reg]] = ((@memory[@regs[reg]] >> 1) | (@regs.flags.C << 7)) & 0xFF
    @regs.flags.C = newC
    @regs.flags.Z = unless @memory[@regs[reg]] then 1 else 0

  ADD_HL_r: (reg) ->
    @regs.flags.N = 0
    @regs.flags.C = if ((@regs.HL & 0xFFFF) + (@regs[reg] & 0xFFFF)) & 0x10000 then 1 else 0
    @regs.flags.H = if ((@regs.HL & 0xFFF) + (@regs[reg] & 0xFFF)) & 0x1000 then 1 else 0
    @regs.HL = (@regs.HL + @regs[reg]) & 0xFFFF

  SWAP_r: (reg) ->
    tmp = @regs[reg] & 0xF
    @regs[reg] = @regs[reg] >> 4
    @regs[reg] |= (tmp << 4)
    @regs.flags.Z = unless @regs[reg] then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

  SWAP_R: (reg) ->
    tmp = @memory[@regs[reg]] & 0xF
    @memory[@regs[reg]] = @memory[@regs[reg]] >> 4
    @memory[@regs[reg]] |= (tmp << 4)
    @regs.flags.Z = unless @memory[@regs[reg]] then 1 else 0
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.C = 0

  RLC_r: (reg) ->
    newC= @regs[reg] >> 7
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs[reg] = ((@regs[reg] << 1) | newC) & 0xFF
    @regs.flags.C = newC
    @regs.flags.Z = unless @regs[reg] then 1 else 0

  RLC_R: (reg) ->
    newC= @memory[@regs[reg]] >> 7
    @regs.flags.N = 0
    @regs.flags.H = 0
    @memory[@regs[reg]] = ((@memory[@regs[reg]] << 1) | newC) & 0xFF
    @regs.flags.C = newC
    @regs.flags.Z = unless @memory[@regs[reg]] then 1 else 0

  RRC_r: (reg) ->
    newC= @regs[reg] & 0x1
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs[reg] = ((@regs[reg] >> 1) | (newC << 7)) & 0xFF
    @regs.flags.C = newC
    @regs.flags.Z = unless @regs[reg] then 1 else 0

  RRC_R: (reg) ->
    newC= @memory[@regs[reg]] & 0x1
    @regs.flags.N = 0
    @regs.flags.H = 0
    @memory[@regs[reg]] = ((@memory[@regs[reg]] >> 1) | (newC << 7)) & 0xFF
    @regs.flags.C = newC
    @regs.flags.Z = unless @memory[@regs[reg]] then 1 else 0

  SLA_r: (reg) ->
    @regs[reg] = @regs[reg] << 1
    @regs.flags.C = if @regs[reg] & 0x100 then 1 else 0
    @regs[reg] &= 0xFF
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.Z = unless @regs[reg] then 1 else 0

  SLA_R: (reg) ->
    @memory[@regs[reg]] = @memory[@regs[reg]] << 1
    @regs.flags.C = if @memory[@regs[reg]] & 0x100 then 1 else 0
    @memory[@regs[reg]] &= 0xFF
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.Z = unless @memory[@regs[reg]] then 1 else 0

  SRA_r: (reg) ->
    @regs.flags.C = @regs[reg] & 1
    msb = @regs[reg] >> 7
    @regs[reg] = ((msb << 7) | (@regs[reg] >> 1)) & 0xFF
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.Z = unless @regs[reg] then 1 else 0

  SRA_R: (reg) ->
    @regs.flags.C = @memory[@regs[reg]] & 1
    msb = @memory[@regs[reg]] >> 7
    @memory[@regs[reg]] = ((msb << 7) | (@memory[@regs[reg]] >> 1)) & 0xFF
    @regs.flags.N = 0
    @regs.flags.H = 0
    @regs.flags.Z = unless @memory[@regs[reg]] then 1 else 0

  RST_n: ->


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
      when 0x96 then @SUB_R('HL')
      when 0xD6 then @SUB_imm()

      # SBC A, n
      when 0x9F then @SBC_A_r('A')
      when 0x98 then @SBC_A_r('B')
      when 0x99 then @SBC_A_r('C')
      when 0x9A then @SBC_A_r('D')
      when 0x9B then @SBC_A_r('E')
      when 0x9C then @SBC_A_r('H')
      when 0x9D then @SBC_A_r('L')
      when 0x9E then @SBC_A_R('HL')
      when 0xDE then @SBC_A_imm()

      # AND n
      when 0xA7 then @AND_r('A')
      when 0xA0 then @AND_r('B')
      when 0xA1 then @AND_r('C')
      when 0xA2 then @AND_r('D')
      when 0xA3 then @AND_r('E')
      when 0xA4 then @AND_r('H')
      when 0xA5 then @AND_r('L')
      when 0xA6 then @AND_R('HL')
      when 0xE6 then @AND_imm()

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

      # CP n
      when 0xBF then @CP_r('A')
      when 0xB8 then @CP_r('B')
      when 0xB9 then @CP_r('C')
      when 0xBA then @CP_r('D')
      when 0xBB then @CP_r('E')
      when 0xBC then @CP_r('H')
      when 0xBD then @CP_r('L')
      when 0xBE then @CP_R('HL')
      when 0xFE then @CP_imm()

      # STOP
      when 0x10
        console.log 'STOP'

      # INC BC
      when 0x03 then @regs.BC++

      # DAA
      when 0x27
        # Based on: http://forums.nesdev.com/viewtopic.php?t=9088
        a = @regs.A

        unless @regs.flags.N
          if @regs.flags.H || (a & 0xF) > 9
            a += 0x06

          if @regs.flags.C || (a > 0x9F)
            a += 0x60
        else
          if @regs.flags.H
            a = (a - 6) & 0xFF

          if @regs.flags.C
            a -= 0x60

        if (a & 0x100) == 0x100
          @regs.flags.C = 1

        @regs.flags.H = 0

        a &= 0xFF
        @regs.A = a
        @regs.flags.Z = unless @regs.A then 1 else 0

      # CPL
      when 0x2F
        @regs.A ^= 0xFF
        @regs.flags.N = 1
        @regs.flags.H = 1

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

      # INC SP
      when 0x33
        @regs.SP = (@regs.SP + 1) & 0xFFFF

      # DEC BC
      when 0x0B
        @regs.BC--

      # DEC DE
      when 0x1B
        @regs.DE--

      # DEC HL
      when 0x2B
        @regs.HL--

      # DEC SP
      when 0x3B
        @regs.SP = (@regs.SP - 1) & 0xFFFF

      # ADD SP, n
      when 0xE8
        n = @getInt8()

        @regs.flags.C = if ((@regs.SP & 0xFF) + (n & 0xFF)) & 0x100 then 1 else 0
        @regs.flags.H = if ((@regs.SP & 0xF) + (n & 0xF)) & 0x10 then 1 else 0
        @regs.flags.Z = 0
        @regs.flags.N = 0

        @regs.SP = (@regs.SP + n) & 0xFFFF

      when 0x1F
        @RR_r('A')
        @regs.flags.Z = 0

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

      when 0x00 # NOP
        boo = 1
        #console.log 'nop'

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

      # JP Z, nn
      when 0xCA
        address = @getUint16()
        if @regs.flags.Z
          @regs.PC = address
          return false unless @doDiff()

      # JP NC, n
      when 0xD2
        address = @getUint16()
        unless @regs.flags.C
          @regs.PC = address
          return false unless @doDiff()

      # JP C, n
      when 0xDA
        address = @getUint16()
        if @regs.flags.C
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

      # # # # # #
      # Old implementations
      # # # # # #


      # XOR A
      when 0xAF
        @regs.A ^= @regs.A
        @regs.flags.Z = unless @regs.A then 1 else 0
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

      # CALL NC, nn
      when 0xD4
        address = @getUint16()
        unless @regs.flags.C
          @PUSH_r('PC')
          @regs.PC = address
          return false unless @doDiff()

      # CALL C, nn
      when 0xDC
        address = @getUint16()
        if @regs.flags.C
          @PUSH_r('PC')
          @regs.PC = address
          return false unless @doDiff()

      # CALL Z, nn
      when 0xCC
        address = @getUint16()
        if @regs.flags.Z
          @PUSH_r('PC')
          @regs.PC = address
          return false unless @doDiff()

      # RLCA
      when 0x07
        newC= @regs.A >> 7
        @regs.flags.N = 0
        @regs.flags.H = 0
        @regs.A = ((@regs.A << 1) | newC) & 0xFF
        @regs.flags.C = newC
        @regs.flags.Z = 0

      # RLA
      when 0x17
        newC= @regs.A >> 7
        @regs.flags.N = 0
        @regs.flags.H = 0
        @regs.A = ((@regs.A << 1) | @regs.flags.C) & 0xFF
        @regs.flags.C = newC
        @regs.flags.Z = 0

      # RRCA
      when 0x0F
        newC= @regs.A & 0x1
        @regs.flags.N = 0
        @regs.flags.H = 0
        @regs.A = ((@regs.A >> 1) | (newC << 7)) & 0xFF
        @regs.flags.C = newC
        @regs.flags.Z = 0

      # # INC HL
      when 0x23
        @regs.HL++

      # # INC DE
      when 0x13
        @regs.DE++

      # RET
      when 0xC9
        @POP_r('PC')
        return false unless @doDiff()

      # RETI
      when 0xD9
        @POP_r('PC')
        return false unless @doDiff()

      # RST n
      when 0xC7 then @RST_n(0x00)
      when 0xCF then @RST_n(0x08)
      when 0xD7 then @RST_n(0x10)
      when 0xDF then @RST_n(0x18)
      when 0xE7 then @RST_n(0x20)
      when 0xEF then @RST_n(0x28)
      when 0xF7 then @RST_n(0x30)
      when 0xFF then @RST_n(0x38)

      # RET Z
      when 0xC8
        if @regs.flags.Z
          @POP_r('PC')
          return false unless @doDiff()

      # RET NZ
      when 0xC0
        unless @regs.flags.Z
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

      # SCF
      when 0x37
        @regs.flags.N = 0
        @regs.flags.H = 0
        @regs.flags.C = 1

      # CCF
      when 0x3F
        @regs.flags.C = if @regs.flags.C then 0 else 1
        @regs.flags.N = 0
        @regs.flags.H = 0

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
          when 0x1E then @RR_R('HL')

          # RL n
          when 0x17 then @RL_r('A')
          when 0x10 then @RL_r('B')
          when 0x11 then @RL_r('C')
          when 0x12 then @RL_r('D')
          when 0x13 then @RL_r('E')
          when 0x14 then @RL_r('H')
          when 0x15 then @RL_r('L')
          when 0x16 then @RL_R('HL')

          # RLC n
          when 0x07 then @RLC_r('A')
          when 0x00 then @RLC_r('B')
          when 0x01 then @RLC_r('C')
          when 0x02 then @RLC_r('D')
          when 0x03 then @RLC_r('E')
          when 0x04 then @RLC_r('H')
          when 0x05 then @RLC_r('L')
          when 0x06 then @RLC_R('HL')

          # SLA n
          when 0x27 then @SLA_r('A')
          when 0x20 then @SLA_r('B')
          when 0x21 then @SLA_r('C')
          when 0x22 then @SLA_r('D')
          when 0x23 then @SLA_r('E')
          when 0x24 then @SLA_r('H')
          when 0x25 then @SLA_r('L')
          when 0x26 then @SLA_R('HL')


          # RRC n
          when 0x0F then @RRC_r('A')
          when 0x08 then @RRC_r('B')
          when 0x09 then @RRC_r('C')
          when 0x0A then @RRC_r('D')
          when 0x0B then @RRC_r('E')
          when 0x0C then @RRC_r('H')
          when 0x0D then @RRC_r('L')
          when 0x0E then @RRC_R('HL')

          # SRL n
          when 0x3F then @SRL_r('A')
          when 0x38 then @SRL_r('B')
          when 0x39 then @SRL_r('C')
          when 0x3A then @SRL_r('D')
          when 0x3B then @SRL_r('E')
          when 0x3C then @SRL_r('H')
          when 0x3D then @SRL_r('L')
          when 0x3E then @SRL_R('HL')

          # SRA n
          when 0x2F then @SRA_r('A')
          when 0x28 then @SRA_r('B')
          when 0x29 then @SRA_r('C')
          when 0x2A then @SRA_r('D')
          when 0x2B then @SRA_r('E')
          when 0x2C then @SRA_r('H')
          when 0x2D then @SRA_r('L')
          when 0x2E then @SRA_R('HL')

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

            if register == '(HL)'
              if command == 'BIT'
                @regs.flags.Z = unless (@memory[@regs.HL] & (1 << bit)) then 1 else 0
                @regs.flags.N = 0
                @regs.flags.H = 1
              else if command == 'SET'
                @memory[@regs.HL] = @memory[@regs.HL] | (1 << bit)
              else if command == 'RES'
                @memory[@regs.HL] = @memory[@regs.HL] & ~(1 << bit)
            else
              if command == 'BIT'
                @regs.flags.Z = unless (@regs[register] & (1 << bit)) then 1 else 0
                @regs.flags.N = 0
                @regs.flags.H = 1
              else if command == 'SET'
                @regs[register] = @regs[register] | (1 << bit)
              else if command == 'RES'
                @regs[register] = @regs[register] & ~(1 << bit)

      else
        throw "Unknown opcode: 0x#{opcode.toString(16)}"

    if @breakpoints?[@regs.PC]
      return false
    true



window.CPU = CPU
