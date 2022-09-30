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
    
  if driver:setup_timer() then
    commands.handle_player_refresh(driver)
  end

  device.thread:call_with_delay(10, function () commands.handle_init(driver, device) end)

  local default_state = {
    duration = 0,
    play_mode = 'NORMAL',
    volume = 0,
    mute = 0,
    state = 'STOPPED'
  }

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
  commands.handle_unsubs(driver, device)
end

return lifecycle_handler