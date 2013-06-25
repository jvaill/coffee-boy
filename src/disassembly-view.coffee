do ($ = jQuery) =>

  PLUGIN_NAMESPACE = 'DISASSEMBLY_VIEW'

  class DisassemblyView
    $element:  null
    $data:     null
    $scroller: null

    disassembly:         null
    fontHeight:          null
    yStride:             null
    addressGutterLength: null

    PC:          null
    breakpoints: null

    constructor: (element, @disassembler) ->
      unless element?      then throw 'A containing element is required.'
      unless @disassembler? then throw 'A disassembler is required.'

      @$element = $(element).empty()
      # Create a div to hold the current data view.
      @$data     = $('<div/>').appendTo(@$element)
      # Create a second div and overlay it to allow for scrolling.
      @$scroller = $("<div style='position: relative; overflow: auto' />").appendTo(@$element)

      # Init.
      @Reset()
      @DisassemblyLengthChanged()
      @$scroller.scroll => @Refresh()

      # Breakpoints.
      @$element.click (e) =>
        # Get the current view's starting index.
        lineIndex  = Math.floor(@$scroller.scrollTop() / @fontHeight)
        # Add the clicked line's index.
        lineIndex += Math.floor((e.offsetY - @$scroller.scrollTop()) / @fontHeight)
        # These two operations can't be combined because we need to call Math.floor() for each.

        address = @disassembly[lineIndex].address
        @toggleBreakpoint address
        @Refresh()

      @Refresh()

    SetPC: (@PC) ->
      @Refresh()

    Refresh: ->
      lineIndex = Math.floor(@$scroller.scrollTop() / @fontHeight)
      @render lineIndex

    GetBreakpoints: (cb) ->
      cb? @breakpoints

    Reset: ->
      @disassembly = @disassembler.Disassembly()

      [width, height] = [@$element.width(), @$element.height()]
      @PC          = null
      @breakpoints = {}

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

      # Calculate vertical stride (# of chars per column).
      @fontHeight = @getFontHeight()
      @yStride    = Math.floor(height / @fontHeight)

      # Calculate address gutter length.
      lastInstruction = @disassembly[@disassembly.length - 1]
      maxMemoryAddress = lastInstruction.address.toString(16)
      @addressGutterLength = maxMemoryAddress.length

    # Recalculates the scrollbar's length.
    DisassemblyLengthChanged: ->
      @disassembly = @disassembler.Disassembly()

      @$scroller.empty()
      # Create a scrollbar and set its height accordingly.
      scrollHeight = @disassembly.length * @fontHeight
      @$scroller.append $("<div style='height: #{scrollHeight}px' />")

    getFontHeight: ->
      $measure = $("<span style='visibility: hidden' />").appendTo(@$data)

      # Measure a single character.
      $measure.text('0')
      fontHeight = $measure.height()
      
      $measure.remove()
      fontHeight

    toggleBreakpoint: (address) ->
      if @breakpoints[address]?
        delete @breakpoints[address]
      else
        @breakpoints[address] = true

    render: (startIndex) ->
      padLeft = (string, length) ->
        string = "0#{string}" while string.length < length
        string

      view = []
      # Loop thru lines.
      for y in [0...@yStride]
        instruction = @disassembly[startIndex + y]
        address     = padLeft(instruction.address.toString(16), @addressGutterLength)
        
        line = "<span style='color: blue'>#{address}</span> #{instruction.mnemonic}"

        color =
          if @PC == instruction.address and @breakpoints[instruction.address]
            'Khaki'
          # Highlight the currently executing instruction.
          else if @PC == instruction.address
            'PowderBlue'
          # Highlight breakpoints.
          else if @breakpoints[instruction.address]
            'Tomato'

        if color?
          line = "<div style='background-color: #{color}; display: inline-block; width: 100%'>#{line}</div>"

        view.push line

      # Render.
      @$data.html view.join('<br/>')

  $.fn.extend
    disassemblyView: (disassembly) ->
      if typeof disassembly == 'string' and $(@).data(PLUGIN_NAMESPACE)?
        # Call a method on the original instance.
        method = disassembly
        instance = $(@).data(PLUGIN_NAMESPACE)
        instance[method].apply instance, Array.prototype.slice.call(arguments, 1)
      else
        # Create an instance.
        instance = new DisassemblyView(this, disassembly)
        $(@).data(PLUGIN_NAMESPACE, instance)

      this
