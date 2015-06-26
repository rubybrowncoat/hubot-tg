# http = require 'http'
httpfr  = require 'follow-redirects'
http    = httpfr.http
url     = require 'url'
net     = require 'net'
request = require 'request'
fs      = require 'fs'
cp      = require 'child_process'
sharp   = require 'sharp'

{ Adapter
, TextMessage } = require 'hubot'

class Tg extends Adapter
  constructor: (robot) ->
    @robot   = robot
    @port    = process.env['HUBOT_TG_PORT'] || 1123
    @host    = process.env['HUBOT_TG_HOST'] || 'localhost'
    @tempdir = process.env['HUBOT_TG_TEMP'] || '/tmp/hubot/'

  send: (envelope, lines...) ->
    text = []
    lines.map (line) =>
      imageUrl = line.split('#')[0].split('?')[0]
      if not imageUrl.match /\.jpe?g|png|gif$/g
        text.push line
      else
        @robot.logger.info 'Found image ' + imageUrl
        if text.length
          @send_text envelope, text
          text = []
        @get_image line, (filepath) =>
          if filepath.match /\.gif$/g
            @send_document envelope, filepath
          else
            @send_photo envelope, filepath
    @send_text envelope, text

  get_image: (imageUrl, callback) ->
    mkdir = 'mkdir -p ' + @tempdir
    cp.exec mkdir, (err, stdout, stder) =>
      throw err if err

      finalUrl = url.parse(imageUrl)
      filename = finalUrl.pathname.split("/").pop()

      options =
        url: finalUrl
        host: finalUrl.host
        port: 80
        path: finalUrl.pathname

      stream = request.get(options)
     
      if filename.match /\.gif$/g
        stream.on "end", =>
          @robot.logger.info filename + " downloaded to " + @tempdir
          callback @tempdir + filename
        file = fs.createWriteStream(@tempdir + filename)
        stream.pipe(file)
      else
        resizer = sharp().resize(400).quality(60).toFile @tempdir + filename, (err) =>
          @robot.logger.info filename + " downloaded and processed to " + @tempdir
          callback @tempdir + filename
        stream.pipe(resizer)

  send_photo: (envelope, filepath) ->
    client = net.connect @port, @host, ->
      message = "send_photo " + envelope.room + " " + filepath + "\n"
      client.write message, ->
        client.end ->
          # fs.unlink(filepath)
          @robot.logger.info "Image " + filepath + " sent."

  send_document: (envelope, filepath) ->
    client = net.connect @port, @host, ->
      message = "send_document " + envelope.room + " " + filepath + "\n"
      client.write message, ->
        client.end ->
          @robot.logger.info "File " + filepath + " sent."

  send_text: (envelope, lines) ->
    text = lines.join "\n"
    client = net.connect @port, @host, ->
      message = "msg "+envelope.room+" \""+text.replace(/"/g, '\\"').replace(/\n/g, '\\n')+"\"\n"
      client.write message, ->
        client.end()

  emote: (envelope, lines...) ->
    @send envelope, "* #{line}" for line in lines

  reply: (envelope, lines...) ->
    lines = lines.map (s) -> "#{envelope.user.name}: #{s}"
    @send envelope, lines...

  entityToID: (entity) ->
    entity.type + "#" + entity.id

  run: ->
    self = @
    # We will listen here to incoming events from tg
    self.robot.router.post "/hubot_tg/msg_receive", (req, res) ->
      msg = req.body
      room = if msg.to.type == 'user' then self.entityToID(msg.from) else self.entityToID(msg.to)
      from = self.entityToID(msg.from)
      user = self.robot.brain.userForId from, name: msg.from.print_name, room: room
      self.robot.receive new TextMessage user, msg.text or '', msg.id
      res.end ""
    self.emit 'connected'


exports.use = (robot) ->
  new Tg robot
