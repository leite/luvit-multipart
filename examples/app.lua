local app       = require('luvit-app'):new()
local multipart = require '../multipart'

local json_headers = {['Content-type'] = 'application/json'}

app:mount('/public/', 'static', {mount = '',root = __dirname .. '/public'})
app:use(multipart())

app:POST('/foo$', function(self, nxt)
  p(self.req)
  self:send(200, '{"foo":"post_it"}', json_headers)
end)

app:GET('/favicon.ico$', function(self, nxt)
  self:send(404)
end)

app:run(6969, '0.0.0.0')
