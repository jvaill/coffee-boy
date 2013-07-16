class Video
  MMU:       null
  CanvasCtx: null

  Mode:      0
  modeClock: 0
  line:      0

  constructor: (@MMU, @CanvasCtx) ->
    unless @MMU?
      throw 'MMU is required.'
    unless @CanvasCtx?
      throw 'CanvasCtx is required.'

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


  render: ->
    console.log 'render'

    @CanvasCtx.clearRect(0, 0, 300, 300)
    @CanvasCtx.fillStyle = "black"

    @drawBackground()

  clear: ->
    @CanvasCtx.clearRect(0, 0, 300, 300)

  drawTile: (tileIndex, x, y) ->
    # Tiles are 16 bytes long
    baseIndex = 0x8000 + tileIndex * 16

    # 8 rows
    for y2 in [0...8]
      rowIndex = baseIndex + y2 * 2
      tiles  = @MMU.memory[rowIndex]
      tiles2 = @MMU.memory[rowIndex + 1]

      for i in [0...8]
        # Mono color for now, beurk
        if tiles >> (7 - i) & 1 == 1 or tiles2 >> (7 - i) & 1 == 1
          @CanvasCtx.fillRect(x + i, y + y2, 1, 1)

  drawBackground: ->
    # 32x32 tiles per background
    for x in [0...32]
      for y in [0...32]
        mapIdx = @MMU.memory[0x9800 + x + y * 32]
        @drawTile mapIdx, x * 8, y * 8

window.Video = Video
