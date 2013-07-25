class Timer
  MMU: null

  remainingCycles: 0
  divRemainingCycles: 0

  mainClock: 0
  divClock: 0

  totalClocks: 0

  constructor: (@MMU) ->
    unless @MMU?
      throw 'MMU is required.'

  step: (clocks) ->
    if window.boom
      @totalClocks += clocks

    # Increment by the last opcode's time
    @remainingCycles += clocks

    # The main clock increments at 1/4th the rate of the core's clock.

    # No opcode takes longer than 4 cycles,
    # so we only have to check once
    if @remainingCycles >= 4
      @remainingCycles -= 4
      @mainClock++

      # The DIV register increments at 1/16th the rate of the main clock
      @divClock++
      if @divClock == 16
        @divClock = 0
        @MMU.Set 0xFF04, ((@MMU.Get(0xFF04) + 1) & 0xFF)

    @check()

  check: ->
    tac = @MMU.Get(0xFF07)
    if tac & 4 # enabled?
      threshold =
        switch tac & 3
          when 0 then 64 # 4k
          when 1 then 1  # 256k
          when 2 then 4  # 64k
          when 3 then 16 # 16k

      if @mainClock >= threshold
        @mainClock = 0
        tima = @MMU.Get(0xFF05)
        tima++

        if tima > 0xFF
          # At overflow, refill with the Modulo
          tima = @MMU.Get(0xFF06)
          @MMU.Set 0xFF05, tima

          # & flag an interrupt!
          @MMU.Regs.IF.TimerOverflow = true
        else
          @MMU.Set 0xFF05, tima


window.Timer = Timer
