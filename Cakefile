{spawn} = require('child_process')
express = require('express')

build = (options) ->
  args = ['-c', '-o', 'lib', 'src']
  args.unshift('-w') if options?.watch

  coffee = spawn('coffee', args)
  coffee.stderr.pipe process.stderr, end: false
  coffee.stdout.pipe process.stdout, end: false

startWebServer = ->
  app = express()

  # Setup directories.
  app.use '/',     express.static("#{__dirname}/www")
  app.use '/lib',  express.static("#{__dirname}/lib")
  app.use '/ROMs', express.static("#{__dirname}/ROMs")

  # Root goes to index.htm
  app.get '/', (req, res) ->
    res.sendfile "#{__dirname}/www/index.htm"

  app.listen 3000
  console.log 'Web server is listening on port 3000.'

  app

task 'build', 'Build lib/ from src/.', ->
  build()

task 'server', 'Start a local server and watch src/ for changes.', ->
  startWebServer()
  build watch: true
