$.get '../ROMs/DMG_ROM.bin', (data) ->
  alert 'Fetched DMG_ROM.bin'

new Debugger().loadCode([])
