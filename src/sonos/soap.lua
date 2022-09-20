local socket = require('socket')
local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
local http = require("socket.http")
local utils = require("st.utils")
local ltn12 = require('ltn12')
-- XML modules
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"

local log = require "log"
local math = require ('math')
local config = require('config')
local xmlutil = require('xmlutil')
local metadata = require('sonos.metadata')

SONOS_HTTP_PORT = '1400'

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

local function isRadio(uri)
    return uri:match('x-sonosapi-stream:') or
      uri:match('x-sonosapi-radio:') or
      uri:match('pndrradio:') or
      uri:match('x-sonosapi-hls:') or
      uri:match('x-sonosprog-http:');
end

local types = {
    ['urn:schemas-upnp-org:service:ContentDirectory:1'] = {
        control = '/MediaServer/ContentDirectory/Control',
        commands = {
            Browse = {params = {ObjectID = "", BrowseFlag = "BrowseDirectChildren", Filter = "*", StartingIndex = 0, RequestedCount = 100, SortCriteria=""}}
        }
    },
    ['urn:schemas-upnp-org:service:RenderingControl:1'] = {
        control = '/MediaRenderer/RenderingControl/Control',
        commands = {
            GetVolume = {params = {InstanceID = 0, Channel = "Master"}},
            GetMute = {params = {InstanceID = 0, Channel = "Master"}},
            SetVolume = {params = {InstanceID = 0, Channel = "Master", DesiredVolume = 50}},
            SetMute = {params = {InstanceID = 0, Channel = "Master", DesiredMute = true}},
        }
    },
    ['urn:schemas-upnp-org:service:ZoneGroupTopology:1'] = {
        control = '/ZoneGroupTopology/Control',
        commands = {
            GetZoneGroupState = {},
            GetZoneGroupAttributes = {}
        }
    },
    ['urn:schemas-upnp-org:service:AVTransport:1'] = {
        control = '/MediaRenderer/AVTransport/Control',
        commands = {
            SetAVTransportURI = {params = {InstanceID = 0, CurrentURI = "", CurrentURIMetaData= ""}},
            RemoveAllTracksFromQueue = {params = {InstanceID = 0}},
            AddURIToQueue = {params = {InstanceID = 0, EnqueuedURI = "", EnqueuedURIMetaData= "", DesiredFirstTrackNumberEnqueued=0, EnqueueAsNext=false}},
            GetMediaInfo = {params = {InstanceID = 0}},
            GetPositionInfo = {params = {InstanceID = 0}},
            SetPlayMode = {params = {InstanceID = 0, NewPlayMode = ""}}, -- NORMAL / REPEAT_ALL / REPEAT_ONE / SHUFFLE_NOREPEAT / SHUFFLE / SHUFFLE_REPEAT_ONE
            Play = {params = {InstanceID = 0, Speed = 1}},
            Pause = {params = {InstanceID = 0}},
            Stop = {params = {InstanceID = 0}},
            Next = {params = {InstanceID = 0}},
            Previous = {params = {InstanceID = 0}}
        }
    },
    ['urn:schemas-sonos-com:service:Queue:1'] = {
        control = '/MediaRenderer/Queue/Control',
        commands = {

        }
    }
}

local function get_command_meta(command)
    local result = nil
    for type, meta in pairs(types) do
        for cmd, item in pairs(meta.commands) do
            if cmd:lower() == command:lower() then
                result = {type = type, command = cmd, control = meta.control, params = item.params}
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
    o.players = nil
    o.favorites = nil
    o.playlists = nil
    setmetatable(o, M)
    return o
end
setmetatable(M, {__call = constructor})


local function get_config(ip)
    local res = {}
    local url = 'http://'..ip..':'..SONOS_HTTP_PORT..'/xml/group_description.xml'
    local _, status = http.request({
      url=url,
      sink=ltn12.sink.table(res)
    })
  
    -- XML Parser
    local xmlres = xml_handler:new()
    local xml_parser = xml2lua.parser(xmlres)
    xml_parser:parse(table.concat(res))
  
    -- Device metadata
    return xmlres.root.root.device
end

-- SSDP Response parser
local function parse_ssdp(data)
    local res = {}
    res.status = data:sub(0, data:find('\r\n'))
    for k, v in data:gmatch('([%w-%.]+): ([%a+-_: /=]+)') do
      res[k:lower()] = v
    end
    return res
end

function M:init_player(ip)
    local meta = get_config(ip)
    --log.debug("meta for "..ip.." is "..utils.stringify_table(meta))
    if meta and meta.friendlyName and "" ~= meta.friendlyName then
        log.info("sonos speaker "..meta.friendlyName.." at "..ip)
        return {ip=ip, id=meta.UDN:gsub('uuid:',''), name=meta.friendlyName}                   
    end
    return nil
end

-- This function enables a UDP
-- Socket and broadcast a single
-- M-SEARCH request, i.e., it
-- must be looped appart.
function M:find_devices()
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
    local result = {}
    repeat
        log.debug("discovering sonos speakers...")
        local res, ip = upnp:receivefrom()
        if nil == res then
            err = ip
        else
            res = parse_ssdp(res)
            log.debug("st is "..res.st)
            if(res and res.st and config.URN == res.st) then
                local player = self:init_player(ip)
                if player then table.insert(result, player) end
            end
        end
    until err

    -- close udp socket
    upnp:close()
    self.players = result
    return next(result) and result or nil
end
  

function M:discover()
    return self:find_devices()
end

local function get_request_body(command)
    local result = [[<?xml version="1.0" encoding="utf-8"?>
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <s:Body>
        <u:%(cmd)s xmlns:u="%(type)s">
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
                if params[key] then
                    parameters[key] = params[key]
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
    local url = 'http://'..ip..':1400'
    local cmd = assert(get_command_meta(command))

    url = url..cmd.control
    local cparams = {cmd = cmd.command, type = cmd.type, paramxml = ""}
    cparams.paramxml = get_param_xml(cmd, params)
    local body = get_request_body(cparams)
    local headers = {
        Host = ip..':1400',
        soapaction = cmd.type..'#'..cmd.command,
        ['Content-Type'] = 'text/xml; charset="utf-8"',
        ['Content-Length'] = #body
    }
    log.debug("executing on "..player.name.." command "..command.." with params "..(params and utils.stringify_table(params) or "none"))
    --log.debug(utils.stringify_table(headers))
    log.debug(body)

    local _, status = http.request({
      url=url,
      method = 'POST',
      headers = headers,
      source = ltn12.source.string(body),
      sink=ltn12.sink.table(res)
    })
  
    local result
    if 200 == status then
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
        if 500 == status then
            local xmlres = xml_handler:new()
            local xml_parser = xml2lua.parser(xmlres)
            xml_parser:parse(table.concat(res))
            local code = xmlres.root['s:Envelope']['s:Body']['s:Fault']['detail']['UPnPError']['errorCode']
            log.error("error code "..(code or "nil").." "..(code and errors[code] or "nil"))
        else 
            log.error(table.concat(res))
        end
    end

    return result
end

function M:get_players()
    if not self.players then
        self:discover()
    end
    return self.players
end

function M:any_player()
    return self:get_player()
end

function M:get_player(name)
    if name and name:match('%d+%.%d+%.%d+%.%d+') then -- is an ip address
        return self:init_player(name)
    end
    local players = self:get_players()
    if players then
        if not name or "" == name then -- any player will do
            return players[1]
        end
        for i, item in ipairs(players) do
            if item.name:lower() == name:lower() then return item end
        end
    end
    return nil
end

function M:browse(player, term)
    local didl = self:cmd(player,'Browse', {ObjectID = term})
    if not didl or not didl['Result'] then return nil else didl = didl['Result'] end
    --log.debug(didl)
    local result = metadata.parse_didl(didl, player, SONOS_HTTP_PORT)
    log.debug(result and utils.stringify_table(result) or "nil")
    return result
end

function M:find_favorites(player)
    self.favorites = self:browse(player, 'FV:2')
    return self.favorites
end

function M:find_playlists(player)
    self.playlists = self:browse(player, 'SQ:')
    return self.playlists
end

function M:playback_cmd(player, cmd)
    return self:cmd(player, cmd)
end

function M:mute_cmd(player, state)
    return self:cmd(player, 'SetMute', {DesiredMute = state and true or false})
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

function M:mute(player)
    return self:mute_cmd(player, true)
end

function M:unmute(player)
    return self:mute_cmd(player, false)
end

function M:set_volume(player, volume) -- number between 0 and 100
    assert(volume)
    return self:cmd(player, 'SetVolume', {DesiredVolume = volume})
end

function M:set_uri(player, uri, mdata)
    log.info("setting uri on "..player.." to "..uri)
    return self:cmd(player, 'SetAVTransportURI', {CurrentURI = uri, CurrentURIMetaData = (mdata or "")})
end

function M:clear_queue(player)
    log.info("clearing queue on "..player)
    return self:cmd(player, 'RemoveAllTracksFromQueue')
end

function M:add_to_queue(player, uri, mdata, beginning)
    log.info("adding to queue on "..player.." uri "..uri)
    return self:cmd(player, 'AddURIToQueue', {EnqueuedURI = uri, EnqueuedURIMetaData = (mdata or ""), DesiredFirstTrackNumberEnqueued = (beginning and 1 or 0)})
end

function M:set_media(player, media)
    if isRadio(media.uri) then
        return self:set_uri(media.uri, media.metadata)
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
    local result = name:lower()
    result = result:gsub("[%s,'\"_%-]+","")
    return result
end

function M:find_media_by_field(pname, field)
    local plist = nil
    pname = clean_name(pname)
    for _, list in ipairs({self.playlists, self.favorites}) do
        for i, item in ipairs(list) do
            --log.debug("searching "..item.name.." for "..pname)
            if pname == clean_name(item[field]) then
                log.info("found media "..item.name)
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
    return self:play()
end

function M:play_media_by_id(player, pid, replace)
    assert(self:set_media_by_id(player, pid, replace))
    return self:play()
end

function M:set_media_by_name(player, pname, replace)
    if replace then self:clear_queue(player) end
    local item = assert(self:find_media_by_field(pname, 'name'))
    return self:set_media(player, item)
end

function M:set_media_by_id(player, pid, replace)
    if replace then self:clear_queue(player) end
    local item = assert(self:find_media_by_field(pid, 'id'))
    return self:set_media(player, item)
end

function M:whats_playing(player)
    local result = nil
    log.info("getting current playing on "..player)
    local response = self:cmd(player, 'GetPositionInfo')
    if response then
        log.debug(utils.stringify_table(response))
        result = metadata.parse_didl(response.TrackMetaData, player, SONOS_HTTP_PORT)
        if (result) then
            result = result[1]
            result.num = response.TrackNum
            result.duration = response.TrackDuration
            result.metadata = response.TrackMetaData
            result.position = response.RelTime            
        end
    end
    return result
end

return M