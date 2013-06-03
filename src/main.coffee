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

    # Emulate
    cpu.LoadCode blob      
