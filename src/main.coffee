requestAnimationFrame =
  window.requestAnimationFrame or window.mozRequestAnimationFrame or
  window.webkitRequestAnimationFrame or window.msRequestAnimationFrame

isPaused = true

mmu   = null
core  = null
video = null
cart  = null

downloadBlob = (path, cb) ->
  # jQuery didn't support 'arraybuffer' as a response type
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

run = ->
  if isPaused
    # Step one opcode at a time when paused
    core.executeOpcode()
    video.Step(core.Cycles.Current)
  else
    for i in [0..500000]
      shouldBreak = !core.executeOpcode()
      video.Step(core.Cycles.Current)

      if shouldBreak
        # Breakpoint reached
        $('#resume').click()
        break

  requestAnimationFrame(run) unless isPaused

$ ->
  $('#step').click ->
    run()
    updateRegisters()
    $('#disassembly').disassemblyView('SetPC', core.Params.PC)

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

  ctx = $('#canvas').get(0).getContext('2d')
  mmu   = new MMU()
  window.core  = core = new Core(mmu)
  video = new Video(mmu, ctx)
  mmu.Video = video

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
      disasembler = new Disassembler(blob2)
      $('#disassembly').disassemblyView(disasembler)

      $('#disassembly').disassemblyView 'GetBreakpoints', (breakpoints) ->
        window.core.Breakpoints = breakpoints


      mmu.Cart = new Cart(mmu, blob2)
