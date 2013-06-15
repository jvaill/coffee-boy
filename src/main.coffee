requestAnimationFrame = window.requestAnimationFrame or window.mozRequestAnimationFrame or
                        window.webkitRequestAnimationFrame or window.msRequestAnimationFrame

isPaused = true

downloadBlob = (path, cb) ->
  # jQuery didn't support 'arraybuffer' as a response type.
  xhr = new XMLHttpRequest()
  xhr.responseType = 'arraybuffer'

  xhr.onload = (e) ->
    if @status == 200
      blob = new Uint8Array(@response)
      cb? blob
    else
      throw "Could not download blob at '#{path}'."

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
    value = cpu.regs[register].toString(16)
    html += "<li>#{register}: $#{value}</li>"

  $('#registers').html(html)

drawVideo = ->
  # Vblank available.
  # Different code looks at different scanlines. Hack.
  if cpu.memory[0xFF44] == 0x91
    cpu.memory[0xFF44] = 0x90
  else
    cpu.memory[0xFF44] = 0x91

  ctx = $('#canvas').get(0).getContext('2d')
  ctx.clearRect(0, 0, 160, 144)
  ctx.fillStyle = "black"

  drawTile = (tileIndex, x, y) ->
    y += cpu.memory[0xFF42]

    # Tiles are 16 bytes long.
    baseIndex = 0x8000 + tileIndex * 16

    # 8 rows.
    for y2 in [0...8]
      rowIndex = baseIndex + y2 * 2
      tiles  = cpu.memory[rowIndex]
      tiles2 = cpu.memory[rowIndex + 1]

      for i in [0...8]
        # Mono color for now, beurk.
        if tiles >> (7 - i) & 1 == 1 or tiles2 >> (7 - i) & 1 == 1
          ctx.fillRect(x + i, y + y2, 1, 1)

  # 32x32 tiles per background.
  for x in [0...32]
    for y in [0...32]
      mapIdx = cpu.memory[0x9800 + x + y * 32]
      drawTile mapIdx, x * 8, y * 8

step = ->
  if isPaused
    # Step one opcode at a time when paused.
    cpu.executeOpcode()
  else
    for i in [0..500]
      unless cpu.executeOpcode()
        # Breakpoint reached.
        $('#resume').click()
        break

  drawVideo()

  unless isPaused
    requestAnimationFrame step

cpu = new CPU()

$ ->
  updateRegisters()
  $('#memory').hexView(cpu.memory)

  $('#step').click ->
    step()
    $('#disassembly').disassemblyView('SetPC', cpu.regs.PC)
    $('#memory').hexView('Refresh')
    updateRegisters()

  $('#resume').click ->
    isPaused = !isPaused

    if isPaused
      $(this).text('Resume')
      $('#step').removeAttr('disabled')
      $('#disassembly').disassemblyView('SetPC', cpu.regs.PC)
      $('#memory').hexView('Refresh')
      updateRegisters()
    else
      $(this).text('Pause')
      $('#step').attr('disabled', 'disabled')
      $('#disassembly').disassemblyView('SetPC', null)
      step()

  downloadBlob 'ROMs/DMG_ROM.bin', (blob) ->
    downloadBlob 'ROMS/ROM.gb', (blob2) ->
      ROM = new Uint8Array(blob2.buffer, 0x100, blob2.length - 0x100)

      # Append the rom after the BIOS.
      tmp = new Uint8Array(blob.byteLength + ROM.byteLength)
      tmp.set(blob, 0)
      tmp.set(ROM, blob.byteLength)

      # Disassemble.
      disassembler = new Disassembler(tmp)
      $('#disassembly').disassemblyView(disassembler)
      $('#disassembly').disassemblyView 'GetBreakpoints', (breakpoints) ->
        cpu.breakpoints = breakpoints

      # Scrappy emulate.
      cpu.LoadCode tmp
      $('#disassembly').disassemblyView('SetPC', cpu.regs.PC)
      $('#memory').hexView('Refresh')
