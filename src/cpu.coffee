class CPU
  buffer: null
  PC:     null
  SP:     null
  A:      null
  B:      null
  C:      null
  D:      null
  E:      null
  H:      null
  L:      null
  flags:  null
  memory: null

  constructor: ->
    @reset()

  LoadCode: (buffer) ->
    unless buffer instanceof Uint8Array
      throw 'Input buffer must be of type Uint8Array.'

    @buffer = buffer

    # Kind of map the ROM where it belongs.
    for i in [0...0xFF]
      @memory[i] = @buffer[i]
      @memory[i + 0xFF] = @buffer[i + 0xFF * 2 + 1]

    # @reset()
    @resume()

  reset: ->
    @PC = 0
    @SP = 0
    @A  = 0
    @B  = 0
    @C  = 0
    @D  = 0
    @E  = 0
    @H  = 0
    @L  = 0
    @memory = new Array(0xFFFF + 1)

    @flags =
      Z: null
      N: null
      H: null
      C: null

  # Unsigned

  getUint8: ->
    @buffer[@PC++]

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
    @getInt8() + @PC

  resume: ->
    unless @buffer?
      throw 'Code must be loaded using Debugger.LoadCode() first.'

    # Temporary
    while @booya != 10
      @executeOpcode()

  executeOpcode: ->
    opcode = @getUint8()
    unless opcode?
      return false


    switch opcode
      # LD SP, nn
      when 0x31
        @SP = @getUint16()

      # XOR A
      when 0xAF
        @A ^= @A
        @flags.Z = @A == 0
        @flags.N = 0
        @flags.H = 0
        @flags.C = 0

      # LD HL, nn
      when 0x21
        @L = @getUint8()
        @H = @getUint8()

      # LDD (HL), A
      when 0x32
        @memory[(@H << 8) + @L] = @A
        @L = (@L - 1) & 255
        if @L == 255
          @H = (@H - 1) & 255

      # JR NZ, *
      when 0x20
        address = @getRelInt8JmpAddress()
        unless @flags.Z
          @PC = address

      # JR Z, *
      when 0x28
        address = @getRelInt8JmpAddress()
        if @flags.Z
          @PC = address

      # JR n
      when 0x18
        @PC = @getRelInt8JmpAddress()

      # LD C, n
      when 0x0E
        @C = @getUint8()

      # LD A, #
      when 0x3E
        @A = @getUint8()

      # LD ($FF00 + C), A
      when 0xE2
        @memory[0xFF00 + @C] = @A

      # INC C
      when 0x0C
        @C++
        @flags.Z == @C == 0
        @flags.N = 0
        @flags.H = ((@C >> 3) & 1) == 1

      # LD (HL), A
      when 0x77
        @memory[(@H << 8) + @L] = @A

      # LD ($FF00+n), A
      when 0xE0
        address = 0xFF00 + @getUint8()
        @memory[address] = @A

      # LD DE, nn
      when 0x11
        @E = @getUint8()
        @D = @getUint8()

      # LD A, (DE)
      when 0x1A
        @A = @memory[(@D << 8) + @E]

      # CALL nn
      when 0xCD
        address = @getUint16()
        @memory[@SP] = @PC >> 8
        @memory[@SP - 1] = @PC & 0xFF
        @SP -= 2
        @PC = address

      # LD C, A
      when 0x4F
        @C = @A

      # LD B, n
      when 0x06
        @B = @getUint8()

      # LD L, n
      when 0x2E
        @L = @getUint8()

      # PUSH BC
      when 0xC5
        @memory[@SP] = @B
        @memory[@SP - 1] = @C
        @SP -= 2

      # RLA
      when 0x17
        newC= @A >> 7
        @flags.N = 0
        @flags.H = 0
        @A = ((@A << 1) + @flags.C) & 0xFF
        @flags.C = newC
        @flags.Z = if @A == 0 then 1 else 0

      # POP BC
      when 0xC1
        @C = @memory[@SP + 1]
        @B = @memory[@SP + 2]
        @SP += 2

      # DEC B
      when 0x05
        @B--
        @flags.Z = if @B == 0 then 1 else 0
        @flags.N = 1
        #@flags.H = ?? I don't understand this flag yet :)

      # DEC A
      when 0x3D
        @A--
        @flags.Z = if @A == 0 then 1 else 0
        @flags.N = 1
        #@flags.H = ?? I don't understand this flag yet :)

      # DEC C
      when 0x0D
        @C--
        @flags.Z = if @C == 0 then 1 else 0
        @flags.N = 1
        #@flags.H = ?? I don't understand this flag yet :)

      # LDI (HL), A
      when 0x22
        @memory[(@H << 8) + @L] = @A
        @L = (@L + 1) & 255
        if !@L
          @H = (@H + 1) & 255

      # INC HL
      when 0x23
        @L = (@L + 1) & 255
        if !@L
          @H = (@H + 1) & 255

      # INC DE
      when 0x13
        @E = (@E + 1) & 255
        if !@E
          @D = (@D + 1) & 255

      # RET
      when 0xC9
        @PC = (@memory[@SP + 2] << 8) + @memory[@SP + 1]
        @SP += 2

      # LD A, E
      when 0x7B
        @A = @E

      # CP #
      when 0xFE
        data = @getUint8()
        result = @A - data
        @flags.Z = if result == 0 then 1 else 0
        @flags.N = 1
        #flags.H ??
        @flags.C = if @A < data then 1 else 0

      # LD (nn), A
      when 0xEA
        @memory[@getUint16()] = @A

      when 0xCB
        opcode2 = @getUint8()

        switch opcode2
          # BIT 7, H
          when 0x7C
            @flags.Z = (@H >> 7) == 0
            @booya = @H
            @flags.N = 0
            @flags.H = 1

          # RL C
          when 0x11
            newC = @C >> 7
            @flags.N = 0
            @flags.H = 0
            @C = ((@C << 1) + @flags.C) & 0xFF
            @flags.C = newC
            @flags.Z = if @C == 0 then 1 else 0

          else
            throw "Unknown opcode: 0xCB 0x#{opcode2.toString(16)}"

      else
        throw "Unknown opcode: 0x#{opcode.toString(16)}"


window.CPU = CPU
