class Disassembler
  PC:         null
  buffer:     null
  codePaths:  null
  diassembly: null

  constructor: (@buffer) ->
    unless @buffer?
      throw 'A buffer is required.'
    unless @buffer instanceof Uint8Array
      throw 'Buffer must be of type Uint8Array.'

    @loadCode buffer

  Disassembly: ->
    disassembly = []

    for address in [0...@disassembly.length]
      mnemonic = @disassembly[address]

      if mnemonic?
        disassembly.push {
          address:  address
          mnemonic: mnemonic
        }

    disassembly

  loadCode: (@buffer) ->
    @reset()
    @disassemble()

  reset: ->
    @PC          = 0
    @codePaths   = [0]
    @disassembly = []

  disassemble: ->
    @PC = @codePaths.pop()
    return unless @PC?

    # Store the PC before the instruction is fetched
    PC = @PC

    while mnemonic = @decodeOpcode()
      if typeof mnemonic == 'object'
        # Object, does it have a mnemonic?
        if mnemonic.label?
          @disassembly[PC] = mnemonic.label

        # This property flags the end of a code path
        if mnemonic.end
          @PC = @codePaths.pop()
          break unless @PC?
      else
        # String, it's just the mnemonic
        @disassembly[PC] = mnemonic

      # Store the PC before the next instruction is fetched
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
  #   - http://www.scribd.com/doc/39999184/GameBoy-Programming-Manual
  #
  # As conventions:
  #   - 'r' represents a register
  #   - 'n' represents a byte
  #   - 'rr' represents a pair of registers
  #   - 'nn' represents a 16 bit integer
  #   - 'cc' represents a condition
  #   - Uppercase characters denote a pointer
  #
  LD_r_n:     (reg)       -> "LD #{reg}, $#{@getUint8H()}"
  LD_r_r2:    (reg, reg2) -> "LD #{reg}, #{reg2}"
  LD_A_r:     (reg)       -> "LD A, #{reg}"
  LD_A_NN:                -> "LD A, ($#{@getUint16H()})"
  LD_A_n:                 -> "LD A, $#{@getUint8H()}"
  LD_r_A:     (reg)       -> "LD #{reg}, A"
  LD_NN_A:                -> "LD ($#{@getUint16H()}), A"
  LDH_N_A:                -> "LD ($FF00 + $#{@getUint8H()}), A"
  LDH_A_N:                -> "LD A, ($FF00 + $#{@getUint8H()})"
  LD_r_nn:    (reg)       -> "LD #{reg}, $#{@getUint16H()}"
  LDHL_SP_n:              -> "LDHL SP, $#{@getUint8H()}"
  LD_NN_SP:               -> "LD ($#{@getUint16H()}), SP"
  PUSH_r:     (reg)       -> "PUSH #{reg}"
  POP_r:      (reg)       -> "POP #{reg}"
  ADD_A_r:    (reg)       -> "ADD A, #{reg}"
  ADD_A_n:                -> "ADD A, $#{@getUint8H()}"
  ADC_A_r:    (reg)       -> "ADC A, #{reg}"
  ADC_A_n:                -> "ADC A, $#{@getUint8H()}"
  SUB_r:      (reg)       -> "SUB #{reg}"
  SUB_n:                  -> "SUB $#{@getUint8H()}"
  SBC_A_r:    (reg)       -> "SBC A, #{reg}"
  SBC_A_n:                -> "SBC A, $#{@getUint8H()}"
  AND_r:      (reg)       -> "AND #{reg}"
  AND_n:                  -> "AND $#{@getUint8H()}"
  OR_r:       (reg)       -> "OR #{reg}"
  OR_n:                   -> "OR $#{@getUint8H()}"
  XOR_r:      (reg)       -> "XOR #{reg}"
  XOR_n:                  -> "XOR $#{@getUint8H()}"
  CP_r:       (reg)       -> "CP #{reg}"
  CP_n:                   -> "CP $#{@getUint8H()}"
  INC_r:      (reg)       -> "INC #{reg}"
  DEC_r:      (reg)       -> "DEC #{reg}"
  ADD_HL_r:   (reg)       -> "ADD HL, #{reg}"
  ADD_SP_n:               -> "ADD SP, $#{@getUint8H()}"
  RST:        (add)       -> "RST $#{add}"
  RET_cc:     (cond)      -> "RET #{cond}"

  # Jumps are loosely tracked to avoid disassembling data:

  # Non-conditional jumps end the current code path
  JP_nn: ->
    addressH = @trackCodeAtAddress(@getUint16())
    { label: "JP $#{addressH}", end: true }

  JR_n: ->
    addressH = @trackCodeAtAddress(@getRelInt8JmpAddress())
    { label: "JR $#{addressH}", end: true }

  # Track conditional jump code paths
  JP_cc_nn: (cond) ->
    addressH = @trackCodeAtAddress(@getUint16())
    "JP #{cond}, $#{addressH}"

  JR_cc_n: (cond) ->
    addressH = @trackCodeAtAddress(@getRelInt8JmpAddress())
    "JR #{cond}, $#{addressH}"

  # Track call code paths
  CALL_nn: ->
    addressH = @trackCodeAtAddress(@getUint16())
    "CALL $#{addressH}"

  CALL_cc_nn: (cond) ->
    addressH = @trackCodeAtAddress(@getUint16())
    "CALL #{cond}, $#{addressH}"

  # Returns end the current code path
  RET:  -> { label: 'RET',  end: true }
  RETI: -> { label: 'RETI', end: true }

  # Extended operations
  SWAP_r: (reg) -> "SWAP #{reg}"
  RLC_r:  (reg) -> "RLC #{reg}"
  RL_r:   (reg) -> "RL #{reg}"
  RRC_r:  (reg) -> "RRC #{reg}"
  RR_r:   (reg) -> "RR #{reg}"
  SLA_r:  (reg) -> "SLA #{reg}"
  SRA_r:  (reg) -> "SRA #{reg}"
  SRL_r:  (reg) -> "SRL #{reg}"

  decodeOpcode: ->
    opcode = @getUint8()
    unless opcode?
      return { end: true }

    switch opcode

      # LD nn, n
      when 0x06 then @LD_r_n('B')
      when 0x0E then @LD_r_n('C')
      when 0x16 then @LD_r_n('D')
      when 0x1E then @LD_r_n('E')
      when 0x26 then @LD_r_n('H')
      when 0x2E then @LD_r_n('L')
      when 0x36 then @LD_r_n('(HL)')

      # LD r1, r2

      when 0x40 then @LD_r_r2('B', 'B')
      when 0x41 then @LD_r_r2('B', 'C')
      when 0x42 then @LD_r_r2('B', 'D')
      when 0x43 then @LD_r_r2('B', 'E')
      when 0x44 then @LD_r_r2('B', 'H')
      when 0x45 then @LD_r_r2('B', 'L')
      when 0x46 then @LD_r_r2('B', '(HL)')

      when 0x48 then @LD_r_r2('C', 'B')
      when 0x49 then @LD_r_r2('C', 'C')
      when 0x4A then @LD_r_r2('C', 'D')
      when 0x4B then @LD_r_r2('C', 'E')
      when 0x4C then @LD_r_r2('C', 'H')
      when 0x4D then @LD_r_r2('C', 'L')
      when 0x4E then @LD_r_r2('C', '(HL)')

      when 0x50 then @LD_r_r2('D', 'B')
      when 0x51 then @LD_r_r2('D', 'C')
      when 0x52 then @LD_r_r2('D', 'D')
      when 0x53 then @LD_r_r2('D', 'E')
      when 0x54 then @LD_r_r2('D', 'H')
      when 0x55 then @LD_r_r2('D', 'L')
      when 0x56 then @LD_r_r2('D', '(HL)')

      when 0x58 then @LD_r_r2('E', 'B')
      when 0x59 then @LD_r_r2('E', 'C')
      when 0x5A then @LD_r_r2('E', 'D')
      when 0x5B then @LD_r_r2('E', 'E')
      when 0x5C then @LD_r_r2('E', 'H')
      when 0x5D then @LD_r_r2('E', 'L')
      when 0x5E then @LD_r_r2('E', '(HL)')

      when 0x60 then @LD_r_r2('H', 'B')
      when 0x61 then @LD_r_r2('H', 'C')
      when 0x62 then @LD_r_r2('H', 'D')
      when 0x63 then @LD_r_r2('H', 'E')
      when 0x64 then @LD_r_r2('H', 'H')
      when 0x65 then @LD_r_r2('H', 'L')
      when 0x66 then @LD_r_r2('H', '(HL)')

      when 0x68 then @LD_r_r2('L', 'B')
      when 0x69 then @LD_r_r2('L', 'C')
      when 0x6A then @LD_r_r2('L', 'D')
      when 0x6B then @LD_r_r2('L', 'E')
      when 0x6C then @LD_r_r2('L', 'H')
      when 0x6D then @LD_r_r2('L', 'L')
      when 0x6E then @LD_r_r2('L', '(HL)')

      when 0x70 then @LD_r_r2('(HL)', 'B')
      when 0x71 then @LD_r_r2('(HL)', 'C')
      when 0x72 then @LD_r_r2('(HL)', 'D')
      when 0x73 then @LD_r_r2('(HL)', 'E')
      when 0x74 then @LD_r_r2('(HL)', 'H')
      when 0x75 then @LD_r_r2('(HL)', 'L')

      # LD A, n
      when 0x7F then @LD_A_r('A')
      when 0x78 then @LD_A_r('B')
      when 0x79 then @LD_A_r('C')
      when 0x7A then @LD_A_r('D')
      when 0x7B then @LD_A_r('E')
      when 0x7C then @LD_A_r('H')
      when 0x7D then @LD_A_r('L')
      when 0x0A then @LD_A_r('(BC)')
      when 0x1A then @LD_A_r('(DE)')
      when 0x7E then @LD_A_r('(HL)')
      when 0xFA then @LD_A_NN()
      when 0x3E then @LD_A_n()

      # LD n, A
      when 0x47 then @LD_r_A('B')
      when 0x4F then @LD_r_A('C')
      when 0x57 then @LD_r_A('D')
      when 0x5F then @LD_r_A('E')
      when 0x67 then @LD_r_A('H')
      when 0x6F then @LD_r_A('L')
      when 0x02 then @LD_r_A('(BC)')
      when 0x12 then @LD_r_A('(DE)')
      when 0x77 then @LD_r_A('(HL)')
      when 0xEA then @LD_NN_A()

      # LDH A, (C)
      when 0xF2 then 'LD A, ($FF00 + C)'
      # LDH (C), A
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
      when 0x01 then @LD_r_nn('BC')
      when 0x11 then @LD_r_nn('DE')
      when 0x21 then @LD_r_nn('HL')
      when 0x31 then @LD_r_nn('SP')

      # LD SP, HL
      when 0xF9 then 'LD SP, HL'
      # LDHL SP, n
      when 0xF8 then @LDHL_SP_n()
      # LD (nn), SP
      when 0x08 then @LD_NN_SP()

      # PUSH nn
      when 0xF5 then @PUSH_r('AF')
      when 0xC5 then @PUSH_r('BC')
      when 0xD5 then @PUSH_r('DE')
      when 0xE5 then @PUSH_r('HL')

      # POP nn
      when 0xF1 then @POP_r('AF')
      when 0xC1 then @POP_r('BC')
      when 0xD1 then @POP_r('DE')
      when 0xE1 then @POP_r('HL')

      # ADD A, n
      when 0x87 then @ADD_A_r('A')
      when 0x80 then @ADD_A_r('B')
      when 0x81 then @ADD_A_r('C')
      when 0x82 then @ADD_A_r('D')
      when 0x83 then @ADD_A_r('E')
      when 0x84 then @ADD_A_r('H')
      when 0x85 then @ADD_A_r('L')
      when 0x86 then @ADD_A_r('(HL)')
      when 0xC6 then @ADD_A_n()

      # ADC A, n
      when 0x8F then @ADC_A_r('A')
      when 0x88 then @ADC_A_r('B')
      when 0x89 then @ADC_A_r('C')
      when 0x8A then @ADC_A_r('D')
      when 0x8B then @ADC_A_r('E')
      when 0x8C then @ADC_A_r('H')
      when 0x8D then @ADC_A_r('L')
      when 0x8E then @ADC_A_r('(HL)')
      when 0xCE then @ADC_A_n()

      # SUB n
      when 0x97 then @SUB_r('A')
      when 0x90 then @SUB_r('B')
      when 0x91 then @SUB_r('C')
      when 0x92 then @SUB_r('D')
      when 0x93 then @SUB_r('E')
      when 0x94 then @SUB_r('H')
      when 0x95 then @SUB_r('L')
      when 0x96 then @SUB_r('(HL)')
      when 0xD6 then @SUB_n()

      # SBC A, n
      when 0x9F then @SBC_A_r('A')
      when 0x98 then @SBC_A_r('B')
      when 0x99 then @SBC_A_r('C')
      when 0x9A then @SBC_A_r('D')
      when 0x9B then @SBC_A_r('E')
      when 0x9C then @SBC_A_r('H')
      when 0x9D then @SBC_A_r('L')
      when 0x9E then @SBC_A_r('(HL)')
      when 0xDE then @SBC_A_n()

      # AND n
      when 0xA7 then @AND_r('A')
      when 0xA0 then @AND_r('B')
      when 0xA1 then @AND_r('C')
      when 0xA2 then @AND_r('D')
      when 0xA3 then @AND_r('E')
      when 0xA4 then @AND_r('H')
      when 0xA5 then @AND_r('L')
      when 0xA6 then @AND_r('(HL)')
      when 0xE6 then @AND_n()

      # OR n
      when 0xB7 then @OR_r('A')
      when 0xB0 then @OR_r('B')
      when 0xB1 then @OR_r('C')
      when 0xB2 then @OR_r('D')
      when 0xB3 then @OR_r('E')
      when 0xB4 then @OR_r('H')
      when 0xB5 then @OR_r('L')
      when 0xB6 then @OR_r('(HL)')
      when 0xF6 then @OR_n()

      # XOR n
      when 0xAF then @XOR_r('A')
      when 0xA8 then @XOR_r('B')
      when 0xA9 then @XOR_r('C')
      when 0xAA then @XOR_r('D')
      when 0xAB then @XOR_r('E')
      when 0xAC then @XOR_r('H')
      when 0xAD then @XOR_r('L')
      when 0xAE then @XOR_r('(HL)')
      when 0xEE then @XOR_n()

      # CP n
      when 0xBF then @CP_r('A')
      when 0xB8 then @CP_r('B')
      when 0xB9 then @CP_r('C')
      when 0xBA then @CP_r('D')
      when 0xBB then @CP_r('E')
      when 0xBC then @CP_r('H')
      when 0xBD then @CP_r('L')
      when 0xBE then @CP_r('(HL)')
      when 0xFE then @CP_n()

      # INC n
      when 0x3C then @INC_r('A')
      when 0x04 then @INC_r('B')
      when 0x0C then @INC_r('C')
      when 0x14 then @INC_r('D')
      when 0x1C then @INC_r('E')
      when 0x24 then @INC_r('H')
      when 0x2C then @INC_r('L')
      when 0x34 then @INC_r('(HL)')

      # DEC n
      when 0x3D then @DEC_r('A')
      when 0x05 then @DEC_r('B')
      when 0x0D then @DEC_r('C')
      when 0x15 then @DEC_r('D')
      when 0x1D then @DEC_r('E')
      when 0x25 then @DEC_r('H')
      when 0x2D then @DEC_r('L')
      when 0x35 then @DEC_r('(HL)')

      # ADD HL, n
      when 0x09 then @ADD_HL_r('BC')
      when 0x19 then @ADD_HL_r('DE')
      when 0x29 then @ADD_HL_r('HL')
      when 0x39 then @ADD_HL_r('SP')

      # ADD SP, n
      when 0xE8 then @ADD_SP_n()

      # INC nn
      when 0x03 then @INC_r('BC')
      when 0x13 then @INC_r('DE')
      when 0x23 then @INC_r('HL')
      when 0x33 then @INC_r('SP')

      # DEC nn
      when 0x0B then @DEC_r('BC')
      when 0x1B then @DEC_r('DE')
      when 0x2B then @DEC_r('HL')
      when 0x3B then @DEC_r('SP')

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
      when 0x10 then 'STOP'
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
      when 0xC7 then @RST(0x00)
      when 0xCF then @RST(0x08)
      when 0xD7 then @RST(0x10)
      when 0xDF then @RST(0x18)
      when 0xE7 then @RST(0x20)
      when 0xEF then @RST(0x28)
      when 0xF7 then @RST(0x30)
      when 0xFF then @RST(0x38)

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
          when 0x37 then @SWAP_r('A')
          when 0x30 then @SWAP_r('B')
          when 0x31 then @SWAP_r('C')
          when 0x32 then @SWAP_r('D')
          when 0x33 then @SWAP_r('E')
          when 0x34 then @SWAP_r('H')
          when 0x35 then @SWAP_r('L')
          when 0x36 then @SWAP_r('(HL)')

          # RLC n
          when 0x07 then @RLC_r('A')
          when 0x00 then @RLC_r('B')
          when 0x01 then @RLC_r('C')
          when 0x02 then @RLC_r('D')
          when 0x03 then @RLC_r('E')
          when 0x04 then @RLC_r('H')
          when 0x05 then @RLC_r('L')
          when 0x06 then @RLC_r('(HL)')

          # RL n
          when 0x17 then @RL_r('A')
          when 0x10 then @RL_r('B')
          when 0x11 then @RL_r('C')
          when 0x12 then @RL_r('D')
          when 0x13 then @RL_r('E')
          when 0x14 then @RL_r('H')
          when 0x15 then @RL_r('L')
          when 0x16 then @RL_r('(HL)')

          # RRC n
          when 0x0F then @RRC_r('A')
          when 0x08 then @RRC_r('B')
          when 0x09 then @RRC_r('C')
          when 0x0A then @RRC_r('D')
          when 0x0B then @RRC_r('E')
          when 0x0C then @RRC_r('H')
          when 0x0D then @RRC_r('L')
          when 0x0E then @RRC_r('(HL)')

          # RR n
          when 0x1F then @RR_r('A')
          when 0x18 then @RR_r('B')
          when 0x19 then @RR_r('C')
          when 0x1A then @RR_r('D')
          when 0x1B then @RR_r('E')
          when 0x1C then @RR_r('H')
          when 0x1D then @RR_r('L')
          when 0x1E then @RR_r('(HL)')

          # SLA n
          when 0x27 then @SLA_r('A')
          when 0x20 then @SLA_r('B')
          when 0x21 then @SLA_r('C')
          when 0x22 then @SLA_r('D')
          when 0x23 then @SLA_r('E')
          when 0x24 then @SLA_r('H')
          when 0x25 then @SLA_r('L')
          when 0x26 then @SLA_r('(HL)')

          # SRA n
          when 0x2F then @SRA_r('A')
          when 0x28 then @SRA_r('B')
          when 0x29 then @SRA_r('C')
          when 0x2A then @SRA_r('D')
          when 0x2B then @SRA_r('E')
          when 0x2C then @SRA_r('H')
          when 0x2D then @SRA_r('L')
          when 0x2E then @SRA_r('(HL)')

          # SRL n
          when 0x3F then @SRL_r('A')
          when 0x38 then @SRL_r('B')
          when 0x39 then @SRL_r('C')
          when 0x3A then @SRL_r('D')
          when 0x3B then @SRL_r('E')
          when 0x3C then @SRL_r('H')
          when 0x3D then @SRL_r('L')
          when 0x3E then @SRL_r('(HL)')

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
       # throw "Unknown opcode: 0x#{opcode.toString(16)}"


window.Disassembler = Disassembler
