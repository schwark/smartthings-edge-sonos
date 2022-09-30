local log = require "log"
local capabilities = require "st.capabilities"
local config = require("config")
local Sonos = require('sonos.soap')
local math = require('math')
local utils = require('st.utils')
local cosock = require "cosock"
local socket = cosock.socket

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
    --log.info('update state '..component..':'..attribute..':'..tostring(value))
    if device and device.label and value ~= nil then
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

function command_handlers.get_device(driver, id)
    if not driver or not id then return nil end
    local result = nil
    local devices = driver:get_devices()
    for i, device in ipairs(devices) do
        if device.device_network_id == id then 
            result = device 
            break
        end
    end
    return result
end

local function find_hub_ip(driver)
    --First check if the hub_ipv4 is known
    if driver.environment_info.hub_ipv4 then
        return driver.environment_info.hub_ipv4 
    end
    --If not, use this other method
    local s = socket:udp()
    -- The IP address here doesn't seem to matter so long as it isn't '*'
    s:setpeername('192.168.0.0', 0)
    local localip, _, _ = s:getsockname()
    return localip
end

function command_handlers.get_current_subscription(driver, device, type)
    return driver.subscriptions[device.device_network_id] 
            and driver.subscriptions[device.device_network_id][type] 
            and driver.subscriptions[device.device_network_id][type] or nil
end

function command_handlers.handle_added(driver, device)
    command_handlers.handle_refresh(driver, device)
    device:emit_event(capabilities.switchLevel.level(0))
    device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands({ 'play', 'stop', 'pause' }))
end

function command_handlers.handle_subs(driver, device)
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos then
        local event_subs = {'AVTransport', 'GroupRenderingControl'}
        local callback = 'http://%(host)s:%(port)s/' % {host = find_hub_ip(driver), port = driver.server.port}
        for i, type in ipairs(event_subs) do
            driver.subscriptions[device.device_network_id] = driver.subscriptions[device.device_network_id] or {}
            local current = command_handlers.get_current_subscription(driver, device, type)
            if not current or (current.timeout and current.timeout - os.time() < config.SUBSCRIPTION_TIME/10) then
                local sid = sonos:subscribe_events(device.device_network_id, type, callback, current and current.sid or nil)
                if sid then
                    driver.subscriptions[device.device_network_id][type] = {sid = sid, timeout = os.time() + config.SUBSCRIPTION_TIME}
                else
                    -- fall back on polling
                    device.thread:call_on_schedule(
                        config.STATE_UPDATE_SCHEDULE_PERIOD,
                        function ()
                            return command_handlers.handle_refresh(driver, device)
                        end,
                        'Refresh schedule')
                end
            end
        end
    end
end

function command_handlers.handle_unsubs(driver, device)
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos then
        local subs = driver.subscriptions[device.device_network_id] or {}
        for type, sub in pairs(subs) do
            sonos:unsubscribe_events(device.device_network_id, type, sub.sid)
            driver.subscriptions[device.device_network_id].type = nil
        end
    end
end

function command_handlers.handle_init(driver, device)
    command_handlers.handle_subs(driver, device)
    device.thread:call_on_schedule(
        config.SUBSCRIPTION_TIME,
        function ()
            return command_handlers.handle_subs(driver, device)
        end,
        'Refresh schedule')
end

function command_handlers.get_sonos(driver, device)
    if not driver or not device then return Sonos() end
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
            item = device.preferences and device.preferences['song' .. i] or nil
            if item then
                log.debug("song" .. i .. " is " .. (item or "nil"))
                if item and not is_empty(item) then
                    table.insert(list, item)
                    i = i + 1
                else
                    item = nil
                end
            end
        until not item
        log.info('setting faves to ' .. utils.stringify_table(list))
        device:set_field('faves', list)
    end
end

function command_handlers.handle_play_mode(driver, device, command)
    log.info("in " .. command.command .. " command for " .. device.label)
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos then
        local s = command.args.shuffle or device:get_latest_state('main','mediaPlaybackShuffle','playbackShuffle') or 'disabled'
        local r = command.args.mode or device:get_latest_state('main','mediaPlaybackRepeat','playbackRepeat') or 'off'
        local shuffle = s == 'enabled'
        local rpt = r ~= 'off'
        local all = r == 'all'
        if sonos:set_play_mode(device.device_network_id, shuffle, rpt, all) then
            update_state(device, 'mediaPlaybackShuffle','playbackShuffle', s)
            update_state(device, 'mediaPlaybackRepeat','playbackRepeatMode', r)
        end
    end
end

function command_handlers.handle_track_command(driver, device, command)
    log.info("in " .. command.command .. " command for " .. device.label)
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos then
        if command.command == 'on' or command.command == 'play' or command.command == 'startAudio' or
            command.command == 'playPreset' then
            local current_fave = nil and command_handlers.get_current_fave(driver, device)
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

function command_handlers.handle_event(driver, device, event)
    log.info("in handle event for " .. (device and device.label or "nil"))
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos and event then
        local state = sonos:process_event(device.device_network_id, event)
        if state then
            return command_handlers.process_state(driver, device, state)
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

function command_handlers.process_state(driver, device, state)
    local success = false
    if state then
        if state.play_mode then
            local sonos = command_handlers.get_sonos(driver, device)
            if sonos then
                state.shuffle, state.rpt, state.all = sonos:get_play_mode(nil, state.play_mode)                
            end
        end
        if state.mute then
            local mute_states = { 'unmuted', 'muted' }
            local mute = mute_states[tonumber(state.mute) + 1]
            update_state(device, 'audioMute', 'mute', mute, true)
        end
        if state.volume then
            local volume = tonumber(state.volume)
            update_state(device, 'audioVolume', 'volume', volume)
        end
        if state.state then
            local play = state.state
            local switch_states = { PLAYING = 'on', TRANSITIONING = 'on' }
            update_state(device, 'switch', 'switch', switch_states[play] or 'off', true)                
            local playback_states = { PLAYING = 'playing', TRANSITIONING = 'playing', PAUSED_PLAYBACK = 'paused',
            STOPPED = 'stopped', NO_MEDIA_PRESENT = 'stopped' }
            update_state(device, 'mediaPlayback', 'playbackStatus', playback_states[play], true)
        end
        if state.shuffle ~= nil then
            update_state(device, 'mediaPlaybackShuffle', 'playbackShuffle', state.shuffle and 'enabled' or 'disabled')
        end
        if state.rpt ~= nil then
            update_state(device, 'mediaPlaybackRepeat', 'playbackRepeatMode', state.rpt and (state.all and 'all' or 'one') or 'off')
        end
        if state.playing then
            if state.playing.uri then
                local uri = state.playing and state.playing.uri or nil
                update_state(device, 'audioStream', 'uri', uri)
            end
            if state.playing.duration then
                local duration = state.playing and '' ~= state.playing.duration and state.playing.duration or nil
                update_state(device, 'audioTrackData', 'totalTime', duration)
            end
            if state.playing.position then
                local position = state.playing and state.playing.position or nil
                update_state(device, 'audioTrackData', 'elapsedTime', position)
            end
            if state.playing.num then
                local track_nav = {}
                local has_next = state.playing.num and state.playing.num_tracks and
                    state.playing.num < state.playing.num_tracks and table.insert(track_nav, 'nextTrack')
                local has_prev = state.playing.num and state.playing.num > 1 and table.insert(track_nav, 'previousTrack')
                update_state(device, 'mediaTrackControl', 'supportedTrackControlCommands', track_nav)
            end
            if state.playing.title then
                local track = 
                {
                    title = state.playing.title,
                    album = state.playing.album,
                    albumArtUrl = state.playing.art,
                    artist = state.playing.artist,
                    mediaSource = (state.playing.service or "") .. (state.playing.type and ' ' .. state.playing.type or
                        "")
                }
                update_state(device, 'audioTrackData', 'audioTrackData', track)
            end
        end
        --log.debug(utils.stringify_table(state))
        success = true
    end
    return success
end

function command_handlers.handle_refresh(driver, device)
    --log.info("Sending refresh command to "..device.label)
    local success = false
    local sonos = command_handlers.get_sonos(driver, device)
    if sonos then
        local state = sonos:get_state(device.device_network_id)
        success = command_handlers.process_state(driver, device, state)
    end
    return success
end

return command_handlers
