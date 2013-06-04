# Adapted from:
# http://www.discoded.com/2012/04/05/my-favorite-javascript-string-extensions-in-coffeescript/
padLeft = (string, padString, length) ->
  while string.length < length
    string = padString + string
  return string

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

$ ->
  cpu = new CPU()
  $('#hex').hexView(cpu.memory)

  downloadBlob 'ROMs/DMG_ROM.bin', (blob) ->
    # Disassemble
    debug = new Debugger()
    debug.LoadCode blob

    disassembly = []
    for address, mnemonic of debug.disassembly
      addressH = parseInt(address).toString(16)
      disassembly.push "#{padLeft(addressH, '0', 4)}: #{mnemonic}"
    
    $('#disassembly').val disassembly.join("\n")

    downloadBlob 'ROMS/ROM.gb', (blob2) ->
      tmp = new Uint8Array(blob.byteLength + blob2.byteLength)
      tmp.set(blob, 0)
      tmp.set(blob2, blob.byteLength)

      # Emulate
      try
        cpu.LoadCode tmp
        
        doShit = ->
          # console.log cpu.regs.PC.toString(16)
          cpu.memory[0xFF44] = 0x90 #vblank available

          ctx = $('#canvas').get(0).getContext('2d')
          ctx.clearRect(0, 0, 160, 144)
          ctx.fillStyle = "black"

          drawTile = (tileIndex, x, y) ->
            y += cpu.memory[0xFF42]

            # Each tile is 16 bytes long.
            baseIndex = 0x8000 + tileIndex * 16

            # 8 rows.
            for y2 in [0...8]
              rowIndex = baseIndex + y2 * 2
              tiles  = cpu.memory[rowIndex]
              tiles2 = cpu.memory[rowIndex + 1]

              for i in [0...8]
                # mono colour
                if tiles >> (7 - i) & 1 == 1 or tiles2 >> (7 - i) & 1 == 1
                  ctx.fillRect(x + i, y + y2, 1, 1)

          for x in [0...32]
            for y in [0...32]
              mapIdx = cpu.memory[0x9800 + x + y * 32]
              drawTile mapIdx, x * 8, y * 8

          for i in [0..500]
            cpu.executeOpcode()

        setInterval doShit, 10



