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
  # Download and disassemble!
  downloadBlob 'ROMs/DMG_ROM.bin', (blob) ->
    debug = new Debugger()
    debug.LoadCode blob

    disassembly = []
    for address, mnemonic of debug.disassembly
      addressH = parseInt(address).toString(16)
      disassembly.push "#{padLeft(addressH, '0', 4)}: #{mnemonic}"
    
    $('#disassembly').val disassembly.join("\n")

    cpu = new CPU()
    cpu.LoadCode blob
