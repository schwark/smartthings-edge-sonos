--local socket = require('socket')
local cosock = require "cosock"
local socket = cosock.socket
local http = cosock.asyncify "socket.http"

local utils = require("st.utils")
local ltn12 = require('ltn12')
-- XML modules
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"

local log = require "log"
local config = require('config')
local xmlutil = require('xmlutil')
local metadata = require('sonos.metadata')

local function get_cached(cache, var)
    --[[
    local i = 0
    while cache and cache[var..'updating'] do
        log.info('waiting for other thread to finish getting '..var)
        -- wait for the other update to finish
        socket.sleep(5)
        i = i + 1
        if i > 20 then
            log.info('giving up waiting for other thread to finish getting '..var)
            cache[var..'updating'] = nil -- something must be stuck on the other thread
        end
    end
    --]]
    local result = cache and cache[var] or nil
    --[[
    if not result and cache then
        log.info('mutexing trying to get '..var)
        cache[var..'updating'] = os.time()
    end
    --]]
    return result
end

local function set_cached(cache, var, value)
    if not cache then return nil end
    cache[var] = value
    cache[var..'_updated'] = os.time()
    --[[
    log.info('clearing mutex trying to get '..var)
    cache[var..'updating'] = nil
    --]]
end

local errors = {
        ["400"] = "Bad request" ,
        ["401"] = "Invalid action" ,
        ["402"] = "Invalid args" ,
        ["404"] = "Invalid var" ,
        ["412"] = "Precondition failed" ,
        ["501"] = "Action failed" ,
        ["600"] = "Argument value invalid" ,
        ["601"] = "Argument value out of range" ,
        ["602"] = "Optional action not implemented" ,
        ["603"] = "Out of memory" ,
        ["604"] = "Human intervention required" ,
        ["605"] = "String argument too long" ,
        ["606"] = "Action not authorized" ,
        ["607"] = "Signature failure" ,
        ["608"] = "Signature missing" ,
        ["609"] = "Not encrypted" ,
        ["610"] = "Invalid sequence" ,
        ["611"] = "Invalid control URL" ,
        ["612"] = "No such session", 
        ["701"] = "Transition not available",
        ["702"] = "No content",
        ["703"] = "Read error",
        ["704"] = "Format not supported for playback",
        ["705"] = "Transport is locked",
        ["706"] = "Write error",
        ["707"] = "Media protected or not writeable",
        ["708"] = "Format not supported for recording",
        ["709"] = "Media is full",
        ["710"] = "Seek mode not supported",
        ["711"] = "Illegal seek target",
        ["712"] = "Play mode not supported",
        ["713"] = "Record quality not supported",
        ["714"] = "Illegal MIME-Type",
        ["715"] = "Content busy",
        ["716"] = "Resource not found",
        ["717"] = "Play speed not supported",
        ["718"] = "Invalid InstanceID",
        ["737"] = "No dns configured",
        ["738"] = "Bad domain",
        ["739"] = "Server error",
        ["800"] = "Command not supported or not a coordinator",
        ["719"] = "Destination resource access denied" ,
        ["720"] = "Cannot process the request" 
}

local function interp(s, tab)
    return (s:gsub('%%%((%a%w*)%)([-0-9%.]*[cdeEfgGiouxXsq])',
              function(k, fmt) return tab[k] and ("%"..fmt):format(tab[k]) or
                  '%('..k..')'..fmt end))
end
getmetatable("").__mod = interp

local types = {
    ContentDirectory = {
        urn = 'urn:schemas-upnp-org:service:ContentDirectory:1',
        control = '/MediaServer/ContentDirectory/Control',
        events = '/MediaRenderer/ContentDirectory/Event',
        commands = {
            Browse = {params = {ObjectID = "", BrowseFlag = "BrowseDirectChildren", Filter = "*", StartingIndex = 0, RequestedCount = 100, SortCriteria=""}}
        }
    },
    RenderingControl = {
        urn = 'urn:schemas-upnp-org:service:RenderingControl:1',
        control = '/MediaRenderer/RenderingControl/Control',
        events = '/MediaRenderer/RenderingControl/Event',
        commands = {
            GetVolume = {params = {InstanceID = 0, Channel = "Master"}},
            GetMute = {params = {InstanceID = 0, Channel = "Master"}},
            SetVolume = {params = {InstanceID = 0, Channel = "Master", DesiredVolume = 50}},
            SetMute = {params = {InstanceID = 0, Channel = "Master", DesiredMute = true}},
        }
    },
    GroupRenderingControl = {
        urn = 'urn:schemas-upnp-org:service:GroupRenderingControl:1',
        control = '/MediaRenderer/GroupRenderingControl/Control',
        events = '/MediaRenderer/GroupRenderingControl/Event',
        commands = {
            GetGroupVolume = {params = {InstanceID = 0}},
            GetGroupMute = {params = {InstanceID = 0}},
            SetGroupVolume = {params = {InstanceID = 0, DesiredVolume = 50}},
            SetGroupMute = {params = {InstanceID = 0, DesiredMute = true}},
        }
    },
    ZoneGroupTopology = {
        urn = 'urn:schemas-upnp-org:service:ZoneGroupTopology:1',
        control = '/ZoneGroupTopology/Control',
        events = '/ZoneGroupTopology/Event',
        commands = {
            GetZoneGroupState = {},
            GetZoneGroupAttributes = {}
        }
    },
    AVTransport = {
        urn = 'urn:schemas-upnp-org:service:AVTransport:1',
        control = '/MediaRenderer/AVTransport/Control',
        events = '/MediaRenderer/AVTransport/Event',
        commands = {
            SetAVTransportURI = {params = {InstanceID = 0, CurrentURI = "", CurrentURIMetaData= ""}},
            RemoveAllTracksFromQueue = {params = {InstanceID = 0}},
            AddURIToQueue = {params = {InstanceID = 0, EnqueuedURI = "", EnqueuedURIMetaData= "", DesiredFirstTrackNumberEnqueued=0, EnqueueAsNext=false}},
            GetMediaInfo = {params = {InstanceID = 0}},
            GetPositionInfo = {params = {InstanceID = 0}},
            GetTransportInfo = {params = {InstanceID = 0}}, -- STOPPED / PLAYING / PAUSED_PLAYBACK / TRANSITIONING
            GetTransportSettings = {params = {InstanceID = 0}}, -- NORMAL / REPEAT_ALL / REPEAT_ONE / SHUFFLE_NOREPEAT / SHUFFLE / SHUFFLE_REPEAT_ONE
            SetPlayMode = {params = {InstanceID = 0, NewPlayMode = ""}}, -- NORMAL / REPEAT_ALL / REPEAT_ONE / SHUFFLE_NOREPEAT / SHUFFLE / SHUFFLE_REPEAT_ONE
            Play = {params = {InstanceID = 0, Speed = 1}},
            Pause = {params = {InstanceID = 0}},
            Stop = {params = {InstanceID = 0}},
            Next = {params = {InstanceID = 0}},
            Previous = {params = {InstanceID = 0}},
            Seek = {params = {InstanceID = 0, Unit = "", Target = ""}}, --TRACK_NR / REL_TIME / TIME_DELTA // Position of track in queue (start at 1) or hh:mm:ss for REL_TIME or +/-hh:mm:ss for TIME_DELTA
        }
    },
    Queue = {
        urn = 'urn:schemas-sonos-com:service:Queue:1',
        control = '/MediaRenderer/Queue/Control',
        events = '/MediaRenderer/Queue/Event',
        commands = {

        }
    }
}

local muted_calls = {
    GetMediaInfo = true,
    GetMute = true,
    GetPositionInfo = true,
    GetTransportInfo = true,
    GetTransportSettings = true,
    GetVolume = true,
    GetGroupVolume = true,
    GetGroupMute = true,
}

local function get_command_meta(command)
    local result = nil
    for type, meta in pairs(types) do
        for cmd, item in pairs(meta.commands) do
            if cmd:lower() == command:lower() then
                result = {type = type, urn = meta.urn, events = meta.events, command = cmd, control = meta.control, params = item.params}
                break
            end
        end
        if result then
            break
        end
    end
    return result
end

local M = {}; M.__index = M

local function constructor(self,o)
    o = o or {}
    o.players = o.players or nil
    o.favorites = o.favorites or nil
    o.playlists = o.playlists or nil
    o.last_updated = o.last_updated or nil
    setmetatable(o, M)
    return o
end
setmetatable(M, {__call = constructor})

local _instance = nil

function M.get_instance() 
    if not _instance then
        _instance = M()
    end
    return _instance
end


local function get_config(ip)
    local res = {}
    local url = 'http://'..ip..':'..config.SONOS_HTTP_PORT..'/xml/group_description.xml'
    log.debug('getting config '..url)
    local _, status = http.request({
      url=url,
      sink=ltn12.sink.table(res)
    })
    log.debug('got config '..url)

    if next(res) then 
        -- XML Parser
        local xmlres = xml_handler:new()
        local xml_parser = xml2lua.parser(xmlres)
        xml_parser:parse(table.concat(res))

        -- Device metadata
        return xmlres.root.root.device
    else
        log.error(status)
    end
end

-- SSDP Response parser
local function parse_ssdp(data)
    local res = {}
    res.status = data:sub(0, data:find('\r\n'))
    for k, v in data:gmatch('([%w%-%.]+):[%s]+([%w%+%-%:%.; /=_"]+)') do
      res[k:lower()] = v
    end
    return res
end

function M:init_player(ip)
    log.info('init player for '..ip)
    local meta = get_config(ip)
    --log.debug("meta for "..ip.." is "..utils.stringify_table(meta))
    if meta and type(meta.friendlyName) == 'string' and meta.friendlyName and "" ~= meta.friendlyName then
        return {ip=ip, id=meta.UDN:gsub('uuid:',''), name=meta.friendlyName}                   
    end
    return nil
end


-- This function enables a UDP
-- Socket and broadcast a single
-- M-SEARCH request, i.e., it
-- must be looped appart.
function M:find_players(cache, force)
    --log.debug(debug.traceback(utils.stringify_table(cache)))
    local result = get_cached(cache, 'players') or {}
    if not force and next(result) then return result end

    -- UDP socket initialization
    local upnp = socket.udp()
    upnp:setsockname('*', 0)
    upnp:setoption('broadcast', true)
    upnp:settimeout(config.MC_TIMEOUT)

    -- broadcasting request
    upnp:sendto(config.MSEARCH, config.MC_ADDRESS, config.MC_PORT)

    -- Socket will wait n seconds
    -- based on the s:setoption(n)
    -- to receive a response back.
    local err
    log.debug("discovering sonos speakers...")
    local ips = {}
    repeat
        local res, ip = upnp:receivefrom()
        if nil == res then
            err = ip
        else
            res = parse_ssdp(res)
            if(res and res.st and config.URN == res.st) then
                log.info('got a SSDP response from '..ip)
                log.debug(utils.stringify_table(res))
                local id = res.usn and res.usn:gsub('::urn.+',''):gsub('uuid:','') or nil
                local name = res['groupinfo.smartspeaker.audio'] and res['groupinfo.smartspeaker.audio']:match('gname="([^"]+)') or nil
                local household = res['household.smartspeaker.audio']
                if name and id then
                    log.info(id..': found sonos player at '..ip..' named '..name)
                    table.insert(result, {ip = ip, id = id, name = name, household = household})
                else
                    table.insert(ips, ip)
                end
            end
        end
    until err
    log.debug('got all the SSDP responses we will get...')
    -- close udp socket
    upnp:close()

    if not next(result) then
        for _, ip in ipairs(ips) do
            local player = self:init_player(ip)
            if player then 
                log.info('found a sonos speaker at '..player.ip..' named '..player.name)
                table.insert(result, player) 
            end
        end
    end

    self.players = result
    if result then set_cached(cache, 'players', result) end
    return next(result) and result or nil
end

local function get_device_url(device)
    return 'http://'..device.ip..':'..config.SONOS_HTTP_PORT
end

function M:get_types_meta()
    return types
end

function M:process_event(player, event)
    local player = assert(self:get_player(player))
    return metadata.parse_properties(event, player.ip, config.SONOS_HTTP_PORT)
end

function M:subscribe_events(player, type, callback, sid)
    local player = assert(self:get_player(player))
    local i = 0
    repeat
        local host = player.ip..':'..config.SONOS_HTTP_PORT
        local headers = {
            Host = host,
            TIMEOUT = 'Second-'..config.SUBSCRIPTION_TIME,
        }
        if sid then
            headers.SID = sid
        else
            headers.CALLBACK = '<'..callback..'>'
            headers.NT = 'upnp:event'
        end
        local url = types[type].events
        local res = {}
        local req_result, code, res_headers, status = http.request({
            url='http://'..host..url,
            method = 'SUBSCRIBE',
            headers = headers
        })
        log.debug('SUBSCRIBE with headers '..utils.stringify_table(headers))
        if code and 200 == code then
            log.debug(utils.stringify_table(res_headers))
            sid = res_headers.sid
            log.info('subscribe successful '.. (sid or "nil"))
        else
            log.error('subscribe error with status '..(status or "nil"))
            log.error('code is '..(code or "nil"))
            sid = nil -- if renewal fails try again as new subscription
        end
        i = i + 1
    until sid or i > 1 -- if renewal fails try again as new subscription
    return sid
  end

  function M:unsubscribe_events(player, type, sid)
    local player = assert(self:get_player(player))
    local result = nil
    local host = player.ip..':'..config.SONOS_HTTP_PORT
    local headers = {
        Host = host,
        SID = sid,
    }
    local url = types[type].events
    local req_result, code, headers, status = http.request({
        url='http://'..host..url,
        method = 'UNSUBSCRIBE',
        headers = headers
      })
      if code and 200 == code then
        log.info('unsubscribe successful ')
    else
        log.error('unsubscribe error with status '..(status or "nil"))
        log.error('code is '..(code or "nil"))
    end
    return result
  end

local function get_request_body(command)
    local result = [[<?xml version="1.0" encoding="utf-8"?>
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <s:Body>
        <u:%(cmd)s xmlns:u="%(urn)s">
        %(paramxml)s
        </u:%(cmd)s>
      </s:Body>
    </s:Envelope>]] % command
    return result
end

local function toXml(params)
    local result = ""
    for key, value in pairs(params) do
        local encoded = xmlutil.xml_encode(value)
        result = result .. '<%(key)s>%(value)s</%(key)s>' % {key = key, value = encoded}
    end
    return result
end

local function get_param_xml(cmd, params)
    local paramXml = ""
    if cmd.params then
        --log.debug(utils.stringify_table(cmd.params))
        --log.debug(utils.stringify_table(params))
        local parameters = utils.deep_copy(cmd.params)
        if params then
            for key, value in pairs(parameters) do
                if params[key] ~= nil then
                    local param = (type(params[key]) == 'boolean' and (params[key] and 1 or 0)) or params[key]
                    parameters[key] = param
                end
            end
        end
        paramXml = toXml(parameters)
    end
    return paramXml
end

function M:cmd(player, command, params)
    local player = assert(self:get_player(player))
    local ip = assert(player.ip)

    local res = {}
    local url = get_device_url(player)
    local cmd = assert(get_command_meta(command))

    url = url..cmd.control
    local cparams = {cmd = cmd.command, type = cmd.type, urn = cmd.urn, paramxml = ""}
    cparams.paramxml = get_param_xml(cmd, params)
    local body = get_request_body(cparams)
    local headers = {
        Host = ip..':1400',
        soapaction = cmd.urn..'#'..cmd.command,
        ['Content-Type'] = 'text/xml; charset="utf-8"',
        ['Content-Length'] = #body
    }
    if not muted_calls[command] then
        log.debug("executing on "..player.name.." command "..command.." with params "..(params and utils.stringify_table(params) or "none"))
    end
    --log.debug(url)
    --log.debug(utils.stringify_table(headers))
    --log.debug(body)

    local req_result, code, res_headers, status = http.request({
      url=url,
      method = 'POST',
      headers = headers,
      source = ltn12.source.string(body),
      sink=ltn12.sink.table(res)
    })
  
    local result
    if 200 == code then
        -- XML Parser
        local xmlres = xml_handler:new()
        local xml_parser = xml2lua.parser(xmlres)
        xml_parser:parse(table.concat(res))
        result = xmlres.root['s:Envelope']['s:Body']['u:'..cmd.command..'Response']
        if params and params.parse and result[params.parse] then
            local decoded = xmlutil.xml_decode(result[params.parse])
            --log.info('need to parse..'..decoded)
            local result_handler = xml_handler:new()
            local result_parser = xml2lua.parser(result_handler)
            result_parser:parse(decoded)
            if result_handler.root then
                result[params.parse] = result_handler.root
            end
        end
        --log.debug(utils.stringify_table(result))     
    else
        result = nil
        if 500 == code then
            local xmlres = xml_handler:new()
            local xml_parser = xml2lua.parser(xmlres)
            xml_parser:parse(table.concat(res))
            local err = xmlres.root['s:Envelope']['s:Body']['s:Fault']['detail']['UPnPError']['errorCode']
            log.error(player.name..' : '..command.." error code "..(err or "nil").." "..(code and errors[err] or "nil"))
        else 
            log.error(player.name..' : '..command..' error with code '..tostring(code)..', status '..tostring(status)..' and content '..table.concat(res))
        end
    end

    return result
end

function M:any_player()
    return self:get_player()
end

function M:get_player(name)
    if name and type(name) == 'table' and name.ip then
        return name
    end
    if name and name:match('%d+%.%d+%.%d+%.%d+') then -- is an ip address
        return self:init_player(name)
    end
    local players = assert(self.players)
    if players then
        if not name or "" == name then -- any player will do
            return players[math.random(#players)]
        end
        name = name:gsub('uuid:','')
        for i, item in ipairs(players) do
            if item.name:lower() == name:lower() then return item end
            if item.id == name then return item end
        end
    end
    return nil
end

function M:browse(term)
    local result = nil
    local i = 0
    repeat
        local player = assert(self:any_player())
        local didl
        local status, err = pcall( function () 
            didl = self:cmd(player.id,'Browse', {ObjectID = term})
            if not didl or not didl['Result'] then return nil else didl = didl['Result'] end
            result = metadata.parse_didl(didl, player.ip, config.SONOS_HTTP_PORT)
            --log.debug(result and utils.stringify_table(result) or "nil")
        end)
        i = i + 1
        if not status then
            log.warn('browse failed due to '..tostring(err)..' : retrying ..')
            log.debug(didl)
            socket.sleep(1)
        end
    until status or i > 1
    return result
end

function M:find_favorites(cache, force)
    local result = get_cached(cache, 'favorites') or {}
    if not force and next(result) then return result end
    log.info('getting favorites...')
    self.favorites = self:browse('FV:2')
    if self.favorites then set_cached(cache, 'favorites', self.favorites) end
    return self.favorites
end

function M:find_playlists(cache, force)
    local result = get_cached(cache, 'playlists') or {}
    if not force and next(result) then return result end
    log.info('getting playlists...')
    self.playlists = self:browse('SQ:')
    if self.playlists then set_cached(cache, 'playlists', self.playlists) end
    return self.playlists
end

function M:playback_cmd(player, cmd)
    return self:cmd(player, cmd) and true or false
end

function M:mute_cmd(player, state)
    return self:cmd(player, 'SetGroupMute', {DesiredMute = state and true or false}) and true or false
end

function M:play(player)
    return self:playback_cmd(player, 'Play')
end

function M:stop(player)
    return self:playback_cmd(player, 'Stop')
end

function M:pause(player)
    return self:playback_cmd(player, 'Pause')
end

function M:prev(player)
    return self:playback_cmd(player, 'Previous')
end

function M:next(player)
    return self:playback_cmd(player, 'Next')
end

function M:get_mute(player) 
    local result = self:cmd(player, 'GetGroupMute')
    return result and result.CurrentMute or nil
end

function M:mute(player)
    return self:mute_cmd(player, true)
end

function M:unmute(player)
    return self:mute_cmd(player, false)
end

function M:get_volume(player) 
    local result = self:cmd(player, 'GetGroupVolume')
    return result and result.CurrentVolume and tonumber(result.CurrentVolume) or nil
end

function M:set_volume(player, volume) -- number between 0 and 100
    assert(volume and type(volume) == "number" and volume >= 0 and volume <= 100)
    return self:cmd(player, 'SetGroupVolume', {DesiredVolume = volume}) and true or false
end

function M:set_uri(player, uri, mdata)
    log.info("setting uri on "..player.." to "..uri)
    return self:cmd(player, 'SetAVTransportURI', {CurrentURI = uri, CurrentURIMetaData = (mdata or "")}) and true or false
end

function M:clear_queue(player)
    log.info("clearing queue on "..player)
    return self:cmd(player, 'RemoveAllTracksFromQueue') and true or false
end

function M:add_to_queue(player, uri, mdata, beginning)
    log.info("adding to queue on "..player.." uri "..uri)
    return self:cmd(player, 'AddURIToQueue', {EnqueuedURI = uri, EnqueuedURIMetaData = (mdata or ""), DesiredFirstTrackNumberEnqueued = (beginning and 1 or 0)}) and true or false
end

function M:set_media(player, media)
    if metadata.is_radio(media.uri) then
        return self:set_uri(player, media.uri, media.metadata)
    end
    local p = assert(self:get_player(player))
    assert(self:add_to_queue(player, media.uri, media.metadata, true))
    return self:set_uri(player, "x-rincon-queue:"..p.id.."#0", "")
end

function M:play_media(player, media)
    assert(self:set_media(player, media))
    return self:play(player)
end

local function clean_name(name)
    if not name then return name end
    local result = name:lower()
    result = result:gsub("[%s,%.'\"_%-]+","")
    return result
end

function M:find_media_by_field(pname, field)
    local plist = nil
    pname = clean_name(pname)
    for _, list in ipairs({self.playlists, self.favorites}) do
        --log.debug("searching "..utils.stringify_table(list))
        for i, item in ipairs(list) do
            log.debug("searching "..item.title.." for "..pname)
            if clean_name(item[field]) == pname then
                log.info("found media "..item.title)
                plist = item
                break
            end
        end
        if plist then break end
    end
    if not plist then log.error("did not find "..pname) end
    return plist
end

function M:play_media_by_name(player, pname, replace)
    assert(self:set_media_by_name(player, pname, replace))
    return self:play(player)
end

function M:play_media_by_id(player, pid, replace)
    assert(self:set_media_by_id(player, pid, replace))
    return self:play(player)
end

function M:set_media_by_name(player, pname, replace)
    if replace then self:clear_queue(player) end
    local item = assert(self:find_media_by_field(pname, 'title'))
    return self:set_media(player, item)
end

function M:set_media_by_id(player, pid, replace)
    if replace then self:clear_queue(player) end
    local item = assert(self:find_media_by_field(pid, 'id'))
    return self:set_media(player, item)
end

function M:whats_playing(player)
    local result = nil
    local response = self:cmd(player, 'GetPositionInfo')
    if response then
        --log.debug(utils.stringify_table(response))
        local p = assert(self:get_player(player))
        result = metadata.parse_didl(response.TrackMetaData, p.ip, config.SONOS_HTTP_PORT)
        if (result) then
            result = result[1]
            result.num = response.Track and tonumber(response.Track)
            if not result.duration then
                result.duration = response.TrackDuration
            end
            result.metadata = response.TrackMetaData
            result.position = metadata.duration_in_seconds(response.RelTime)
            if result.title:match('preroll') then
                result.title = 'Pre-Roll Advertisement'
                result.album = 'Advertising'
                result.artist = 'Advertiser'
                result.type = 'Advertisement'
                result.service = result.service or 'Sonos'
            end
        end
    end
    response = self:cmd(player, 'GetMediaInfo')
    if response and result then
        result.num_tracks = response.NrTracks and tonumber(response.NrTracks)
    end
    return result
end

function M:get_play_state(player)
    local result = self:cmd(player, 'GetTransportInfo')
    return result and result.CurrentTransportState or nil
end

function M:get_play_mode(player, mode)
    local result = mode or self:cmd(player, 'GetTransportSettings')
    local shuffle = false
    local rpt = false
    local all = false

    local state = result and result.PlayMode or 'NORMAL'
    shuffle = state:match('SHUFFLE') or false
    rpt = state:match('^REPEAT') or state == 'SHUFFLE' or false
    all = state:match('_ALL') or state == 'SHUFFLE' or false
    return shuffle, rpt, all
end

function M:set_play_mode(player, shuffle, rpt, all)
    local lookup = (shuffle and 't' or 'f') .. (rpt and 't' or 'f') .. rpt and (all and 't' or 'f') or ''
    local modes = {
        ff = 'NORMAL',
        tf = 'SHUFFLE_NOREPEAT',
        ttf = 'SHUFFLE_REPEAT_ONE',
        ttt = 'SHUFFLE',
        ftf = 'REPEAT_ONE',
        ftt = 'REPEAT_ALL',
    }
    local mode = modes[lookup] or modes.ff
    return self:cmd(player, 'SetPlayMode', {NewPlayMode = mode}) and true or false
end

function M:get_state(player)
    local result = {}
    result.playing = self:whats_playing(player)
    result.mute = self:get_mute(player)
    result.volume = self:get_volume(player)
    result.state = self:get_play_state(player)
    result.shuffle, result.rpt, result.all = self:get_play_mode(player)
    return result
end

function M:update(cache, force)
    self:find_players(cache, force)
    self:find_favorites(cache, force)
    self:find_playlists(cache, force)
    local updated = force and self.players and next(self.players)
    if cache then
        cache.last_updated = updated and os.time() or cache.last_updated
    end
    self.last_updated = (updated and os.time()) or (cache and cache.last_updated) or self.last_updated
    return updated
end

return M