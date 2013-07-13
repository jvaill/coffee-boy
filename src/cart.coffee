class Cart
  MMU:    null
  buffer: null

  constructor: (@MMU, @buffer) ->
    unless @MMU?
      throw 'MMU is required.'
    unless @buffer instanceof Uint8Array
      throw 'Input buffer must be of type Uint8Array.'

  Get: (index) ->
    @buffer[index]

  Set: (index, value) ->
    @buffer[index] = value

window.Cart = Cart
