local log = require "log"
local capabilities = require "st.capabilities"
local config = require ("config")
local discovery = require("discovery")
local Sonos = require('sonos.soap')

local command_handlers = {}

function command_handlers.get_sonos(driver, device)
    local sonos = device:get_field("sonos")
    if not sonos then
        log.info("initializing sonos for "..device.label)
        sonos = Sonos()
        if sonos then
            sonos:update()
            device:set_field('sonos', sonos)
        else
            sonos = nil
            log.error("unable to initialize sonos obj")
        end
    end
    return sonos
end

function command_handlers.handle_player_refresh(driver, device)
    if not driver then return nil end
    log.info("updating players and playlists for "..device.label)
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos then
        if not driver.player_metadata or os.time() - driver.player_metadata.last_updated > config.PLAYER_UPDATE_MAX_FREQUENCY then
            sonos:update()
            local metadata = {
                players = sonos.players,
                playlists = sonos.playlists,
                favorites = sonos.favorites,
                last_updated = os.time()
            }
            driver.player_metadata = metadata                
        else
            sonos:update(driver.player_metadata)
        end
    end
end

--            device:emit_event(capabilities.windowShade.windowShade[state.state]())
--            device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))

function command_handlers.handle_track_command(driver, device, command)
    log.info("in scene command")
    return retry_enabled_command('scene', driver, device, command)
end

function command_handlers.handle_set_track(driver, device, command)
    log.info("in set track")
    return retry_enabled_command('scene', driver, device, command)
end

function command_handlers.handle_volume_command(driver, device, command)
    log.info("in handle volume for command "..command.command)
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos then
        if command.command == 'volumeUp' then
            
            return true
        end
        if command.command == 'volumeDown' then
            
            return true
        end
        if command.command == 'setVolume' then
            local level = command.args.volume and tonumber(command.args.volume) or nil
            if level then
                sonos:set_volume(level)
            end
            return true
        end
    end
end

local function update_state(device, component, attribute, value, enum)
    if value then
        local status = device:get_latest_state('main', component, attribute)
        if status ~= value then
            log.info("setting "..device.label.." "..attribute.." to "..value)
            local caps = capabilities[component][attribute]
            if enum then
                device:emit_event(caps[value]())
            else
                device:emit_event(caps(value))
            end
        end
    end
end

function command_handlers.handle_refresh(driver, device)
    log.info("Sending refresh command to "..device.label)
    local success = false
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos then
        local state = sonos:get_state()
        if state then
            local mute_states = {'unmuted', 'muted'}
            local mute = mute_states[tonumber(state.mute or '0')+1]
            update_state(device, 'audioMute', 'mute', mute, true)
            local volume = state.volume and tonumber(state.volume)
            update_state(device, 'audioVolume', 'volume', volume)
            local uri = state.playing and state.playing.uri or ""
            update_state(device, 'audioStream', 'uri', uri)
            success = true
        end
    end
    return success
end

return command_handlers