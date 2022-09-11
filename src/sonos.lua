local socket = require('socket')
local cosock = require "cosock"
local http = cosock.asyncify "socket.http"
local ltn12 = require('ltn12')
-- XML modules
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"

--local utils = require("st.utils")
local log = require "log"
local math = require ('math')
local config = require('config')
local utils = require("st.utils")

local function interp(s, tab)
    return (s:gsub('%%%((%a%w*)%)([-0-9%.]*[cdeEfgGiouxXsq])',
              function(k, fmt) return tab[k] and ("%"..fmt):format(tab[k]) or
                  '%('..k..')'..fmt end))
end
getmetatable("").__mod = interp


local types = {
    ['urn:schemas-upnp-org:service:ZoneGroupTopology:1'] = {
        control = 'ZoneGroupTopology/Control',
        commands = {
            GetZoneGroupState = {}
        }
    },
    ['urn:schemas-upnp-org:service:AVTransport:1'] = {
        control = 'MediaRenderer/AVTransport/Control',
        commands = {
            Play = {params = {InstanceID = 0, Speed = 1}},
            Pause = {params = {InstanceID = 0}},
            Stop = {params = {InstanceID = 0}},
            Next = {params = {InstanceID = 0}},
            Previous = {params = {InstanceID = 0}}
        }
    },
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
        local res, ip = upnp:receivefrom()
        if nil == res then
            err = ip
        else
            res = parse_ssdp(res)
            log.info("speaker at "..ip.." and xml at "..res.location)
            table.insert(result, {ip=ip, meta=get_config(res.location)})
        end
    until err

    -- close udp socket
    upnp:close()
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

function M:cmd(ip, command, params)
    local res = {}
    local url = 'http://'..ip..':1400/'
    local cmd = assert(get_command_meta(command))

    url = url..cmd.control
    local cparams = {cmd = cmd.command, type = cmd.type, paramxml = ""}
    local parameters = nil
    if cmd.params then
        parameters = utils.deep_copy(cmd.params)
        for key, value in pairs(parameters) do
            if not value or "" == value then
                parameters[key] = params and params[key] and api_safe(params[key]) or ""
            end
        end
        cparams.paramxml = toXml(parameters)
    end
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
        log.debug(utils.stringify_table(result))     
    else
        result = status
        log.error(status)
        log.error(table.concat(res))
    end

    return result
end

return M