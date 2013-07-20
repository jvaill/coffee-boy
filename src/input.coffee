class Input
  rows: [0x0F, 0x0F]
  column: 0

  constructor: ->
    window.onkeydown = @kdown
    window.onkeyup = @kup

  Get: (index) ->
    if @column == 0x10
      @rows[0]
    else if @column == 0x20
      @rows[1]
    else
      0

  Set: (index, value) ->
    @column = value & 0x30

  kdown: (e) =>
    switch e.keyCode
      when 39 then @rows[1] &= 0xE
      when 37 then @rows[1] &= 0xD
      when 38 then @rows[1] &= 0xB
      when 40 then @rows[1] &= 0x7
      when 90 then @rows[0] &= 0xE
      when 88 then @rows[0] &= 0xD
      when 32 then @rows[0] &= 0xB
      when 13 then @rows[0] &= 0x7

  kup: (e) =>
    switch e.keyCode
      when 39 then @rows[1] |= 0x1
      when 37 then @rows[1] |= 0x2
      when 38 then @rows[1] |= 0x4
      when 40 then @rows[1] |= 0x8
      when 90 then @rows[0] |= 0x1
      when 88 then @rows[0] |= 0x2
      when 32 then @rows[0] |= 0x4
      when 13 then @rows[0] |= 0x8

window.Input = Input
