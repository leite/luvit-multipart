local app = require('luvit-app'):new()

local json_headers = {['Content-type'] = 'application/json'}

app:GET('/', function(self, nxt)
  self:send(200, '{"foo":"master"}', json_headers)
end)

app:run(6969, '0.0.0.0')
