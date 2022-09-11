local commands = require('commands')
local config = require('config')
local discovery = require('discovery')

local lifecycle_handler = {}

function lifecycle_handler.init(driver, device)
  -------------------
  -- Set up scheduled
  -- services once the
  -- driver gets
  -- initialized.
  --commands.set_timer(driver, device)
end

function lifecycle_handler.added(driver, device)
  -- Once device has been created
  -- at API level, poll its state
  -- via refresh command and send
  -- request to share server's ip
  -- and port to the device os it
  -- can communicate back.
    --commands.handle_added(driver, device)
end

function lifecycle_handler.removed(_, device)
  -- Remove Schedules created under
  -- device.thread to avoid unnecessary
  -- CPU processing.
  for timer in pairs(device.thread.timers) do
    device.thread:cancel_timer(timer)
  end
end

return lifecycle_handler