requestAnimationFrame =
  window.requestAnimationFrame or window.mozRequestAnimationFrame or
  window.webkitRequestAnimationFrame or window.msRequestAnimationFrame

isPaused = true

core = new Core()
mmu  = new MMU()

core.MMU = mmu

downloadBlob = (path, cb) ->
  # jQuery didn't support 'arraybuffer' as a response type.
  xhr = new XMLHttpRequest()
  xhr.responseType = 'arraybuffer'

  xhr.onload = (e) ->
    if @status == 200
      blob = new Uint8Array(@response)
      cb? blob
    else
      throw "Couldn't download blob at '#{path}'."

  xhr.open 'GET', path, true
  xhr.send()

updateRegisters = ->
  registers = [
    'A', 'B', 'C', 'D', 'E',
    'H', 'L',
    'PC', 'SP',
    'BC', 'DE', 'HL'
  ]

  html = ''
  for register in registers
    value = core.Params[register].toString(16)
    html += "<li>#{register}: $#{value}</li>"

  $('#registers').html(html)

drawVideo = ->
  # Simulate vblank, different code looks at different scalines.. hack for now.
  if mmu.memory[0xFF44] == 0x91
    mmu.memory[0xFF44] = 0x90
  else
    mmu.memory[0xFF44] = 0x91

  ctx = $('#canvas').get(0).getContext('2d')
  ctx.clearRect(0, 0, 300, 300)
  ctx.fillStyle = "black"

  drawTile = (tileIndex, x, y) ->
    # Tiles are 16 bytes long.
    baseIndex = 0x8000 + tileIndex * 16

    # 8 rows.
    for y2 in [0...8]
      rowIndex = baseIndex + y2 * 2
      tiles  = mmu.memory[rowIndex]
      tiles2 = mmu.memory[rowIndex + 1]

      for i in [0...8]
        # Mono color for now, beurk.
        if tiles >> (7 - i) & 1 == 1 or tiles2 >> (7 - i) & 1 == 1
          ctx.fillRect(x + i, y + y2, 1, 1)

  # 32x32 tiles per background.
  for x in [0...32]
    for y in [0...32]
      mapIdx = mmu.memory[0x9800 + x + y * 32]
      drawTile mapIdx, x * 8, y * 8

run = ->
  if isPaused
    # Step one opcode at a time when paused.
    core.executeOpcode()
  else
    for i in [0..50000]
      unless core.executeOpcode()
        # Breakpoint reached.
        $('#resume').click()
        break

  drawVideo()
  requestAnimationFrame(run) unless isPaused

$ ->
  $('#step').click ->
    run()
    updateRegisters()

  $('#resume').click ->
    isPaused = !isPaused

    if isPaused
      $(this).text('Resume')
      $('#step').removeAttr('disabled')
      updateRegisters()
    else
      $(this).text('Pause')
      $('#step').attr('disabled', 'disabled')
      run()

  # Reset registers
  updateRegisters()

  # Download bootstrap ROM
  downloadBlob 'ROMs/DMG_ROM.bin', (blob) ->
    mmu.BootstrapRom = blob

    rom =
      if window.location.hash == ''
        'ROMS/ROM.gb'
      else
        "ROMS/#{window.location.hash[1..]}.gb"

    # Download ROM
    downloadBlob rom, (blob2) ->
      mmu.Cart = new Cart(blob2)
