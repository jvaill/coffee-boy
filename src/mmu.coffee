class MMU
  BootstrapRom: null
  Cart:         null
  Video:        null

  memory: new Array(0xFFFF)
  isBootstrapRomDisabled: false

  Get: (index) ->
    if index < 0x100 and !@isBootstrapRomDisabled
      @BootstrapRom[index]
    else if index < 0x8000
      @Cart.Get(index)
    else if index == 0xFF44
      @Video.line
    else
      @memory[index]

  Set: (index, value) ->
    if index == 0xFF50 and value & 1
      @isBootstrapRomDisabled = true

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
