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

    constructor: (element, disassembler) ->
      unless element?      then throw 'A containing element is required.'
      unless disassembler? then throw 'A disassembler is required.'

      @disassembly = disassembler.FormattedDisassembly()

      @$element = $(element).empty()
      # Create a div to hold the current data view,
      @$data     = $('<div/>').appendTo(@$element)
      # Create a second div and overlay it to allow for scrolling.
      @$scroller = $("<div style='position: relative; overflow: auto' />").appendTo(@$element)

      # Init
      @reset()
      @disassemblyLengthChanged()
      @$scroller.scroll => @refresh()

      @render 0

    refresh: ->
      lineIndex = Math.floor(@$scroller.scrollTop() / @fontHeight)
      @render lineIndex

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

      # Calculate vertical stride (# of chars per column).
      @fontHeight = @getFontHeight()
      @yStride    = Math.floor(height / @fontHeight)

      # Calculate address gutter length.
      lastInstruction = @disassembly[@disassembly.length - 1]
      maxMemoryAddress = lastInstruction.address.toString(16)
      @addressGutterLength = maxMemoryAddress.length

    # Recalculates the scrollbar's length.
    disassemblyLengthChanged: ->
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

    render: (address) ->
      padLeft = (string, padString, length) ->
        string = padString + string while string.length < length
        string

      view = []
      # Loop thru lines.
      for y in [0...@yStride]
        instruction = @disassembly[address + y]
        lineAddress = padLeft(instruction.address.toString(16), '0', @addressGutterLength)        
        view.push "<span style='color: blue'>#{lineAddress}</span> #{instruction.mnemonic}"

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
