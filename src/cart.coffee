class Cart
  MMU:    null
  buffer: null
  bank:   1
  type:   0

  constructor: (@MMU, @buffer) ->
    unless @MMU?
      throw 'MMU is required.'
    unless @buffer instanceof Uint8Array
      throw 'Input buffer must be of type Uint8Array.'

    @type = @buffer[0x147]
    console.log @type

  Get: (index) ->
    if @type == 2 or @type == 3
      if index >= 0x4000 and index <= 0x7FFF
        @buffer[(index - 0x4000) + 0x4000 * @bank]
      else
        @buffer[index]
    else
      @buffer[index]

  Set: (index, value) ->
    if @type == 2 or @type == 3
      # Scrappy MBC1
      if index >= 0x2000 and index <= 0x3FFF
        @bank = value & 0x1F
        if @bank == 0
          @bank = 1
      else if index >= 0x4000 and index <= 0x5FFF
        console.log 'boom'
        asfsdg()
      else if index >= 0x6000 and index <= 0x7FFF
        console.log 'switch modes'
        asfsfsdg()
    else
      @buffer[index] = value

window.Cart = Cart
