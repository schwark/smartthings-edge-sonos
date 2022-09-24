local log = require "log"
local config = require("config")
local Sonos = require("sonos.soap")
local utils = require("st.utils")
local socket = require('socket')
local commands = require('commands')
local discovery = {}

local function create_device(driver, device)
  log.info('===== Creating device for '..device.name..'...')

  local network_id = device.id
  -- device metadata table
  local metadata = {
    type = config.DEVICE_TYPE,
    device_network_id = network_id,
    label = device.name,
    profile = config.SPEAKER_PROFILE,
    manufacturer = config.MANUFACTURER,
    model = device.model or 'Speaker Group',
    vendor_provided_label = network_id
  }
  log.info("creating device with metadata "..utils.stringify_table(metadata))
  return driver:try_create_device(metadata)
end

local function get_players(driver, force)
  local sonos = Sonos()
  assert(driver.player_cache)
  sonos:update(driver.player_cache, force)
  return sonos.players
end

function discovery.start(driver, opts, cons)
  local players = get_players(driver, true)
  if(players) then
    for i, each in ipairs(players) do
        log.info('Found '..each.id..' at '..each.ip.." named "..(each.name or "nil"))
        if(each.name and each.name:match(config.FILTER_SPEAKERS)) then
          create_device(driver, each)
          socket.sleep(2)
        end
    end
  else
      log.error('===== No Sonos speakers found')
  end
end

return discovery