class Video
  MMU:       null
  CanvasCtx: null

  constructor: (@MMU, @CanvasCtx) ->
    unless @MMU?
      throw 'MMU is required.'
    unless @CanvasCtx?
      throw 'CanvasCtx is required.'

  Render: ->
    # HACK: Simulate VBLANK.. different code looks for different scanlines
    if @MMU.memory[0xFF44] == 0x91
      @MMU.memory[0xFF44] = 0x90
    else
      @MMU.memory[0xFF44] = 0x91

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
