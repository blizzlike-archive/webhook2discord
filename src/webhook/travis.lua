local http = require('resty.http')
local pkey = require('openssl.pkey')
local digest = require('openssl.digest')
local cjson = require('cjson')
local base64 = require('base64')

local travis = {}

function travis.get_key(self)
  local fd = io.open('/tmp/travis.key', 'r')
  local key = nil
  local err = nil
  if fd then
    ngx.log(ngx.STDERR, 'travis: read key from cache')
    key = fd:read('*a')
    fd:close()
  else
    key, err = travis:req_travis_key()
    if key then
      ngx.log(ngx.STDERR, 'travis: write key to cache')
      fd = io.open('/tmp/travis.key', 'w')
      if fd then
        fd:write(key)
        fd:close()
      end
    end
  end
  return key, err
end

function travis.forward(self, data)
  local webhook = os.getenv('DISCORD_WEBHOOK_URL')
  if not webhook then
    local err = 'missing webhook url'
    ngx.log(ngx.STDERR, 'travis: ' .. err)
    return ngx.HTTP_INTERNAL_SERVER_ERROR, { reason = err }
  end

  local color = 0x000000
  if data.status_message == 'Passed' then color = 0x00ff00 end
  if data.status_message == 'Fixed' then color = 0x00ff00 end
  if data.status_message == 'Broken' then color = 0xff0000 end
  if data.status_message == 'Failed' then color = 0xff0000 end
  if data.status_message == 'Still Failed' then color = 0xff0000 end
  if data.status_message == 'Errored' then color = 0xff0000 end
  
  local req = http:new()
  local _, code, _, _, body = req:request({
    url = webhook,
    scheme = 'https',
    method = 'POST',
    headers = {
      ['Content-Type'] = 'application/json'
    },
    body = cjson.encode({
      embeds = {{
        title = '[' .. data.repository.name .. ':' .. data.branch .. '] ' .. data.type,
        url = data.build_url,
        description = data.message,
        author = {
          name = data.author_name
        },
        color = color,
        footer = {
          text = data.status_message:lower()
        }
      }},
      username = 'travis'
    })
  })

  if code == 204 then
    return ngx.HTTP_OK, { reason = 'k thx bye!' }
  end

  local err = 'discord webhook error (' .. code .. ')'
  ngx.log(ngx.STDERR, 'travis: ' .. err)
  return ngx.HTTP_INTERNAL_SERVER_ERROR, { reason = err }
end

function travis.req_travis_key(self)
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

  return nil, 'could not fetch travis\' public key'
end

function travis.recv_webhook(self)
  ngx.req.read_body()
  local body = ngx.req.get_post_args().payload

  local headers = ngx.req.get_headers()
  if not headers['Signature'] then
    local err = 'missing signature'
    ngx.log(ngx.STDERR, 'travis: ' .. err)
    return ngx.HTTP_FORBIDDEN, { reason = err }
  end

  local key, err = travis:get_key()
  if not key then
    ngx.log(ngx.STDERR, 'travis: ' .. err)
    return ngx.HTTP_INTERNAL_SERVER_ERROR, { reason = err }
  end

  local verify, err = travis:verify_req(body, headers['Signature'], key)
  if not verify then
    ngx.log(ngx.STDERR, 'travis: ' .. err)
    return ngx.HTTP_FORBIDDEN, { reason = err }
  end

  local data = cjson.decode(body)
  if not data then
    local err = 'no json body'
    ngx.log(ngx.STDERR, 'travis: ' .. err)
    return ngx.HTTP_FORBIDDEN, { reason = err }
  end

  return travis:forward(data)
end

function travis.verify_req(self, body, b64signature, key)
  -- see https://docs.travis-ci.com/user/notifications/#Verifying-Webhook-requests
  local signature = base64.decode(b64signature)
  local pubkey = pkey.new({ type = 'RSA' })
  pubkey:setPublicKey(key, 'PEM')
  local payload = digest.new('sha1')
  payload:update(body)

  if not pubkey then return nil, 'cannot read pubkey' end
  local verify = pubkey:verify(signature, payload)
  if not verify then return nil, 'cannot verify signature' end

  return true
end

travis.routes = {
  { context = '', method = 'POST', call = travis.recv_webhook }
}

return travis
