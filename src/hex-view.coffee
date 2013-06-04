do ($ = jQuery) =>

  PLUGIN_NAMESPACE = 'HEX_VIEW'

  class HexView
    
    MEASUREMENT_TEST_STRING: 'iqVy.ch=KM/4'

    $element:  null
    $data:     null
    $scroller: null

    fontDimensions:      null
    stride:              null
    addressGutterLength: null
    bytesPerLine:        null

    constructor: (element, @buffer) ->
      unless element? then throw "A containing element is required."
      unless @buffer? then throw "A buffer is required."

      @$element = $(element).empty()

      # Create a div to hold the current data view,
      @$data     = $("<div />").appendTo(@$element)
      # Create a second div and overlay it to allow for scrolling.
      @$scroller = $("<div style='position: relative; overflow: auto' />").appendTo(@$element)

      # Init
      @reset()
      @bufferLengthChanged()
      @$scroller.scroll => @refresh()

      @render 0

    refresh: ->
      lineIndex = Math.floor(@$scroller.scrollTop() / @fontDimensions.height)
      address   = lineIndex * @bytesPerLine
      @render address

    reset: ->
      width  = @$element.width()
      height = @$element.height()

      # Update container sizes.
      @$data.css(
        width:  width
        height: height
      )

      @$scroller.css(
        width:  width
        height: height
        top:   -height
      )

      # Get stride (# of chars per row, # of chars per column).
      @fontDimensions = @getFontDimensions()
      @stride =
        x: Math.floor(width  / @fontDimensions.width)
        y: Math.floor(height / @fontDimensions.height)

      # Get sizes.
      sizes = @getSizes(@stride.x)
      @addressGutterLength = sizes.addressGutterLength
      @bytesPerLine        = sizes.bytesPerLine

    bufferLengthChanged: ->
      @$scroller.empty()
      # Create a scrollbar and set its height accordingly.
      scrollHeight = (Math.ceil(@buffer.length / @bytesPerLine) + 1) * @fontDimensions.height
      @$scroller.append $("<div style='height: #{scrollHeight}px' />")

    getFontDimensions: ->
      $measure = $("<span style='visibility: hidden' />").appendTo(@$data)

      # Measure a single character.
      $measure.text('0')
      [fontWidth, fontHeight] = [$measure.width(), $measure.height()]

      # Now measure a longer string and get the average for a single
      # character to ensure that this is a fixed width font.
      $measure.text(@MEASUREMENT_TEST_STRING)
      unless fontWidth == $measure.width() / @MEASUREMENT_TEST_STRING.length
        throw 'Font must be fixed width.'

      $measure.remove()
      { width: fontWidth, height: fontHeight }

    # Gets different sizes required for rendering.
    getSizes: (xStride) ->
      maxMemoryAddress = @buffer.length.toString(16)

      addressGutterLength = maxMemoryAddress.length
      bytesPerLine        = 1

      # Calculates the number of characters per line with the given parameters.
      calculateStride = (addressGutterLength, numBytes) ->
        stride  = addressGutterLength # Address in buffer    ('00FF')
        stride += 1                   # Separator            (' ')
        stride += numBytes * 3        # Data incl. separator ('50 6F 6F 66 21 ')
        stride += numBytes            # ASCII representation ('Poof!')
        stride

      # Ensure that we can at least display one byte per line.
      if calculateStride(addressGutterLength, bytesPerLine) > @stride.x
        throw 'Container must be sufficiently wide to display at least one byte.'

      # Add bytes to fill the remaining space.
      while calculateStride(addressGutterLength, bytesPerLine + 1) <= @stride.x
        bytesPerLine++

      { addressGutterLength: addressGutterLength, bytesPerLine: bytesPerLine }

    render: (address) ->
      padLeft = (string, padString, length) ->
        string = padString + string while string.length < length
        string

      view = []
      # Loop thru lines.
      for y in [0...@stride.y]
        lineAddress  = address + y * @bytesPerLine

        bytes = []
        ascii = ''
        # Loop thru bytes.
        for x in [0...@bytesPerLine]
          if lineAddress + x > @buffer.length - 1
            # Last line. Append non-breaking spaces to pad bytes so the ascii still aligns.
            bytes.push String.fromCharCode(0xA0) + String.fromCharCode(0xA0)
          else
            byte = @buffer[lineAddress + x] ? '??'
            # Append the byte.
            bytes.push padLeft(byte.toString(16), 0, 2)
            # Append the char if it falls within the printable ASCII range, otherwise append a dot.
            ascii += if byte >= 0x20 and byte <= 0x7E then String.fromCharCode(byte) else '.'

        # Append the line.
        lineAddress = padLeft(lineAddress.toString(16), '0', @addressGutterLength)
        bytes       = bytes.join(' ')
        ascii       = ascii.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

        view.push "#{lineAddress} #{bytes} #{ascii}"

      # Render.
      @$data.html view.join('<br/>')

  $.fn.extend
    hexView: (buffer) ->
      if typeof buffer == 'string' and $(@).data(PLUGIN_NAMESPACE)?
        # Call a method on the original instance.
        method = buffer
        instance = $(@).data(PLUGIN_NAMESPACE)
        instance[method].apply instance, Array.prototype.slice.call(arguments, 1)
      else
        # Create a new instance.
        instance = new HexView(this, buffer)
        $(@).data(PLUGIN_NAMESPACE, instance)

      this
