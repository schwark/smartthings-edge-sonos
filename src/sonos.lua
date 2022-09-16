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
            SetAVTransportURI = {params = {InstanceID = 0, CurrentURI = nil, CurrentURIMetaData= nil}},
            AddURIToQueue = {params = {InstanceID = 0, EnqueuedURI = nil, EnqueuedURIMetaData= nil, DesiredFirstTrackNumberEnqueued=0, EnqueueAsNext=false}},
            GetMediaInfo = {params = {InstanceID = 0}},
            GetPositionInfo = {params = {InstanceID = 0}},
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


local function xml_decode(str)
    str = str:gsub('&lt;', '<' )
    str = str:gsub('&gt;', '>' )
    str = str:gsub('&quot;', '"' )
    str = str:gsub('&apos;', "'" )
    str = str:gsub('&#(%d+);', function(n) return string.char(n) end )
    str = str:gsub('&#x(%d+);', function(n) return string.char(tonumber(n,16)) end )
    str = str:gsub('&amp;', '&' ) -- Be sure to do this after all others
    return str
end

local function xml_encode(str)
    str = str:gsub('&', '&amp;') -- Be sure to do this before all others
    str = str:gsub( '<' ,'&lt;')
    str = str:gsub( '>' ,'&gt;')
    str = str:gsub( '"' ,'&quot;')
    str = str:gsub( "'" ,'&apos;')
    return str
end

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


local function get_config(url)
    local res = {}
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
                log.debug("found "..ip.." and xml at "..res.location)
                local meta = get_config(res.location)
                log.debug("meta for "..ip.." is "..utils.stringify_table(meta))
                if meta and meta.friendlyName and "" ~= meta.friendlyName then
                    log.info("sonos speaker "..meta.friendlyName.." at "..ip)
                    table.insert(result, {ip=ip, id=meta.UDN, name=meta.friendlyName})                    
                end
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

local function api_safe(val)
    local result = val
    if type(val) == "boolean" then
        result = val and 1 or 0
    end
    return result
end

local function toXml(params)
    local result = ""
    for key, value in pairs(params) do
        result = result .. '<%(key)s>%(value)s</%(key)s>' % {key = key, value = value}
    end
    return result
end

local function get_param_xml(cmd, params)
    local paramXml = ""
    if cmd.params then
        log.info(utils.stringify_table(cmd.params))
        local parameters = utils.deep_copy(cmd.params)
        for key, value in pairs(parameters) do
            if not value or "" == value or params[key] then
                parameters[key] = params and params[key] and api_safe(params[key]) or ""
            end
        end
        paramXml = toXml(parameters)
    end
    return paramXml
end

function M:cmd(ip, command, params)
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
    log.debug(url)
    log.debug(utils.stringify_table(headers))
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
            local decoded = xml_decode(result[params.parse])
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
        result = status
        log.error(status)
        log.error(table.concat(res))
    end

    return result
end

function M:get_players()
    if not self.players then
        self:discover()
    end
    return self.players
end

function M:get_player(name)
    if name and name:match('%d+%.%d+%.%d+%.%d+') then -- is an ip address
        return {ip=name}
    end
    local players = self:get_players()
    if players then
        if not name or "" == name then -- any player will do
            return players[1]
        end
        for i, player in ipairs(players) do
            if player.name:lower() == name:lower() then return player end
        end
    end
    return nil
end

function M:browse(term, name)
    local player = assert(self:get_player(name))
    local ip = assert(player.ip)
    local didl = self:cmd(ip,'Browse', {ObjectID = term, parse = 'Result'})
    local result = nil
    log.debug(utils.stringify_table(didl))
    local list = didl and didl.Result['DIDL-Lite'] and didl.Result['DIDL-Lite'] and (didl.Result['DIDL-Lite'].item or didl.Result['DIDL-Lite'].container)
    if list then
        result = {}
        for i, item in ipairs(list) do
            table.insert(result, {name=item['dc:title'], metadata=item['r:resMD'], art=(type(item['upnp:albumArtURI']) == "table" and item['upnp:albumArtURI'][1] or item['upnp:albumArtURI']), uri=item.res[1], desc=item['r:description']})
        end
    end
    log.debug(result and utils.stringify_table(result) or "nil")
    return result
end

function M:find_favorites(name)
    self.favorites = self:browse('FV:2', name)
    return self.favorites
end

function M:find_playlists(name)
    self.playlists = self:browse('SQ:', name)
    return self.playlists
end

function M:playback_cmd(cmd, name)
    local player = assert(self:get_player(name))
    local ip = assert(player.ip)
    return self:cmd(ip, cmd)
end

function M:play(name)
    return self:playback_cmd('Play', name)
end

function M:stop(name)
    return self:playback_cmd('Stop', name)
end

function M:pause(name)
    return self:playback_cmd('Pause', name)
end

function M:prev(name)
    return self:playback_cmd('Previous', name)
end

function M:next(name)
    return self:playback_cmd('Next', name)
end

function M:set_uri(uri, name)
end

return M