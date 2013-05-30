{spawn} = require('child_process')

build = (options) ->
  args = ['-c', '-o', 'lib', 'src']
  args.unshift('-w') if options?.watch

  coffee = spawn('coffee', args)
  coffee.stderr.pipe process.stderr, end: false
  coffee.stdout.pipe process.stdout, end: false

task 'build', 'Build lib/ from src/', ->
  build()

task 'watch', 'Watch src/ for changes', ->
  build watch: true
