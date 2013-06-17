objectWithProperties = (obj) ->
  if obj.properties
    Object.defineProperties obj, obj.properties
    delete obj.properties
  obj

class CPU
  buffer: null
  flags:  null
  memory: null
  breakpoints: null

  regs: objectWithProperties
    A: 0, B: 0, C: 0, D: 0, E: 0
    H: 0, L: 0
    F: 0
    PC: 0, SP: 0

    properties:
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

    @flags =
      Z: null
      N: null
      H: null
      C: null

  # Unsigned

  getUint8: ->
    @buffer[@regs.PC++]

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
    @flags.Z = unless @regs[reg] then 1 else 0
    @flags.N = 0
    @flags.H = unless @regs[reg] & 0xF then 1 else 0

  INC_RR: (reg) ->
    @memory[@regs[reg]] = (@memory[@regs[reg]] + 1) & 0xFF
    @flags.Z = unless @memory[@regs[reg]] then 1 else 0
    @flags.N = 0
    @flags.H = unless @memory[@regs[reg]] & 0xF then 1 else 0

  DEC_n: (reg) ->
    @regs[reg] = (@regs[reg] - 1) & 0xFF
    @flags.Z = unless @regs[reg] then 1 else 0
    @flags.N = 1
    @flags.H = if @regs[reg] & 0xF == 0xF  then 1 else 0

  DEC_RR: (reg) ->
    @memory[@regs[reg]] = (@memory[@regs[reg]] - 1) & 0xFF
    @flags.Z = unless @memory[@regs[reg]] then 1 else 0
    @flags.N = 1
    @flags.H = if @memory[@regs[reg]] & 0xF == 0xF  then 1 else 0

  ADD_A_n: (reg) ->
    @flags.N = 0
    @flags.H = ((@regs.A & 0xF) + (@regs[reg] & 0xF)) & 0x10
    @flags.C = if @regs.A + @regs[reg] > 0xFF then 1 else 0
    @regs.A += @regs[reg] & 0xFF
    @flags.Z = unless @regs.A then 1 else 0

  ADD_A_RR: (reg) ->
    @flags.N = 0
    @flags.H = ((@regs.A & 0xF) + (@memory[@regs[reg]] & 0xF)) & 0x10
    @flags.C = if @regs.A + @memory[@regs[reg]] > 0xFF then 1 else 0
    @regs.A = (@regs.A + @memory[@regs[reg]]) & 0xFF
    @flags.Z = unless @regs.A then 1 else 0




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

    @flags.Z = 0
    @flags.N = 0
    @flags.H = if ((@regs.SP & 0x800) + n) & 0x1000 then 1 else 0 # Bit 11 to 12
    @flags.C = if (@regs.SP + n) & 0x1000 then 1 else 0           # Bit 15 to 16

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

    @flags.Z = unless (@regs.A + n) & 0xFF then 1 else 0
    @flags.N = 0
    @flags.H = if ((@regs.A & 0xF) + (n & 0xF)) & 0x10 then 1 else 0 # Bit 3 to 4
    @flags.C = if (@regs.A + n) & 0x100 then 1 else 0                # Bit 7 to 8

    @regs.A = (@regs.A + n) & 0xFF

  ADD_A_R: (reg) ->
    n = @memory[@regs[reg]]

    @flags.Z = unless (@regs.A + n) & 0xFF then 1 else 0
    @flags.N = 0
    @flags.H = if ((@regs.A & 0xF) + (n & 0xF)) & 0x10 then 1 else 0 # Bit 3 to 4
    @flags.C = if (@regs.A + n) & 0x100 then 1 else 0                # Bit 7 to 8

    @regs.A = (@regs.A + n) & 0xFF

  ADD_A_imm: ->
    n = @getUint8()

    @flags.Z = unless (@regs.A + n) & 0xFF then 1 else 0
    @flags.N = 0
    @flags.H = if ((@regs.A & 0xF) + (n & 0xF)) & 0x10 then 1 else 0 # Bit 3 to 4
    @flags.C = if (@regs.A + n) & 0x100 then 1 else 0                # Bit 7 to 8

    @regs.A = (@regs.A + n) & 0xFF

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





      # INC BC
      when 0x03 then @INC_rr('B', 'C')

      # CP (HL)
      when 0xBE
        test = @regs.A - @memory[@regs.HL]
        @flags.Z = unless test then 1 else 0
        @flags.N = 1

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

      # SUB n, A
      when 0x97
        @regs.A -= @regs.A

      # AND #
      when 0xE6
        @regs.A = @regs.A & @getUint8()
        @flags.Z = if @regs.A == 0 then 1 else 0
        @flags.N = 0
        @flags.H = 1
        @flags.C = 0

      when 0x00 # NOP
        console.log 'nop'

      # JP NZ, nn
      when 0xC2
        address = @getUint16()
        unless @flags.Z
          @regs.PC = address

      # JP nn
      when 0xC3
        @regs.PC = @getUint16()
      
      # RLCA
      when 0x07
        @regs.A = @regs.A << 1
        @flags.C = if @regs.A & 0x100 then 1 else 0
        @regs.A = @regs.A & 0xFF
        @flags.N = 0
        @flags.H = 0

      # # # # # #
      # Old implementations
      # # # # # #


      # XOR A
      when 0xAF
        @regs.A ^= @regs.A
        @flags.Z = @regs.A == 0
        @flags.N = 0
        @flags.H = 0
        @flags.C = 0

      # JR NZ, *
      when 0x20
        address = @getRelInt8JmpAddress()
        unless @flags.Z
          @regs.PC = address

      # JR Z, *
      when 0x28
        address = @getRelInt8JmpAddress()
        if @flags.Z
          @regs.PC = address

      # JR n
      when 0x18
        @regs.PC = @getRelInt8JmpAddress()

      # SUB B
      when 0x90
        @regs.A -= @regs.B

      # INC C
      when 0x0C
        @regs.C++
        @flags.Z == @regs.C == 0
        @flags.N = 0
        @flags.H = ((@regs.C >> 3) & 1) == 1

      # CALL nn
      when 0xCD
        address = @getUint16()
        @memory[@regs.SP] = @regs.PC >> 8
        @memory[@regs.SP - 1] = @regs.PC & 0xFF
        @regs.SP -= 2
        @regs.PC = address

      # RLA
      when 0x17
        newC= @regs.A >> 7
        @flags.N = 0
        @flags.H = 0
        @regs.A = ((@regs.A << 1) + @flags.C) & 0xFF
        @flags.C = newC
        @flags.Z = if @regs.A == 0 then 1 else 0

      when 0x9
        console.log 'implement me'
      when 0xD5
        console.log 'implement me'
      when 0x19
        console.log 'implement me'
      when 0xD1
        console.log 'implement me'

      # DEC B
      when 0x05
        @regs.B--
        @flags.Z = if @regs.B == 0 then 1 else 0
        @flags.N = 1
        #@flags.H = ?? I don't understand this flag yet :)

      # DEC A
      when 0x3D
        @regs.A--
        @flags.Z = if @regs.A == 0 then 1 else 0
        @flags.N = 1
        #@flags.H = ?? I don't understand this flag yet :)

      # DEC C
      when 0x0D
        @regs.C--
        @flags.Z = if @regs.C == 0 then 1 else 0
        @flags.N = 1
        #@flags.H = ?? I don't understand this flag yet :)

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
        @regs.PC = (@memory[@regs.SP + 2] << 8) + @memory[@regs.SP + 1]
        @regs.SP += 2

      # RET NC
      when 0xD0
        unless @flags.C
          @regs.PC = (@memory[@regs.SP + 2] << 8) + @memory[@regs.SP + 1]
          @regs.SP += 2

      # CP #
      when 0xFE
        data = @getUint8()
        result = @regs.A - data
        @flags.Z = if result == 0 then 1 else 0
        @flags.N = 1
        #flags.H ??
        @flags.C = if @regs.A < data then 1 else 0

      when 0xCB
        opcode2 = @getUint8()

        switch opcode2
          # BIT 7, H
          when 0x7C
            @flags.Z = (@regs.H >> 7) == 0
            @booya = @regs.H
            @flags.N = 0
            @flags.H = 1

          # RL C
          when 0x11
            newC = @regs.C >> 7
            @flags.N = 0
            @flags.H = 0
            @regs.C = ((@regs.C << 1) + @flags.C) & 0xFF
            @flags.C = newC
            @flags.Z = if @regs.C == 0 then 1 else 0

          else
            throw "Unknown opcode: 0xCB 0x#{opcode2.toString(16)}"

      else
        throw "Unknown opcode: 0x#{opcode.toString(16)}"

    if @breakpoints?[@regs.PC]
      return false
    true



window.CPU = CPU
