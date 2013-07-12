class MMU
  memory: new Array(0xFFFF)

  Get: (index) ->
    @memory[index]

  Set: (index, value) ->
    @memory[index] = value

  # Unsigned

  GetUint16: (index) ->
    @Get(index) + (@Get(index + 1) << 8)

  # Signed

  GetInt8: (index) ->
    byte = @Get(index)

    # Two's complement
    sign = (byte >> 7) & 0x1
    if sign
      byte = -((byte ^ 0xFF) + 1)

    byte

window.MMU = MMU
