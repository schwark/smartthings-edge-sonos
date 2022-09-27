local commands = require('commands')
local config = require('config')

local lifecycle_handler = {}

function lifecycle_handler.infoChanged(driver, device)
    --return commands.handle_faves_refresh(driver,device)
end

function lifecycle_handler.init(driver, device)
  -------------------
  -- Set up scheduled
  -- services once the
  -- driver gets
  -- initialized.
  --commands.set_timer(driver, device)
  device.thread:call_on_schedule(
    config.STATE_UPDATE_SCHEDULE_PERIOD,
    function ()
        return commands.handle_refresh(driver, device)
    end,
    'Refresh schedule')
  
  if driver:setup_timer() then
    commands.handle_player_refresh(driver)
  end

  --[[
  commands.handle_faves_refresh(driver, device)

  local level = device:get_latest_state('main', 'switchLevel', 'level') or 0
  device:emit_event(capabilities.switchLevel.level(level))

  device.thread:call_on_schedule(
    config.PLAYER_UPDATE_SCHEDULE_PERIOD,
    function ()
        return commands.handle_player_refresh(driver, device)
    end,
    'Refresh schedule')
  --]]
end

function lifecycle_handler.added(driver, device)
  -- Once device has been created
  -- at API level, poll its state
  -- via refresh command and send
  -- request to share server's ip
  -- and port to the device os it
  -- can communicate back.
  commands.handle_added(driver, device)
end

function lifecycle_handler.removed(driver, device)
  -- Remove Schedules created under
  -- device.thread to avoid unnecessary
  -- CPU processing.
  for timer in pairs(device.thread.timers) do
    device.thread:cancel_timer(timer)
  end
  local devices = driver:get_devices()
  if not devices or #devices == 0 then
    driver:cancel_timer()
  end
end

return lifecycle_handler