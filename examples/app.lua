process.env.DEBUG = '1'
--local Log = require('lib/log')

local app       = require('luvit-app'):new()
local multipart = require '../multipart'

local json_headers = {['Content-type'] = 'application/json'}

app:mount('/public/', 'static', {mount = '',root = __dirname .. '/public'})
app:use(multipart())

app:GET('/foo$', function(self, nxt)
  p(self.req)
  self:send(200, '{"foo":"master"}', json_headers)
end)

app:POST('/foo$', function(self, nxt)
  p(self.req)
  self:send(200, '{"foo":"post_it"}', json_headers)
end)

app:run(6969, '0.0.0.0')
