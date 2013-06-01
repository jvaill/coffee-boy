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

  LoadCode: (buffer) ->
    unless buffer instanceof Uint8Array
      throw 'Input buffer must be of type Uint8Array.'

    @buffer = buffer
    @reset()
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
    @memory = []

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

      # LD C, n
      when 0x0E
        @C = @getUint8()

      # LD A, #
      when 0x3E
        @A = @getUint8()

      # LD ($FF00 + C), A
      when 0xE2
        @memory[0xFF00 + @C]     = (@A >> 8)
        @memory[0xFF00 + @C + 1] = (@A & 0xFF)

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

      when 0xCB
        opcode2 = @getUint8()

        switch opcode2
          # BIT 7, H
          when 0x7C
            @flags.Z = (@H >> 7) == 0
            @booya = @H
            @flags.N = 0
            @flags.H = 1
          else
            throw "Unknown opcode: 0xCB 0x#{opcode2.toString(16)}"

      else
        console.log @PC.toString(16)
        console.log @memory
        throw "Unknown opcode: 0x#{opcode.toString(16)}"


window.CPU = CPU
