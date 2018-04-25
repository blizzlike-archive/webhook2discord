local http = require('resty.http')
local cjson = require('cjson')

local travis = {}

function travis.req_travis_key()
  local req = http:new()
  local _, code, _, _, body = req:request({
    url = 'https://api.travis-ci.org/config',
    scheme = 'https',
    method = 'GET',
    headers = {
      ['Content-Type'] = 'application/x-www-form-urlencoded'
    }
  })

  if code == 200 then
    local data = cjson.decode(body)
    return data.config.notifications.webhook.public_key
  end
  return nil
end

function travis.recv_webhook(self)
  ngx.req.read_body()
  local body = ngx.var.request_body
  local headers = ngx.req.get_headers()
  local key = travis:req_travis_key()

  if not key then
    return ngx.HTTP_INTERNAL_SERVER_ERROR, {
      reason = 'could not get travis\' public key'
    }
  end

  if not travis:verify_req(headers['Signature'], body) then
    return ngx.HTTP_FORBIDDEN, {
      reason = 'request signature is wrong or missing'
    }
  end

  return ngx.HTTP_OK, { msg = 'k thx bye!' }
end

function travis.verify_req(self, signature, body)
  -- see https://docs.travis-ci.com/user/notifications/#Verifying-Webhook-requests
  return nil
end

travis.routes = {
  { context = '', method = 'POST', call = travis.recv_webhook }
}

return travis
