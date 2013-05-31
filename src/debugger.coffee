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

  # To hex helpers

  getUint8H:  -> @getUint8().toString(16)
  getUint16H: -> @getUint16().toString(16)
  getInt8H:   -> @getInt8().toString(16)

  # Misc

  decodeOpcode: ->
    opcode = @getUint8()

    switch opcode
      when 0x20     # JR NZ, n
        rel = @getInt8()
        add = @PC + rel
        "JR NZ, $#{add}"

      when 0x21 then "LD HL, $#{@getUint16H()}"
      when 0x31 then "LD SP, $#{@getUint16H()}"
      when 0x32 then 'LDD (HL), A'
      when 0xAF then 'XOR A'
      
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
      else
        throw "Unknown opcode: 0x#{opcode.toString(16)}"


window.Debugger = Debugger
