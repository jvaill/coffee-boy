class Cart
  buffer: null

  constructor: (@buffer) ->
    unless @buffer instanceof Uint8Array
      throw 'Input buffer must be of type Uint8Array.'

  Get: (index) ->
    @buffer[index]

  Set: (index, value) ->
    @buffer[index] = value

window.Cart = Cart
