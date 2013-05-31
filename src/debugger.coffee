class Debugger
  PC:         0
  codePaths:  []
  diassembly: []

  LoadCode: (buffer) ->
    unless buffer instanceof Uint8Array
      throw 'Input buffer must be of type Uint8Array.'

    @buffer = buffer
    @reset()
    @disassemble()

  reset: ->
    @PC          = 0
    @codePaths   = []
    @disassembly = []

  disassemble: ->
    unless @buffer?
      throw 'Code must be loaded using Debugger.LoadCode() first.'

    # Store the PC before the instruction is fetched.
    PC = @PC

    while mnemonic = @decodeOpcode()
      if typeof mnemonic == 'object'
        # Object, does it have a mnemonic?
        if mnemonic.label?
          @disassembly[PC] = mnemonic.label

        # This property flags the end of a code path.
        if mnemonic.end
          @PC = @codePaths.pop()
          break unless @PC?
      else
        # String, it's just the mnemonic.
        @disassembly[PC] = mnemonic

      # Again, store the PC before the next instruction is fetched.
      PC = @PC

    @disassembly

  trackCodeAtAddress: (address) ->
    unless @disassembly[address]?
      @codePaths.push address

    address.toString(16)

  # Unsigned

  getUint8: ->
    @buffer[@PC++]

  getUint16: ->
    @getUint8() + (@getUint8() << 8)

  # Signed

  getInt8: ->
    byte = @getUint8()

    # Two's complement
    sign = (byte >> 7) & 0x1
    if sign
      byte = -((byte ^ 0xFF) + 1)
    
    byte

  getRelInt8JmpAddress: ->
    # Order matters
    @getInt8() + @PC

  # To hex helpers

  getUint8H:             -> @getUint8().toString(16)
  getUint16H:            -> @getUint16().toString(16)
  getInt8H:              -> @getInt8().toString(16)
  getRelInt8JmpAddressH: -> @getRelInt8JmpAddress().toString(16)

  # Commands

  # Opcodes are gathered from:
  #   - http://meatfighter.com/gameboy/GBCPUman.pdf
  #   - http://imrannazar.com/Gameboy-Z80-Opcode-Map
  #
  # As a convention, an uppercase 'N' in the function's
  # name denotes a pointer.
  #
  LD_nn_n:    (reg)       -> "LD #{reg}, $#{@getUint8H()}"
  LD_r1_r2:   (reg, reg2) -> "LD #{reg}, #{reg2}"
  LD_A_n:     (reg)       -> "LD A, #{reg}"
  LD_A_NN:                -> "LD A, ($#{@getUint16H()})"
  LD_A_imm:               -> "LD A, $#{@getUint8H()}"
  LD_n_A:     (reg)       -> "LD #{reg}, A"
  LD_NN_A:                -> "LD ($#{@getUint16H()}), A"
  LDH_N_A:                -> "LDH ($#{@getUint8H()}), A"
  LDH_A_N:                -> "LDH A, ($#{@getUint8H()})"
  LD_n_nn:    (reg)       -> "LD #{reg}, $#{@getUint16H()}"
  LDHL_SP_n:              -> "LDHL SP, $#{@getUint8H()}"
  LD_NN_SP:               -> "LD ($#{@getUint16H()}), SP"
  PUSH_nn:    (reg)       -> "PUSH #{reg}"
  POP_nn:     (reg)       -> "POP #{reg}"
  ADD_A_n:    (reg)       -> "ADD A, #{reg}"
  ADD_A_imm:              -> "ADD A, $#{@getUint8H()}"
  ADC_A_n:    (reg)       -> "ADC A, #{reg}"
  ADC_A_imm:              -> "ADC A, $#{@getUint8H()}"
  SUB_n:      (reg)       -> "SUB #{reg}"
  SUB_imm:                -> "SUB $#{@getUint8H()}"
  SBC_A_n:    (reg)       -> "SBC A, #{reg}"
  SBC_A_imm:              -> "SBC A, $#{@getUint8H()}"
  AND_n:      (reg)       -> "AND #{reg}"
  AND_imm:                -> "AND $#{@getUint8H()}"
  OR_n:       (reg)       -> "OR #{reg}"
  OR_imm:                 -> "OR $#{@getUint8H()}"
  XOR_n:      (reg)       -> "XOR #{reg}"
  XOR_imm:                -> "XOR $#{@getUint8H()}"
  CP_n:       (reg)       -> "CP #{reg}"
  CP_imm:                 -> "CP $#{@getUint8H()}"
  INC_n:      (reg)       -> "INC #{reg}"
  DEC_n:      (reg)       -> "DEC #{reg}"
  ADD_HL_n:   (reg)       -> "ADD HL, #{reg}"
  ADD_SP_imm:             -> "ADD SP, $#{@getUint8H()}"
  RST_n:      (add)       -> "RST $#{add}"
  RET_cc:     (cond)      -> "RET #{cond}"

  # Jumps are loosely tracked to avoid disassembling data:

  # Non-conditional jumps end the current code path.
  JP_nn: ->
    addressH = @trackCodeAtAddress(@getUint16())
    { label: "JP $#{addressH}", end: true }

  JR_n: ->
    addressH = @trackCodeAtAddress(@getRelInt8JmpAddress())
    { label: "JR $#{addressH}", end: true }

  # Track conditional jump code paths.
  JP_cc_nn: (cond) ->
    addressH = @trackCodeAtAddress(@getUint16())
    "JP #{cond}, $#{addressH}"

  JR_cc_n: (cond) ->
    addressH = @trackCodeAtAddress(@getRelInt8JmpAddress())
    "JR #{cond}, $#{addressH}"

  # Track call code paths.
  CALL_nn: ->
    addressH = @trackCodeAtAddress(@getUint16())
    "CALL $#{addressH}"

  CALL_cc_nn: (cond) ->
    addressH = @trackCodeAtAddress(@getUint16())
    "CALL #{cond}, $#{addressH}"

  # Returns end the current code path.
  RET:  -> { label: 'RET',  end: true }
  RETI: -> { label: 'RETI', end: true }

  # Extended operations
  SWAP_n: (reg) -> "SWAP #{reg}"
  RLC_n:  (reg) -> "RLC #{reg}"
  RL_n:   (reg) -> "RL #{reg}"
  RRC_n:  (reg) -> "RRC #{reg}"
  RR_n:   (reg) -> "RR #{reg}"
  SLA_n:  (reg) -> "SLA #{reg}"
  SRA_n:  (reg) -> "SRA #{reg}"
  SRL_n:  (reg) -> "SRL #{reg}"

  decodeOpcode: ->
    opcode = @getUint8()
    unless opcode?
      return end: true

    # TODO: (or not): The following is repetitive. Eventually we might want
    #                 to refactor this by dynamically creating a jump table
    #                 of sorts, although I do like the simplicity and
    #                 readability of the current approach.
    switch opcode

      # LD nn, n
      when 0x06 then @LD_nn_n('B')
      when 0x0E then @LD_nn_n('C')
      when 0x16 then @LD_nn_n('D')
      when 0x1E then @LD_nn_n('E')
      when 0x26 then @LD_nn_n('H')
      when 0x2E then @LD_nn_n('L')
      when 0x36 then @LD_nn_n('(HL)')

      # LD r1, r2

      when 0x40 then @LD_r1_r2('B', 'B')
      when 0x41 then @LD_r1_r2('B', 'C')
      when 0x42 then @LD_r1_r2('B', 'D')
      when 0x43 then @LD_r1_r2('B', 'E')
      when 0x44 then @LD_r1_r2('B', 'H')
      when 0x45 then @LD_r1_r2('B', 'L')
      when 0x46 then @LD_r1_r2('B', '(HL)')

      when 0x48 then @LD_r1_r2('C', 'B')
      when 0x49 then @LD_r1_r2('C', 'C')
      when 0x4A then @LD_r1_r2('C', 'D')
      when 0x4B then @LD_r1_r2('C', 'E')
      when 0x4C then @LD_r1_r2('C', 'H')
      when 0x4D then @LD_r1_r2('C', 'L')
      when 0x4E then @LD_r1_r2('C', '(HL)')

      when 0x50 then @LD_r1_r2('D', 'B')
      when 0x51 then @LD_r1_r2('D', 'C')
      when 0x52 then @LD_r1_r2('D', 'D')
      when 0x53 then @LD_r1_r2('D', 'E')
      when 0x54 then @LD_r1_r2('D', 'H')
      when 0x55 then @LD_r1_r2('D', 'L')
      when 0x56 then @LD_r1_r2('D', '(HL)')

      when 0x58 then @LD_r1_r2('E', 'B')
      when 0x59 then @LD_r1_r2('E', 'C')
      when 0x5A then @LD_r1_r2('E', 'D')
      when 0x5B then @LD_r1_r2('E', 'E')
      when 0x5C then @LD_r1_r2('E', 'H')
      when 0x5D then @LD_r1_r2('E', 'L')
      when 0x5E then @LD_r1_r2('E', '(HL)')

      when 0x60 then @LD_r1_r2('H', 'B')
      when 0x61 then @LD_r1_r2('H', 'C')
      when 0x62 then @LD_r1_r2('H', 'D')
      when 0x63 then @LD_r1_r2('H', 'E')
      when 0x64 then @LD_r1_r2('H', 'H')
      when 0x65 then @LD_r1_r2('H', 'L')
      when 0x66 then @LD_r1_r2('H', '(HL)')

      when 0x68 then @LD_r1_r2('L', 'B')
      when 0x69 then @LD_r1_r2('L', 'C')
      when 0x6A then @LD_r1_r2('L', 'D')
      when 0x6B then @LD_r1_r2('L', 'E')
      when 0x6C then @LD_r1_r2('L', 'H')
      when 0x6D then @LD_r1_r2('L', 'L')
      when 0x6E then @LD_r1_r2('L', '(HL)')

      when 0x70 then @LD_r1_r2('(HL)', 'B')
      when 0x71 then @LD_r1_r2('(HL)', 'C')
      when 0x72 then @LD_r1_r2('(HL)', 'D')
      when 0x73 then @LD_r1_r2('(HL)', 'E')
      when 0x74 then @LD_r1_r2('(HL)', 'H')
      when 0x75 then @LD_r1_r2('(HL)', 'L')

      # LD A, n
      when 0x7F then @LD_A_n('A')
      when 0x78 then @LD_A_n('B')
      when 0x79 then @LD_A_n('C')
      when 0x7A then @LD_A_n('D')
      when 0x7B then @LD_A_n('E')
      when 0x7C then @LD_A_n('H')
      when 0x7D then @LD_A_n('L')
      when 0x0A then @LD_A_n('(BC)')
      when 0x1A then @LD_A_n('(DE)')
      when 0x7E then @LD_A_n('(HL)')
      when 0xFA then @LD_A_NN()
      when 0x3E then @LD_A_imm()

      # LD n, A
      when 0x47 then @LD_n_A('B')
      when 0x4F then @LD_n_A('C')
      when 0x57 then @LD_n_A('D')
      when 0x5F then @LD_n_A('E')
      when 0x67 then @LD_n_A('H')
      when 0x6F then @LD_n_A('L')
      when 0x02 then @LD_n_A('(BC)')
      when 0x12 then @LD_n_A('(DE)')
      when 0x77 then @LD_n_A('(HL)')
      when 0xEA then @LD_NN_A()

      # LD A, (C)
      when 0xF2 then 'LD A, ($FF00 + C)' # This does not appear in some docs, but seems valid.
      # LD (C), A
      when 0xE2 then 'LD ($FF00 + C), A'
      # LDD A, (HL)
      when 0x3A then 'LDD A, (HL)'
      # LDD (HL), A
      when 0x32 then 'LDD (HL), A'
      # LDI A, (HL)
      when 0x2A then 'LDI A, (HL)'
      # LDI (HL), A
      when 0x22 then 'LDI (HL), A'
      # LDH (n), A
      when 0xE0 then @LDH_N_A()
      # LDH A, (n)
      when 0xF0 then @LDH_A_N()

      # LD n, nn
      when 0x01 then @LD_n_nn('BC')
      when 0x11 then @LD_n_nn('DE')
      when 0x21 then @LD_n_nn('HL')
      when 0x31 then @LD_n_nn('SP')

      # LD SP, HL
      when 0xF9 then 'LD SP, HL'
      # LDHL SP, n
      when 0xF8 then @LDHL_SP_n()
      # LD (nn), SP
      when 0x08 then @LD_NN_SP()

      # PUSH nn
      when 0xF5 then @PUSH_nn('AF')
      when 0xC5 then @PUSH_nn('BC')
      when 0xD5 then @PUSH_nn('DE')
      when 0xE5 then @PUSH_nn('HL')

      # POP nn
      when 0xF1 then @POP_nn('AF')
      when 0xC1 then @POP_nn('BC')
      when 0xD1 then @POP_nn('DE')
      when 0xE1 then @POP_nn('HL')

      # ADD A, n
      when 0x87 then @ADD_A_n('A')
      when 0x80 then @ADD_A_n('B')
      when 0x81 then @ADD_A_n('C')
      when 0x82 then @ADD_A_n('D')
      when 0x83 then @ADD_A_n('E')
      when 0x84 then @ADD_A_n('H')
      when 0x85 then @ADD_A_n('L')
      when 0x86 then @ADD_A_n('(HL)')
      when 0xC6 then @ADD_A_imm()

      # ADC A, n
      when 0x8F then @ADC_A_n('A')
      when 0x88 then @ADC_A_n('B')
      when 0x89 then @ADC_A_n('C')
      when 0x8A then @ADC_A_n('D')
      when 0x8B then @ADC_A_n('E')
      when 0x8C then @ADC_A_n('H')
      when 0x8D then @ADC_A_n('L')
      when 0x8E then @ADC_A_n('(HL)')
      when 0xCE then @ADC_A_imm()

      # SUB n
      when 0x97 then @SUB_n('A')
      when 0x90 then @SUB_n('B')
      when 0x91 then @SUB_n('C')
      when 0x92 then @SUB_n('D')
      when 0x93 then @SUB_n('E')
      when 0x94 then @SUB_n('H')
      when 0x95 then @SUB_n('L')
      when 0x96 then @SUB_n('(HL)')
      when 0xD6 then @SUB_imm()

      # SBC A, n
      when 0x9F then @SBC_A_n('A')
      when 0x98 then @SBC_A_n('B')
      when 0x99 then @SBC_A_n('C')
      when 0x9A then @SBC_A_n('D')
      when 0x9B then @SBC_A_n('E')
      when 0x9C then @SBC_A_n('H')
      when 0x9D then @SBC_A_n('L')
      when 0x9E then @SBC_A_n('(HL)')
      when 0xDE then @SBC_A_imm()

      # AND n
      when 0xA7 then @AND_n('A')
      when 0xA0 then @AND_n('B')
      when 0xA1 then @AND_n('C')
      when 0xA2 then @AND_n('D')
      when 0xA3 then @AND_n('E')
      when 0xA4 then @AND_n('H')
      when 0xA5 then @AND_n('L')
      when 0xA6 then @AND_n('(HL)')
      when 0xE6 then @AND_imm()

      # OR n
      when 0xB7 then @OR_n('A')
      when 0xB0 then @OR_n('B')
      when 0xB1 then @OR_n('C')
      when 0xB2 then @OR_n('D')
      when 0xB3 then @OR_n('E')
      when 0xB4 then @OR_n('H')
      when 0xB5 then @OR_n('L')
      when 0xB6 then @OR_n('(HL)')
      when 0xF6 then @OR_imm()

      # XOR n
      when 0xAF then @XOR_n('A')
      when 0xA8 then @XOR_n('B')
      when 0xA9 then @XOR_n('C')
      when 0xAA then @XOR_n('D')
      when 0xAB then @XOR_n('E')
      when 0xAC then @XOR_n('H')
      when 0xAD then @XOR_n('L')
      when 0xAE then @XOR_n('(HL)')
      when 0xEE then @XOR_imm()

      # CP n
      when 0xBF then @CP_n('A')
      when 0xB8 then @CP_n('B')
      when 0xB9 then @CP_n('C')
      when 0xBA then @CP_n('D')
      when 0xBB then @CP_n('E')
      when 0xBC then @CP_n('H')
      when 0xBD then @CP_n('L')
      when 0xBE then @CP_n('(HL)')
      when 0xFE then @CP_imm()

      # INC n
      when 0x3C then @INC_n('A')
      when 0x04 then @INC_n('B')
      when 0x0C then @INC_n('C')
      when 0x14 then @INC_n('D')
      when 0x1C then @INC_n('E')
      when 0x24 then @INC_n('H')
      when 0x2C then @INC_n('L')
      when 0x34 then @INC_n('(HL)')

      # DEC n
      when 0x3D then @DEC_n('A')
      when 0x05 then @DEC_n('B')
      when 0x0D then @DEC_n('C')
      when 0x15 then @DEC_n('D')
      when 0x1D then @DEC_n('E')
      when 0x25 then @DEC_n('H')
      when 0x2D then @DEC_n('L')
      when 0x35 then @DEC_n('(HL)')

      # ADD HL, n
      when 0x09 then @ADD_HL_n('BC')
      when 0x19 then @ADD_HL_n('DE')
      when 0x29 then @ADD_HL_n('HL')
      when 0x39 then @ADD_HL_n('SP')

      # ADD SP, n
      when 0xE8 then @ADD_SP_imm()

      # INC nn
      when 0x03 then @INC_n('BC')
      when 0x13 then @INC_n('DE')
      when 0x23 then @INC_n('HL')
      when 0x33 then @INC_n('SP')

      # DEC nn
      when 0x0B then @DEC_n('BC')
      when 0x1B then @DEC_n('DE')
      when 0x2B then @DEC_n('HL')
      when 0x3C then @DEC_n('SP')

      # DAA
      when 0x27 then 'DAA'
      # CPL
      when 0x2F then 'CPL'
      # CCF
      when 0x3F then 'CCF'
      # SCF
      when 0x37 then 'SCF'
      # NOP
      when 0x00 then 'NOP'
      # HALT
      when 0x76 then 'HALT'
      # STOP
      when 0x10 then 'STOP' # Does this require a NOP to follow?
      # DI
      when 0xF3 then 'DI'
      # EI
      when 0xFB then 'EI'
      # RLCA
      when 0x07 then 'RLCA'
      # RLA
      when 0x17 then 'RLA'
      # RRCA
      when 0x0F then 'RRCA'
      # RRA
      when 0x1F then 'RRA'

      # JP nn
      when 0xC3 then @JP_nn()

      # JP cc, nn
      when 0xC2 then @JP_cc_nn('NZ')
      when 0xCA then @JP_cc_nn('Z')
      when 0xD2 then @JP_cc_nn('NC')
      when 0xDA then @JP_cc_nn('C')

      # JP (HL)
      when 0xE9 then 'JP (HL)'
      # JR n
      when 0x18 then @JR_n()

      # JR cc, n
      when 0x20 then @JR_cc_n('NZ')
      when 0x28 then @JR_cc_n('Z')
      when 0x30 then @JR_cc_n('NC')
      when 0x38 then @JR_cc_n('C')

      # CALL nn
      when 0xCD then @CALL_nn()

      # CALL cc, nn
      when 0xC4 then @CALL_cc_nn('NZ')
      when 0xCC then @CALL_cc_nn('Z')
      when 0xD4 then @CALL_cc_nn('NC')
      when 0xDC then @CALL_cc_nn('C')

      # RST n
      when 0xC7 then @RST_n(0x00)
      when 0xCF then @RST_n(0x08)
      when 0xD7 then @RST_n(0x10)
      when 0xDF then @RST_n(0x18)
      when 0xE7 then @RST_n(0x20)
      when 0xEF then @RST_n(0x28)
      when 0xF7 then @RST_n(0x30)
      when 0xFF then @RST_n(0x38)

      # RET
      when 0xC9 then @RET()

      # RET cc
      when 0xC0 then @RET_cc('NZ')
      when 0xC8 then @RET_cc('Z')
      when 0xD0 then @RET_cc('NC')
      when 0xD8 then @RET_cc('C')

      # RETI
      when 0xD9 then @RETI()

      # Ext ops
      when 0xCB
        opcode2 = @getUint8()

        switch opcode2

          # SWAP n
          when 0x37 then @SWAP_n('A')
          when 0x30 then @SWAP_n('B')
          when 0x31 then @SWAP_n('C')
          when 0x32 then @SWAP_n('D')
          when 0x33 then @SWAP_n('E')
          when 0x34 then @SWAP_n('H')
          when 0x35 then @SWAP_n('L')
          when 0x36 then @SWAP_n('(HL)')

          # RLC n
          when 0x07 then @RLC_n('A')
          when 0x00 then @RLC_n('B')
          when 0x01 then @RLC_n('C')
          when 0x02 then @RLC_n('D')
          when 0x03 then @RLC_n('E')
          when 0x04 then @RLC_n('H')
          when 0x05 then @RLC_n('L')
          when 0x06 then @RLC_n('(HL)')

          # RL n
          when 0x17 then @RL_n('A')
          when 0x10 then @RL_n('B')
          when 0x11 then @RL_n('C')
          when 0x12 then @RL_n('D')
          when 0x13 then @RL_n('E')
          when 0x14 then @RL_n('H')
          when 0x15 then @RL_n('L')
          when 0x16 then @RL_n('(HL)')

          # RRC n
          when 0x0F then @RRC_n('A')
          when 0x08 then @RRC_n('B')
          when 0x09 then @RRC_n('C')
          when 0x0A then @RRC_n('D')
          when 0x0B then @RRC_n('E')
          when 0x0C then @RRC_n('H')
          when 0x0D then @RRC_n('L')
          when 0x0E then @RRC_n('(HL)')

          # RR n
          when 0x1F then @RR_n('A')
          when 0x18 then @RR_n('B')
          when 0x19 then @RR_n('C')
          when 0x1A then @RR_n('D')
          when 0x1B then @RR_n('E')
          when 0x1C then @RR_n('H')
          when 0x1D then @RR_n('L')
          when 0x1E then @RR_n('(HL)')

          # SLA n
          when 0x27 then @SLA_n('A')
          when 0x20 then @SLA_n('B')
          when 0x21 then @SLA_n('C')
          when 0x22 then @SLA_n('D')
          when 0x23 then @SLA_n('E')
          when 0x24 then @SLA_n('H')
          when 0x25 then @SLA_n('L')
          when 0x26 then @SLA_n('(HL)')

          # SRA n
          when 0x2F then @SRA_n('A')
          when 0x28 then @SRA_n('B')
          when 0x29 then @SRA_n('C')
          when 0x2A then @SRA_n('D')
          when 0x2B then @SRA_n('E')
          when 0x2C then @SRA_n('H')
          when 0x2D then @SRA_n('L')
          when 0x2E then @SRA_n('(HL)')

          # SRL n
          when 0x3F then @SRL_n('A')
          when 0x38 then @SRL_n('B')
          when 0x39 then @SRL_n('C')
          when 0x3A then @SRL_n('D')
          when 0x3B then @SRL_n('E')
          when 0x3C then @SRL_n('H')
          when 0x3D then @SRL_n('L')
          when 0x3E then @SRL_n('(HL)')

          else
            unless opcode2 >= 0x40
              throw "Unknown opcode: 0xCB 0x#{opcode2.toString(16)}"

            # Command
            mnemonic =
              if opcode2 >= 0x40 and opcode2 <= 0x7F
                'BIT'
              else if opcode2 >= 0x80 and opcode2 <= 0xBF
                'RES'
              else if opcode2 >= 0xC0 and opcode2 <= 0xFF
                'SET'
            
            # Bit
            bit = (opcode2 >> 3) & 0x7
            mnemonic += " #{bit}"

            # Register
            registers = ['B', 'C', 'D', 'E', 'H', 'L', '(HL)', 'A']
            register  = registers[opcode2 & 0x7]
            mnemonic += ", #{register}"

            mnemonic

      else
        throw "Unknown opcode: 0x#{opcode.toString(16)}"


window.Debugger = Debugger
