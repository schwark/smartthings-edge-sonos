local lux = require('luxure')
local socket = require('cosock').socket
local commands = require('commands')
local log = require('log')

local M = {}

function M.start(driver)
  local server = lux.Server.new_with(socket.tcp(), {env='debug'})

  if driver then
    -- Register server
    driver:register_channel_handler(server.sock, function ()
        server:tick()
    end)
  end 
  -- Endpoint
  server:notify('/', function (req, res)
        local headers = req:get_headers()
        local id = headers and headers._inner and headers._inner.sid or nil
        id = id and id:gsub('_sub.+',''):gsub('uuid:','') or nil
        log.info('[NOTIFY] : '..id)
        local event = req:get_body()
        log.info('[NOTIFY] : '..event)
        local ok, err = pcall(function () 
          local device = commands.get_device(driver, id)
          commands.handle_event(driver, device, event) 
        end)
        if not ok then
          log.error('[NOTIFY] event handling failed : '..err)
        end
        res:send('HTTP/1.1 200 OK')
  end)
  server:listen()
  log.info('notification server started at port '..server.port)
  if driver then
      driver.server = server
  else
    server:run()
  end
end

return M