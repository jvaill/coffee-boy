do ($ = jQuery) =>

  # Used to test for a fixed width font.
  MEASUREMENT_TEST_STRING = 'iqVy.ch=KM/4'

  $.fn.extend
    hexView: (buffer) ->
      unless buffer?
        throw "A buffer is required."

      $first = this.first().empty()
      [width, height] = [$first.width(), $first.height()]

      # Create a div to hold the current data view.
      $data     = $("<div style='width: #{width}px; height: #{height}px' />").appendTo($first)
      # And create an overlay div to allow for scrolling.
      $scroller = $("<div style='width: #{width}px; height: #{height}px' />")
                    .css(position: 'relative', top: "-#{height}px", overflow: 'auto')
                    .appendTo($first)

      # Gets the dimensions of a single character in the container's font.
      measureSingleCharacter = ->
        $measure = $('<span />').css('visibility', 'hidden').appendTo($data)

        # Measure a single character.
        $measure.text('0')
        [charWidth, charHeight] = [$measure.width(), $measure.height()]

        # Now measure a longer string and get the average for a single
        # character to ensure that this is a fixed width font.
        $measure.text(MEASUREMENT_TEST_STRING)
        averageCharWidth = $measure.width() / MEASUREMENT_TEST_STRING.length
        unless charWidth == averageCharWidth
          throw 'Font must be fixed width.'

        $measure.remove()
        { width: charWidth, height: charHeight }

      # Gets different sizes required for rendering.
      getSizes = (xStride) ->
        maxMemoryAddress    = buffer.length.toString(16)

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
        if calculateStride(addressGutterLength, bytesPerLine) > xStride
          throw 'Container must be sufficiently wide to display at least one byte.'

        # Add bytes to fill the remaining space.
        while calculateStride(addressGutterLength, bytesPerLine + 1) <= xStride
          bytesPerLine++

        { addressGutterLength: addressGutterLength, bytesPerLine: bytesPerLine }

      # Renders the view for the given parameters.
      render = (address, addressGutterLength, bytesPerLine, numRows) ->

        # Adapted from:
        # http://www.discoded.com/2012/04/05/my-favorite-javascript-string-extensions-in-coffeescript/
        padLeft = (string, padString, length) ->
          while string.length < length
            string = padString + string
          string

        view = []
        for i in [0...numRows]
          rowAddress  = address + (i * bytesPerLine)
          rowAddressH = padLeft(rowAddress.toString(16), '0', addressGutterLength)

          bytes = []
          ascii = ''
          for index in [rowAddress...rowAddress + bytesPerLine]
            if index > buffer.length - 1
              # Last line. Append non-breaking spaces to pad bytes so the ascii still aligns.
              bytes.push String.fromCharCode(0xA0) + String.fromCharCode(0xA0)
            else
              byte  = if buffer[index]? then buffer[index] else '??'

              # Append the byte.
              bytes.push padLeft(byte.toString(16), 0, 2)
              # Append the char if it falls within the printable ASCII range, otherwise append a dot.
              ascii += if byte >= 0x20 and byte <= 0x7E then String.fromCharCode(byte) else '.'

          # Append the line.
          view.push "#{rowAddressH} #{bytes.join(' ')} #{ascii}"

        # Finally, render the view.
        $data.html view.join('<br/>')

      # Calculate the maximum number of characters per row and per column.
      fontDimensions = measureSingleCharacter()
      xStride        = Math.floor(width  / fontDimensions.width)
      yStride        = Math.floor(height / fontDimensions.height)

      # Calculate sizes.
      sizes = getSizes(xStride)

      # Create the scrollbar and set its height accordingly.
      scrollHeight = (Math.ceil(buffer.length / sizes.bytesPerLine) + 1) * fontDimensions.height
      $('<div/>').css('height', "#{scrollHeight}px").appendTo($scroller)

      # Initial render.
      render(0, sizes.addressGutterLength, sizes.bytesPerLine, yStride)

      # Render on scroll.
      $scroller.scroll (e) ->
        yIndex = Math.floor($(@).scrollTop() / fontDimensions.height)
        render(yIndex * sizes.bytesPerLine, sizes.addressGutterLength, sizes.bytesPerLine, yStride)

      # TODO: Add a mechanism to invalidate the current view if its underlying data changes.

      this
