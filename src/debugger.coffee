class Debugger
  loadCode: (buffer) ->
    if typeof buffer != 'Uint8Array'
      throw 'Input buffer must be of type Uint8Array.'
    @buffer = buffer

window.Debugger = Debugger
