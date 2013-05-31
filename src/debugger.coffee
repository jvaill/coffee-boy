class Debugger
  PC: 0

  loadCode: (buffer) ->
    unless buffer instanceof Uint8Array
      throw 'Input buffer must be of type Uint8Array.'
    @buffer = buffer
    @disassemble()

  disassemble: ->
    return unless @buffer?
    while mnemonic = @decodeOpcode()
      console.log mnemonic

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

  # To hex helpers

  getUint8H:             -> @getUint8().toString(16)
  getUint16H:            -> @getUint16().toString(16)
  getInt8H:              -> @getInt8().toString(16)
  getRelInt8JmpAddressH: -> @getRelInt8JmpAddress().toString(16)

  # Misc

  decodeOpcode: ->
    opcode = @getUint8()

    switch opcode
      when 0x04 then 'INC B'
      when 0x05 then 'DEC B'
      when 0x06 then "LD B, $#{@getUint8H()}"
      when 0x0C then 'INC C'
      when 0x0D then 'DEC C'
      when 0x0E then "LD C, $#{@getUint8H()}"
      when 0x11 then "LD DE, $#{@getUint16H()}"
      when 0x13 then 'INC DE'
      when 0x15 then 'DEC D'
      when 0x16 then "LD D, $#{@getUint8H()}"
      when 0x18 then "JR $#{@getRelInt8JmpAddressH()}"
      when 0x1A then 'LD A, (DE)'
      when 0x1D then 'DEC E'
      when 0x1E then "LD E, $#{@getUint8H()}"
      when 0x20 then "JR NZ, $#{@getRelInt8JmpAddressH()}"
      when 0x21 then "LD HL, $#{@getUint16H()}"
      when 0x22 then 'LDI (HL), A'
      when 0x23 then 'INC HL'
      when 0x24 then 'INC H'
      when 0x28 then "JR Z, $#{@getRelInt8JmpAddressH()}"
      when 0x2E then "LD L, $#{@getUint8H()}"
      when 0x31 then "LD SP, $#{@getUint16H()}"
      when 0x32 then 'LDD (HL), A'
      when 0x3D then 'DEC A'
      when 0x3E then "LD A, $#{@getUint8H()}"
      when 0x4F then 'LD C, A'
      when 0x57 then 'LD D, A'
      when 0x67 then 'LD H, A'
      when 0x77 then 'LD (HL), A'
      when 0x7B then 'LD A, E'
      when 0x7C then 'LD A, H'
      when 0x90 then 'SUB B'
      when 0xAF then 'XOR A'
      when 0xC5 then 'PUSH BC'

      when 0xcb     # Ext ops
        params = @getUint8()

        # Command
        command = params >> 6
        mnemonic =
          switch command
            when 0x1 then 'BIT'
            else
              throw "Unknown command: 0x#{command.toString(16)}"

        # Bit
        bit = (params >> 3) & 0x7
        mnemonic += " #{bit}"

        # Register
        registers = ['B', 'C', 'D', 'E', 'H', 'L', '(HL)', 'A']
        register  = registers[params & 0x7]
        mnemonic += ", #{register}"

        mnemonic

      when 0xCD then "CALL $#{@getUint16H()}"
      when 0xE0 then "LDH ($#{@getUint8H()}), A"
      when 0xE2 then 'LDH (C), A'
      when 0xEA then "LD ($#{@getUint16H()}), A"
      when 0xF0 then "LDH A, ($#{@getUint8H()})"
      when 0xFE then "CP $#{@getUint8H()}"
      else
        throw "Unknown opcode: 0x#{opcode.toString(16)}"


window.Debugger = Debugger
