class Video
  MMU:       null
  CanvasCtx: null

  Mode:      0
  modeClock: 0
  line:      0

  BgPal: [
    [0,0,0]
    [0,0,0]
    [0,0,0]
    [0,0,0]
  ]

  LCDC: 0
  Memory: new Uint8Array(0x2000)
  isBgDirty: false

  constructor: (@MMU, @CanvasCtx) ->
    unless @MMU?
      throw 'MMU is required.'
    unless @CanvasCtx?
      throw 'CanvasCtx is required.'

    @imageData = @CanvasCtx.createImageData(256, 256)
    buf = new ArrayBuffer(@imageData.data.length);
    @buf8 = new Uint8ClampedArray(buf);
    @data = new Uint32Array(buf);

  Step: (cycles) ->
    @modeClock += cycles

    switch @Mode
      # OAM read mode, scanline active
      when 2
        if @modeClock >= 80
          # Enter scanline mode 3
          @modeClock = 0
          @Mode = 3
        break

      # VRAM read mode, scanline active
      # Treat end of mode 3 as end of scanline
      when 3
        if @modeClock >= 172
          # Enter hblank
          @modeClock = 0
          @Mode = 0

          # RenderScanline()
        break

      # Hblank
      # After the last hblank, render the screen
      when 0
        if @modeClock >= 204
          @modeClock = 0
          @line++

          if @line == 143
            # Enter vblank
            @MMU.Regs.IF.Vblank = true
            @Mode = 1
            @render()
          else
            @Mode = 2
        break

      # Vblank (10 lines)
      when 1
        if @modeClock >= 456
          @modeClock = 0
          @line++

          if @line > 153
            # Restart scanning modes
            @Mode = 2
            @line = 0
        break

  Set: (index, value) ->
    if index >= 0x8000 and index <= 0xA000
      indexIntoVram = index - 0x8000
      @Memory[indexIntoVram] = value

      # Figure out what we've dirtied
      unless @isBgDirty

        if index >= 0x9800 and index <= 0x9BFF
          # Within BG tile map?
          unless @LCDC & 0x8
            @isBgDirty = true

        else if index >= 0x9C00 and index <= 0x9FFF
          # Within BG tile map?
          if @LCDC & 0x8
            @isBgDirty = true

        if index >= 0x8800 and index <= 0x97FF
          # Within BG tile data?
          unless @LCDC & 0x10
            @isBgDirty = true

        else if index >= 0x8000 and index <= 0x8FFF
          # Within BG tile data?
          if @LCDC & 0x10
            @isBgDirty = true


    else if index == 0xFF40
      # Bg & Window Display flipped on?
      if !(@LCDC & 0x1) and value & 0x1
        @isBgDirty = true

      # BG Tile Map Display Select changed?
      if @LCDC & 0x8 != value & 0x8
        @isBgDirty = true

      # BG & Window Tile Data Select changed?
      if @LCDC & 0x10 != value & 0x10
        @isBgDirty = true

      # LCD Control Operation flipped on?
      if !(@LCDC & 0x80) and value & 0x80
        @isBgDirty = true

      @LCDC = value

  Get: (index) ->
    if index >= 0x8000 and index <= 0xA000
      indexIntoVram = index - 0x8000
      @Memory[indexIntoVram]

    else if index == 0xFF40
      @LCDC

  render: ->
    @isBgDirty = true
    @clear()

    if @LCDC & 0x80 # LCD Display Enable
      @drawBackground()
      @drawSprites()

  clear: ->
    @CanvasCtx.clearRect(0, 0, 300, 300)

  drawTile: (tileIndex, x, y) ->
    baseTileDataIndex = 0

    # BG & Window Tile Data Select
    unless @LCDC & 0x10
      # Tile data starts at 0x8800 and tiles are signed (i.e. tile #0 lies at address 0x9000)
      baseTileDataIndex = 0x800

      # Two's complement
      sign = (tileIndex >> 7) & 0x1
      if sign
        tileIndex = -((tileIndex ^ 0xFF) + 1)

      # Add 128 to get an index we can multiply against
      tileIndex += 128

    # Get its index in memory
    tileDataIndex = baseTileDataIndex + tileIndex * 16 # 16 bytes per tile

    # Draw the tile, tiles are 8x8 pixels
    for y2 in [0...8]
      tileDataRowIndex = tileDataIndex + y2 * 2 # 2 bytes per row
      pixelData  = @Memory[tileDataRowIndex]
      pixelData2 = @Memory[tileDataRowIndex + 1]

      for x2 in [0...8]
        # Get a 3 bit offset into palette data for the current pixel
        nib = ((pixelData >> (7 - x2) & 1) << 1) | (pixelData2 >> (7 - x2) & 1)
        colour = @BgPal[nib]
        # Set the pixel on the background
        @data[(y + y2) * 256 + x + x2] = (255 << 24) | (colour[2] << 16) | (colour[1] << 8) | colour[0]

    @imageData.data.set(@buf8)

  drawSprite: (tileIndex, x, y, xflipped) ->
    image = @CanvasCtx.createImageData(8, 8)
    buf = new ArrayBuffer(image.data.length);
    buf8 = new Uint8ClampedArray(buf);
    data = new Uint32Array(buf);

    #tileIndex &= 0xFE # lower bit ignored in 8x16 mode
    # Tiles are 16 bytes long
    baseIndex = tileIndex * 16

    # 8 rows
    for y2 in [0...8]
      rowIndex = baseIndex + y2 * 2
      tiles  = @Memory[rowIndex]
      tiles2 = @Memory[rowIndex + 1]

      for i in [0...8]
        if xflipped
          itmp = 7 - i
        else
          itmp = i

        nib = ((tiles >> (7 - i) & 1) << 1) | (tiles2 >> (7 - i) & 1)
        colour = @BgPal[nib]
        data[(y2) * 8 + (itmp)] =  (255 << 24) | (colour[2] << 16) | (colour[1] << 8) | colour[0]

    image.data.set(buf8)
    @CanvasCtx.putImageData(image, x, y)

  drawBackground: ->
    if @isBgDirty
      # BG & Window Tile Data Select
      tileMapIndex = unless @LCDC & 0x8 then 0x1800 else 0x1C00

      # 32x32 tiles per background
      for y in [0...32]
        for x in [0...32]
          tileIndex = @Memory[tileMapIndex + y * 32 + x]
          # each tile is 8x8 pixels
          @drawTile tileIndex, x * 8, y * 8

      @isBgDirty = false
    @CanvasCtx.putImageData(@imageData, 0, 0)

  drawSprites: ->
    # 40 sprites
    for x in [0...40]
      baseIndex = 0xFE00 + (4 * x)
      ypos = @MMU.Get(baseIndex) - 16
      xpos = @MMU.Get(baseIndex + 1) - 8
      pattern = @MMU.Get(baseIndex + 2)
      attributes = @MMU.Get(baseIndex + 3)

      xflipped = (attributes & 0x20) > 0

      if xpos > 0 or ypos > 0
        pattern = pattern & 0xFE
        @drawSprite(pattern, xpos, ypos, xflipped)
        @drawSprite(pattern + 1, xpos, ypos + 8, xflipped)

window.Video = Video
