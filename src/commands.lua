local log = require "log"
local capabilities = require "st.capabilities"
local config = require("config")
local Sonos = require('sonos.soap')
local math = require('math')
local utils = require('st.utils')
local json = require('dkjson')

local command_handlers = {}


local function is_empty(var)
    return not var or "" == var or tostring(var):match('userdata')
end

local function has_value(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

local function to_string(val)
    return type(val) == 'table' and utils.stringify_table(val) or tostring(val)
end

local function update_state(device, component, attribute, value, enum)
    local last_key = 'last_' .. component .. '_' .. attribute
    if value then
        local status = type(value) == 'table'
            and device:get_field(last_key)
            or device:get_latest_state('main', component, attribute)
        local string_val = to_string(value)
        local string_status = to_string(status)

        if string_status ~= string_val then
            log.info("setting " .. device.label .. " " .. attribute .. " to " .. string_val)
            if type(value) == 'table' then device:set_field(last_key, string_val) end
            local caps = capabilities[component][attribute]
            device:emit_event(enum and caps[value]() or caps(value))
        end
    end
end

local function get_presets(sonos)
    local presets = {}
    for _, list in ipairs({ sonos.playlists, sonos.favorites }) do
        if list then
            for _, v in ipairs(list) do
                table.insert(presets, { id = v.id, name = v.title })
            end
        end
    end
    return presets
end

function command_handlers.handle_added(driver, device)
    command_handlers.handle_refresh(driver, device)
    device:emit_event(capabilities.switchLevel.level(0))
    device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands({ 'play', 'stop', 'pause' }))
end

function command_handlers.get_sonos(driver, device)
    local sonos = device:get_field("sonos")
    if not sonos then
        log.info("initializing sonos for " .. device.label)
        sonos = Sonos(driver.player_cache)
        if sonos then
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
    local sonos = Sonos()
    if sonos then
        assert(driver.player_cache)
        if not driver.player_cache.last_updated or
            os.time() - driver.player_cache.last_updated > config.PLAYER_UPDATE_MAX_FREQUENCY then
            if sonos:update(driver.player_cache, true) then
                local presets = get_presets(sonos)
                if next(presets) then
                    log.info('updating presets to ' .. utils.stringify_table(presets))
                    local devices = driver:get_devices()
                    for _, each in ipairs(devices) do
                        update_state(each, 'mediaPresets', 'presets', presets)
                    end
                end
            end
        end
    end
end

function command_handlers.handle_faves_refresh(driver, device)
    log.debug("in faves refresh for " .. device.label)
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos then
        local list = {}
        local item = nil
        local i = 1
        repeat
            item = device.preferences['song' .. i]
            log.debug("song" .. i .. " is " .. (item or "nil"))
            if item and "" ~= item and not tostring(item):match('userdata') then
                table.insert(list, item)
                i = i + 1
            else
                item = nil
            end
        until not item
        log.info('setting faves to ' .. utils.stringify_table(list))
        device:set_field('faves', list)
    end
end

function command_handlers.handle_track_command(driver, device, command)
    log.info("in " .. command.command .. " command for " .. device.label)
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos then
        if command.command == 'on' or command.command == 'play' or command.command == 'startAudio' or
            command.command == 'playPreset' then
            local current_fave = command_handlers.get_current_fave(driver, device)
            log.info('current faves is ' .. (current_fave or "nil"))
            local success = false
            if current_fave and command.command == 'on' then
                success = sonos:play_media_by_name(device.device_network_id, current_fave)
            elseif command.command == 'playPreset' and command.args.presetId then
                success = sonos:play_media_by_id(device.device_network_id, command.args.presetId)
            else
                success = sonos:play(device.device_network_id)
            end
            if success then
                device:emit_event(capabilities.switch.switch.on())
                device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
            end
        end
        if (command.command == 'off' or command.command == 'stop' or command.command == 'stopAudio') and
            sonos:stop(device.device_network_id) then
            device:emit_event(capabilities.switch.switch.off())
            device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
        end
        if (command.command == 'pause') and sonos:pause(device.device_network_id) then
            device:emit_event(capabilities.switch.switch.off())
            device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
        end
    end
end

function command_handlers.handle_track_nav(driver, device, command)
    log.info("in track nav command for " .. device.label)
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos then
        local supported_commands = device:get_latest_state('main', 'mediaTrackControl', 'supportedTrackControlCommands')
        if supported_commands and has_value(supported_commands, command.command) then
            if (command.command == 'nextTrack') then
                sonos:next(device.device_network_id)
            end
            if (command.command == 'previousTrack') then
                sonos:prev(device.device_network_id)
            end
        end
    end
end

function command_handlers.get_current_fave(driver, device)
    local choices = device:get_field('faves')
    if not choices or #choices == 0 then return nil end
    log.info(utils.stringify_table(choices))
    local level = device:get_latest_state('main', 'switchLevel', 'level') or 0
    if 0 == level then return nil end
    local num_item = math.floor((#choices - 1) * level / 100 + 0.5) + 1
    log.info('current fave is ' .. choices[num_item])
    return choices[num_item]
end

function command_handlers.handle_set_track(driver, device, command)
    log.info("in set track")
    local level = tonumber(command.args.level or '50')
    device:emit_event(capabilities.switchLevel.level(level))
end

function command_handlers.handle_mute_command(driver, device, command)
    log.info("in handle mute for command " .. command.command)
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos then
        local args = {
            setMute = command.args.state,
            mute = 'muted',
            unmute = 'unmuted',
        }
        local arg = args[command.command]
        if arg then
            sonos:mute_cmd(device.device_network_id, arg == 'muted')
            device:emit_event(capabilities.audioMute.mute[arg]())
        end
    end
end

function command_handlers.handle_volume_command(driver, device, command)
    log.info("in handle volume for command " .. command.command)
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos then
        local current_level = sonos:get_volume(device.device_network_id)
        current_level = current_level and tonumber(current_level) or 0
        local levels = {
            setVolume = tonumber(command.args.volume),
            volumeUp = current_level + 10 < 100 and current_level + 10 or 100,
            volumeDown = current_level - 10 > 0 and current_level - 10 or 0,
        }
        local level = levels[command.command]
        if level then
            sonos:set_volume(device.device_network_id, level)
            device:emit_event(capabilities.audioVolume.volume(level))
        end
    end
end

function command_handlers.handle_refresh(driver, device)
    --log.info("Sending refresh command to "..device.label)
    local success = false
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos then
        local state = sonos:get_state(device.device_network_id)
        if state then
            local mute_states = { 'unmuted', 'muted' }
            local mute = mute_states[tonumber(state.mute or '0') + 1]
            update_state(device, 'audioMute', 'mute', mute, true)
            local volume = state.volume and tonumber(state.volume)
            update_state(device, 'audioVolume', 'volume', volume)
            local uri = state.playing and state.playing.uri or ""
            update_state(device, 'audioStream', 'uri', uri)
            local play = state.state or 'STOPPED'
            local switch_states = { PLAYING = 'on', TRANSITIONING = 'on' }
            update_state(device, 'switch', 'switch', switch_states[play] or 'off', true)
            local playback_states = { PLAYING = 'playing', TRANSITIONING = 'playing', PAUSED_PLAYBACK = 'paused',
                STOPPED = 'stopped', NO_MEDIA_PRESENT = 'stopped' }
            update_state(device, 'mediaPlayback', 'playbackStatus', playback_states[play], true)
            local duration = state.playing and state.playing.duration or 0
            update_state(device, 'audioTrackData', 'totalTime', duration)
            local position = state.playing and state.playing.position or 0
            update_state(device, 'audioTrackData', 'elapsedTime', position)
            --log.debug(utils.stringify_table(state))
            local track_nav = {}
            if state.playing then
                local has_next = state.playing.num and state.playing.num_tracks and
                    state.playing.num < state.playing.num_tracks and table.insert(track_nav, 'nextTrack')
                local has_prev = state.playing.num and state.playing.num > 1 and table.insert(track_nav, 'previousTrack')
                update_state(device, 'mediaTrackControl', 'supportedTrackControlCommands', track_nav)
            end
            local track = state.playing and
                {
                    title = state.playing.title,
                    album = state.playing.album,
                    albumArtUrl = state.playing.art,
                    artist = state.playing.artist,
                    mediaSource = (state.playing.service or "") .. (state.playing.type and ' ' .. state.playing.type or
                        "")
                } or nil
            --track = track and json.encode(track) or nil
            if track then
                update_state(device, 'audioTrackData', 'audioTrackData', track)
            end
            success = true
        end
    end
    return success
end

return command_handlers
