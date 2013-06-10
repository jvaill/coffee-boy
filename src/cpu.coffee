class CPU
  buffer: null
  flags:  null
  memory: null
  breakpoints: null

  regs: {
    A: 0, B: 0, C: 0, D: 0, E: 0
    H: 0, L: 0
    F: 0
    PC: 0, SP: 0

    # TODO: Investigate getters.
    BC: -> (@B << 8) + @C
    DE: -> (@D << 8) + @E
    HL: -> (@H << 8) + @L
  }

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
    @resume()

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

  resume: ->
    unless @buffer?
      throw 'Code must be loaded using Debugger.LoadCode() first.'

    # Temporary
    # while @booya != 10
    #   @executeOpcode()

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

  LD_nn_n: (reg) ->
    @regs[reg] = @getUint8()

  LD_r1_r2: (reg, reg2) ->
    @regs[reg] = @regs[reg2]

  LD_r_RR: (reg, reg2) ->
    @regs[reg] = @memory[@regs[reg2]()]

  LD_RR_r: (reg, reg2) ->
    @memory[@regs[reg]()] = @regs[reg2]

  LD_A_n: (reg) ->
    @regs.A = @regs[reg]

  LD_A_RR: (reg) ->
    @regs.A = @memory[@regs[reg]()]

  LD_A_NN: (reg) ->
    @regs.A = @memory[@getUint16()]

  LD_A_imm: ->
    @regs.A = @getUint8()

  LD_n_A: (reg) ->
    @regs[reg] = @regs.A

  LD_RR_A: (reg) ->
    @memory[@regs[reg]()] = @regs.A

  LD_NN_A: ->
    @memory[@getUint16()] = @regs.A

  LD_n_nn: (reg, reg2) ->
    @regs[reg2] = @getUint8()
    @regs[reg]  = @getUint8()

  LD_SP_nn: ->
    @regs.SP = @getUint16()

  INC_n: (reg) ->
    @regs[reg] = (@regs[reg] + 1) & 0xFF
    @flags.Z = unless @regs[reg] then 1 else 0
    @flags.N = 0
    @flags.H = unless @regs[reg] & 0xF then 1 else 0

  INC_RR: (reg) ->
    @memory[@regs[reg]()] = (@memory[@regs[reg]()] + 1) & 0xFF
    @flags.Z = unless @memory[@regs[reg]()] then 1 else 0
    @flags.N = 0
    @flags.H = unless @memory[@regs[reg]()] & 0xF then 1 else 0

  DEC_n: (reg) ->
    @regs[reg] = (@regs[reg] - 1) & 0xFF
    @flags.Z = unless @regs[reg] then 1 else 0
    @flags.N = 1
    @flags.H = if @regs[reg] & 0xF == 0xF  then 1 else 0

  DEC_RR: (reg) ->
    @memory[@regs[reg]()] = (@memory[@regs[reg]()] - 1) & 0xFF
    @flags.Z = unless @memory[@regs[reg]()] then 1 else 0
    @flags.N = 1
    @flags.H = if @memory[@regs[reg]()] & 0xF == 0xF  then 1 else 0

  ADD_A_n: (reg) ->
    @flags.N = 0
    @flags.H = ((@regs.A & 0xF) + (@regs[reg] & 0xF)) & 0x10
    @flags.C = if @regs.A + @regs[reg] > 0xFF then 1 else 0
    @regs.A += @regs[reg] & 0xFF
    @flags.Z = unless @regs.A then 1 else 0

  ADD_A_RR: (reg) ->
    @flags.N = 0
    @flags.H = ((@regs.A & 0xF) + (@memory[@regs[reg]()] & 0xF)) & 0x10
    @flags.C = if @regs.A + @memory[@regs[reg]()] > 0xFF then 1 else 0
    @regs.A = (@regs.A + @memory[@regs[reg]()]) & 0xFF
    @flags.Z = unless @regs.A then 1 else 0

  executeOpcode: ->
    opcode = @getUint8()
    unless opcode?
      return false


    switch opcode

      # LD nn, n
      when 0x06 then @LD_nn_n('B')
      when 0x0E then @LD_nn_n('C')
      when 0x16 then @LD_nn_n('D')
      when 0x1E then @LD_nn_n('E')
      when 0x26 then @LD_nn_n('H')
      when 0x2E then @LD_nn_n('L')

      # LD r1, r2

      when 0x40 then @LD_r1_r2('B', 'B')
      when 0x41 then @LD_r1_r2('B', 'C')
      when 0x42 then @LD_r1_r2('B', 'D')
      when 0x43 then @LD_r1_r2('B', 'E')
      when 0x44 then @LD_r1_r2('B', 'H')
      when 0x45 then @LD_r1_r2('B', 'L')
      when 0x46 then @LD_r_RR( 'B', 'HL')

      when 0x48 then @LD_r1_r2('C', 'B')
      when 0x49 then @LD_r1_r2('C', 'C')
      when 0x4A then @LD_r1_r2('C', 'D')
      when 0x4B then @LD_r1_r2('C', 'E')
      when 0x4C then @LD_r1_r2('C', 'H')
      when 0x4D then @LD_r1_r2('C', 'L')
      when 0x4E then @LD_r_RR( 'C', 'HL')

      when 0x50 then @LD_r1_r2('D', 'B')
      when 0x51 then @LD_r1_r2('D', 'C')
      when 0x52 then @LD_r1_r2('D', 'D')
      when 0x53 then @LD_r1_r2('D', 'E')
      when 0x54 then @LD_r1_r2('D', 'H')
      when 0x55 then @LD_r1_r2('D', 'L')
      when 0x56 then @LD_r_RR( 'D', 'HL')

      when 0x58 then @LD_r1_r2('E', 'B')
      when 0x59 then @LD_r1_r2('E', 'C')
      when 0x5A then @LD_r1_r2('E', 'D')
      when 0x5B then @LD_r1_r2('E', 'E')
      when 0x5C then @LD_r1_r2('E', 'H')
      when 0x5D then @LD_r1_r2('E', 'L')
      when 0x5E then @LD_r_RR( 'E', 'HL')

      when 0x60 then @LD_r1_r2('H', 'B')
      when 0x61 then @LD_r1_r2('H', 'C')
      when 0x62 then @LD_r1_r2('H', 'D')
      when 0x63 then @LD_r1_r2('H', 'E')
      when 0x64 then @LD_r1_r2('H', 'H')
      when 0x65 then @LD_r1_r2('H', 'L')
      when 0x66 then @LD_r_RR( 'H', 'HL')

      when 0x68 then @LD_r1_r2('L', 'B')
      when 0x69 then @LD_r1_r2('L', 'C')
      when 0x6A then @LD_r1_r2('L', 'D')
      when 0x6B then @LD_r1_r2('L', 'E')
      when 0x6C then @LD_r1_r2('L', 'H')
      when 0x6D then @LD_r1_r2('L', 'L')
      when 0x6E then @LD_r_RR( 'L', 'HL')

      when 0x70 then @LD_RR_r('HL', 'B')
      when 0x71 then @LD_RR_r('HL', 'C')
      when 0x72 then @LD_RR_r('HL', 'D')
      when 0x73 then @LD_RR_r('HL', 'E')
      when 0x74 then @LD_RR_r('HL', 'H')
      when 0x75 then @LD_RR_r('HL', 'L')

      # LD A, n
      when 0x7F then @LD_A_n('A')
      when 0x78 then @LD_A_n('B')
      when 0x79 then @LD_A_n('C')
      when 0x7A then @LD_A_n('D')
      when 0x7B then @LD_A_n('E')
      when 0x7C then @LD_A_n('H')
      when 0x7D then @LD_A_n('L')
      when 0x0A then @LD_A_RR('BC')
      when 0x1A then @LD_A_RR('DE')
      when 0x7E then @LD_A_RR('HL')
      when 0xFA then @LD_A_NN()
      when 0x3E then @LD_A_imm()

      # LD n, A
      when 0x47 then @LD_n_A('B')
      when 0x4F then @LD_n_A('C')
      when 0x57 then @LD_n_A('D')
      when 0x5F then @LD_n_A('E')
      when 0x67 then @LD_n_A('H')
      when 0x6F then @LD_n_A('L')
      when 0x02 then @LD_RR_A('BC')
      when 0x12 then @LD_RR_A('DE')
      when 0x77 then @LD_RR_A('HL')
      when 0xEA then @LD_NN_A()

      # LD A, (C)
      when 0xF2
        @regs.A = @memory[0xFF00 + @regs.C]
      
      # LD (C), A
      when 0xE2
        @memory[0xFF00 + @regs.C] = @regs.A

      # LDD A, (HL)
      when 0x3A
        @regs.A = @memory[@regs.HL()]
        @DEC_rr('H', 'L')

      # LDD (HL), A
      when 0x32
        @memory[@regs.HL()] = @regs.A
        @DEC_rr('H', 'L')

      # LDI A, (HL)
      when 0x2A
        @regs.A = @memory[@regs.HL()]
        @INC_rr('H', 'L')

      # LDI (HL), A
      when 0x22
        @memory[@regs.HL()] = @regs.A
        @INC_rr('H', 'L')

      # LDH (n), A
      when 0xE0
        @memory[0xFF00 + @getUint8()] = @regs.A

      # LDH A, (n)
      when 0xF0
        @regs.A = @memory[0xFF00 + @getUint8()]

      # INC BC
      when 0x03 then @INC_rr('B', 'C')

      # LD n, nn
      when 0x01 then @LD_n_nn('B', 'C')
      when 0x11 then @LD_n_nn('D', 'E')
      when 0x21 then @LD_n_nn('H', 'L')
      when 0x31 then @LD_SP_nn('SP')

      # LD SP, HL
      when 0xF9
        @regs.SP = @regs.HL()

      # CP (HL)
      when 0xBE
        test = @regs.A - @memory[@regs.HL()]
        @flags.Z = unless test then 1 else 0
        @flags.N = 1

      # DI
      when 0xF3
        console.log 'DI'

      # ADD A, n
      when 0x87 then @ADD_A_n('A')
      when 0x80 then @ADD_A_n('B')
      when 0x81 then @ADD_A_n('C')
      when 0x82 then @ADD_A_n('D')
      when 0x83 then @ADD_A_n('E')
      when 0x84 then @ADD_A_n('H')
      when 0x85 then @ADD_A_n('L')
      when 0x86 then @ADD_A_RR('HL')

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


      # LD SP, nn
      when 0x31
        @regs.SP = @getUint16()

      # XOR A
      when 0xAF
        @regs.A ^= @regs.A
        @flags.Z = @regs.A == 0
        @flags.N = 0
        @flags.H = 0
        @flags.C = 0

      # LD HL, nn
      when 0x21
        @regs.L = @getUint8()
        @regs.H = @getUint8()

      # LDD (HL), A
      when 0x32
        @memory[(@regs.H << 8) + @regs.L] = @regs.A
        @regs.L = (@regs.L - 1) & 255
        if @regs.L == 255
          @regs.H = (@regs.H - 1) & 255

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


      # LD A, #
      when 0x3E
        @regs.A = @getUint8()

      # SUB B
      when 0x90
        @regs.A -= @regs.B

      # LD ($FF00 + C), A
      when 0xE2
        @memory[0xFF00 + @regs.C] = @regs.A

      # INC C
      when 0x0C
        @regs.C++
        @flags.Z == @regs.C == 0
        @flags.N = 0
        @flags.H = ((@regs.C >> 3) & 1) == 1

      # LD (HL), A
      when 0x77
        @memory[(@regs.H << 8) + @regs.L] = @regs.A

      # LD ($FF00+n), A
      when 0xE0
        address = 0xFF00 + @getUint8()
        @memory[address] = @regs.A

      # LD DE, nn
      when 0x11
        @regs.E = @getUint8()
        @regs.D = @getUint8()

      # LD A, (DE)
      when 0x1A
        @regs.A = @memory[(@regs.D << 8) + @regs.E]

      # CALL nn
      when 0xCD
        address = @getUint16()
        @memory[@regs.SP] = @regs.PC >> 8
        @memory[@regs.SP - 1] = @regs.PC & 0xFF
        @regs.SP -= 2
        @regs.PC = address

      # LD C, A
      when 0x4F
        @regs.C = @regs.A


      # PUSH BC
      when 0xC5
        @memory[@regs.SP] = @regs.B
        @memory[@regs.SP - 1] = @regs.C
        @regs.SP -= 2

      # RLA
      when 0x17
        newC= @regs.A >> 7
        @flags.N = 0
        @flags.H = 0
        @regs.A = ((@regs.A << 1) + @flags.C) & 0xFF
        @flags.C = newC
        @flags.Z = if @regs.A == 0 then 1 else 0

      # POP BC
      when 0xC1
        @regs.C = @memory[@regs.SP + 1]
        @regs.B = @memory[@regs.SP + 2]
        @regs.SP += 2

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

      # LDI (HL), A
      when 0x22
        @memory[(@regs.H << 8) + @regs.L] = @regs.A
        @regs.L = (@regs.L + 1) & 255
        if !@regs.L
          @regs.H = (@regs.H + 1) & 255

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

      # LD A, E
      when 0x7B
        @regs.A = @regs.E

      # CP #
      when 0xFE
        data = @getUint8()
        result = @regs.A - data
        @flags.Z = if result == 0 then 1 else 0
        @flags.N = 1
        #flags.H ??
        @flags.C = if @regs.A < data then 1 else 0

      # LD (nn), A
      when 0xEA
        @memory[@getUint16()] = @regs.A

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
