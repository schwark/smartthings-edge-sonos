local log = require "log"
local config = require("config")
local Sonos = require("sonos")
local utils = require("st.utils")
local socket = require("socket")
local discovery = {}

function discovery.get_model(type)
  return config.MODEL..' '..utils.pascal_case(type)
end

function discovery.get_network_id(type, id)
  return discovery.get_model(type)..' '..id
end

function discovery.extract_id(network_id)
  return network_id:match('[%s_](%d+)$')
end

local function create_device(driver, device)
  log.info('===== Creating device for '..device.type..' '..device.name..'...')

  local model = discovery.get_model(device.type)
  local network_id = discovery.get_network_id(device.type, device.id)
  -- device metadata table
  local metadata = {
    type = config.DEVICE_TYPE,
    device_network_id = network_id,
    label = device.name,
    profile = config[device.type:upper()..'_PROFILE'],
    manufacturer = config.MANUFACTURER,
    model = model,
    vendor_provided_label = network_id
  }
  log.info("creating device with metadata "..utils.stringify_table(metadata))
  return driver:try_create_device(metadata)
end

function discovery.start(driver, opts, cons)
  local sonos = Sonos()
  local speakers = sonos:discover()
  if(speakers) then
    for i, each in ipairs(speakers) do
        log.info(each.ip.." : "..(each.meta.roomName or "nil"))
    end
    sonos:cmd(speakers[1].ip, "Stop")
  else
      log.error('===== No Sonos speakers found')
  end
end

return discovery