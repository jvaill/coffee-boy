class MMU
  BootstrapRom: null
  Cart:         null
  Video:        null

  memory: new Uint8Array(0xFFFF)

  Regs:
    Addresses:
      BootstrapRomFlag: 0xFF50
      IF:               0xFF0F
      LY:               0xFF44
      BGP:              0xFF47
      IE:               0xFFFF

    isBootstrapRomDisabled: false

    IF:
      Vblank:           false
      LcdcStatus:       false
      TimerOverflow:    false
      SerialTransfer:   false
      HiLoPin:          false

    IE:
      Vblank:           false
      LcdcStatus:       false
      TimerOverflow:    false
      SerialTransfer:   false
      HiLoPin:          false

  Get: (index) ->
    # Bootstrap ROM
    if index < 0x100 and !@Regs.isBootstrapRomDisabled
      @BootstrapRom[index]

    # Cart
    else if index < 0x8000
      @Cart.Get(index)

    # Interrupt Flag
    else if index == @Regs.Addresses.IF
      @Regs.IF.Vblank                  |
        (@Regs.IF.LcdcStatus     << 1) |
        (@Regs.IF.TimerOverflow  << 2) |
        (@Regs.IF.SerialTransfer << 3) |
        (@Regs.IF.HiLoPin        << 4)

    # LCDC - Y Coordinate
    else if index == @Regs.Addresses.LY
      @Video.line

    # Interrupt Enable
    else if index == @Regs.Addresses.IE
      @Regs.IE.Vblank                  |
        (@Regs.IE.LcdcStatus     << 1) |
        (@Regs.IE.TimerOverflow  << 2) |
        (@Regs.IE.SerialTransfer << 3) |
        (@Regs.IE.HiLoPin        << 4)

    # RAM
    else
      @memory[index]

  Set: (index, value) ->
    # Bootstrap ROM
    if index == @Regs.Addresses.BootstrapRomFlag
      @Regs.isBootstrapRomDisabled = true if value & 1

    # Interrupt Flag
    else if index == @Regs.Addresses.IF
      @Regs.IF.Vblank         = value & 1
      @Regs.IF.LcdcStatus     = (value >> 1) & 1
      @Regs.IF.TimerOverflow  = (value >> 2) & 1
      @Regs.IF.SerialTransfer = (value >> 3) & 1
      @Regs.IF.HiLoPin        = (value >> 4) & 1

    # BG & Window Palette Data
    else if index == @Regs.Addresses.BGP
      getColour = (data) ->
        switch data
          when 0 then [255, 255, 255]
          when 1 then [192, 192, 192]
          when 2 then [96, 96, 96]
          when 3 then [0, 0, 0]

      @Video.BgPal = [
        getColour(value & 0x3)
        getColour((value >> 2) & 0x3)
        getColour((value >> 4) & 0x3)
        getColour((value >> 6) & 0x3)
      ]

    # Interrupt Enable
    else if index == @Regs.Addresses.IE
      @Regs.IE.Vblank         = value & 1
      @Regs.IE.LcdcStatus     = (value >> 1) & 1
      @Regs.IE.TimerOverflow  = (value >> 2) & 1
      @Regs.IE.SerialTransfer = (value >> 3) & 1
      @Regs.IE.HiLoPin        = (value >> 4) & 1

    # HACK: Fake pad input until implemented
    else if index == 0xFF00
      @memory[index] = 0xFF

    # LCDC
    else if index == 0xFF40
      @Video.Set index, value

    # Video RAM
    else if index >= 0x8000 and index <= 0xA000
      @Video.Set index, value

    # RAM
    else
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
