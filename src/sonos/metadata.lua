local xmlutil = require('xmlutil')
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"
local utils = require("st.utils")
local log = require "log"

local M = {}

local function interp(s, tab)
  return (s:gsub('%%%((%a%w*)%)([-0-9%.]*[cdeEfgGiouxXsq])',
    function(k, fmt) return tab[k] and ("%" .. fmt):format(tab[k]) or
          '%(' .. k .. ')' .. fmt
    end))
end

getmetatable("").__mod = interp


local function matches(s, pattern)
  local t = {}
  for v in string.gmatch(s, pattern) do
    table.insert(t, v)
  end
  return t
end

getmetatable("").matches = matches


local function split(s, separator)
  local t = {}
  for v in string.gmatch(s, "[^" .. separator .. "]+") do
    table.insert(t, v)
  end
  return t
end

getmetatable("").split = split

local function trim_whitespace(s)
  s = s:gsub('^%s+', '')
  s = s:gsub('%s+$', '')
  return s
end

getmetatable("").trim = trim_whitespace

local function starts_with(s, prefix)
  return s:match('^' .. prefix)
end

getmetatable("").starts_with = starts_with


local function get_upnp_class(parentid)
  local classes = {
    ['A:ALBUMS'] = 'object.item.audioItem.musicAlbum',
    ['A:TRACKS'] = 'object.item.audioItem.musicTrack',
    ['A:ALBUMARTIST'] = 'object.item.audioItem.musicArtist',
    ['A:GENRE'] = 'object.container.genre.musicGenre',
    ['A:COMPOSER'] = 'object.container.person.composer'
  }
  return classes[parentid] or ''
end

function M.parse_didl(didl, host, port)
  if (not didl or not didl:match('^<DIDL')) then return nil end
  log.debug('Parsing DIDL...')
  local result = nil

  local result_handler = xml_handler:new()
  local result_parser = xml2lua.parser(result_handler)
  result_parser:parse(didl)
  if not result_handler.root or not result_handler.root['DIDL-Lite'] then return nil end

  local parsed_items = result_handler.root['DIDL-Lite'].item or result_handler.root['DIDL-Lite'].container
  if not parsed_items[1] then parsed_items = { parsed_items } end

  for _, didl_item in ipairs(parsed_items) do
    local track = {
      album = didl_item['upnp:album'],
      artist = didl_item['dc:creator'],
      art = nil,
      title = didl_item['dc:title'],
      upnp_class = didl_item['upnp:class'],
      duration = nil,
      id = didl_item._attr.id,
      parentid = didl_item._attr.parentID,
      uri = "",
      protocol_info = ""
    }
    if (didl_item['r:streamContent'] and type(didl_item['r:streamContent']) == 'string' and track.Artist == nil) then
      local streamContent = didl_item['r:streamContent']:split('-')
      if (#streamContent == 2) then
        track.artist = streamContent[1]:trim()
        track.title = streamContent[2]:trim()
      else
        track.artist = streamContent[1].trim()
        if (didl_item['r:radioShowMd'] and type(didl_item['r:radioShowMd']) == 'string') then
          local radioShowMd = didl_item['r:radioShowMd']:split(',')
          track.title = radioShowMd[1]:trim()
        end
      end
    end
    if (didl_item['upnp:albumArtURI']) then
      local uri = type(didl_item['upnp:albumArtURI']) == "table" and didl_item['upnp:albumArtURI'][1] or
          didl_item['upnp:albumArtURI']
      -- Github user @hklages discovered that the album uri sometimes doesn't work because of encodings
      -- See https://github.com/svrooij/node-sonos-ts/issues/93 if you found and album art uri that doesn't work
      local art = uri:gsub('&amp;', '&'); -- :gsub(/%25/g, '%'):gsub(/%3a/gi, ':')
      track.art = art:match('^http') and art or 'http://%(host)s:%(port)s%(art)s' % { host = host, port = port, art = art }
    end

    if (didl_item.res) then
      track.duration = didl_item.res._attr.duration
      track.uri = didl_item.res[1]
      track.protocol_info = didl_item.res._attr.protocolInfo
    end

    if (didl_item['r:resMD']) then
      if type(didl_item['r:resMD']) == 'table' then
        track.metadata = xmlutil.tight_xml(xmlutil.toXml(didl_item['r:resMD']))
      else
        assert(type(didl_item['r:resMD']) == 'string')
        track.metadata = didl_item['r:resMD']
      end
    end

    if not result then result = {} end
    table.insert(result, track)
  end

  return result
end

function M.track_metadata(track, includeResource, cdudn)
  if track == nil then
    return ''
  end

  if not cdudn then
    cdudn = 'RINCON_AssociatedZPUDN'
  end

  local localCdudn = track.cdudn or cdudn
  local protocolInfo = track.protocol_info or 'http-get:*:audio/mpeg:*'
  local itemId = track.id or '-1'

  local metadata = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
  local parent_attr = track.parentid and ' parentID="' .. track.parentid .. '"' or ''
  metadata = metadata ..
      '<item id="%(itemId)s" restricted="true"%(parent_attr)s>' % { itemId = itemId, parent_attr = parent_attr }
  if (includeResource) then metadata = metadata ..
      '<res protocolInfo="%(proto)s" duration="%(duration)s">%(uri)s</res>' %
      { proto = protocolInfo, duration = track.duration, uri = track.uri } end
  if (track.art) then metadata = metadata .. '<upnp:albumArtURI>%(art)s</upnp:albumArtURI>' % { art = track.art } end
  if (track.title) then metadata = metadata .. '<dc:title>%(title)s</dc:title>' % { title = track.title } end
  if (track.artist) then metadata = metadata .. '<dc:creator>%(artist)s</dc:creator>' % { artist = track.artist } end
  if (track.album) then metadata = metadata .. '<upnp:album>%(album)s</upnp:album>' % { album = track.album } end
  if (track.upnp_class) then metadata = metadata ..
      '<upnp:class>%(upnp_class)s</upnp:class>' % { upnp_class = track.upnp_class } end
  metadata = metadata ..
      '<desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">%(localCdudn)s</desc>' %
      { localCdudn = localCdudn }
  metadata = metadata .. '</item></DIDL-Lite>'
  return metadata
end

function M.GuessMetaDataAndTrackUri(trackUri, spotifyRegion)
  if not spotifyRegion then spotifyRegion = '2311' end
  local metadata = M.GuessTrack(trackUri, spotifyRegion)

  return {
    uri = (not metadata or not metadata.uri) and trackUri or xmlutil.xml_decode(metadata.uri),
    metadata = metadata or ''
  }
end

local function spotifyMetadata(trackUri, kind, region)
  local spotifyUri = trackUri:gsub(':', '%3a')
  local track = {
    title = '',
    cdudn = 'SA_RINCON%(region)s_X_#Svc%(region)s-0-Token' % { region = region },
  }

  if kind == 'album' then
    track.uri = 'x-rincon-cpcontainer:1004206c%(uri)s?sid=9&flags=8300&sn=7' % { uri = spotifyUri }
    track.id = '0004206c%(uri)s' % { uri = spotifyUri }
    track.upnp_class = 'object.container.album.musicAlbum'
    return track
  end
  if kind == 'artistRadio' then
    track.uri = 'x-sonosapi-radio:%(uri)s?sid=9&flags=8300&sn=7' % { uri = spotifyUri }
    track.id = '100c206c%(uri)s' % { uri = spotifyUri }
    track.title = 'Artist radio'
    track.upnp_class = 'object.item.audioItem.audioBroadcast.#artistRadio'
    track.parentid = '10052064%(uri)s' % { uri = spotifyUri:gsub('artistRadio', 'artist') }
    return track
  end
  if kind == 'artistTopTracks' then
    track.uri = 'x-rincon-cpcontainer:100e206c%(uri)s?sid=9&flags=8300&sn=7' % { uri = spotifyUri }
    track.id = '100e206c%(uri)s' % { uri = spotifyUri }
    track.parentid = '10052064%(uri)s' % { uri = spotifyUri:gsub('artistTopTracks', 'artist') }
    track.upnp_class = 'object.container.playlistContainer'
    return track
  end
  if kind == 'playlist' then
    track.uri = 'x-rincon-cpcontainer:1006206c%(uri)s?sid=9&flags=8300&sn=7' % { uri = spotifyUri }
    track.id = '1006206c%(uri)s' % { uri = spotifyUri }
    track.title = 'Spotify playlist'
    track.upnp_class = 'object.container.playlistContainer'
    track.parentid = '10fe2664playlists'
    return track
  end
  if kind == 'track' then
    track.uri = 'x-sonos-spotify:%(uri)s?sid=9&amp;flags=8224&amp;sn=7' % { uri = spotifyUri }
    track.id = '00032020%(uri)s' % { uri = spotifyUri }
    track.upnp_class = 'object.item.audioItem.musicTrack'
    return track
  end
  if kind == 'user' then
    track.uri = 'x-rincon-cpcontainer:10062a6c%(uri)s?sid=9&flags=10860&sn=7' % { uri = spotifyUri }
    track.id = '10062a6c%(uri)s' % { uri = spotifyUri }
    track.title = 'User\'s playlist'
    track.upnp_class = 'object.container.playlistContainer'
    track.parentid = '10082664playlists'
    return track
  end
  log.debug('Don\'t support this Spotify uri ' .. trackUri)
  return nil
end

local function deezerMetadata(kind, -- 'album' | 'artistTopTracks' | 'playlist' | 'track' | unknown
                              id, region)
  if not region then region = '519' end
  local track = {
    cdudn = 'SA_RINCON%(region)s_X_#Svc%(region)s-0-Token' % { region = region },
  }
  if kind == 'album' then
    track.uri = 'x-rincon-cpcontainer:1004006calbum-%(id)s?sid=2&flags=108&sn=23' % { kind = kind, id = id }
    track.upnp_class = 'object.container.album.musicAlbum.#HERO'
    track.id = '1004006calbum-%(id)s' % { kind = kind, id = id }
    return track
  end
  if kind == 'artistTopTracks' then
    track.uri = 'x-rincon-cpcontainer:10fe206ctracks-artist-%(id)s?sid=2&flags=8300&sn=23' % { kind = kind, id = id }
    track.upnp_class = 'object.container.#DEFAULT'
    track.id = '10fe206ctracks-artist-%(id)s' % { kind = kind, id = id }
    return track
  end
  if kind == 'playlist' then
    track.uri = 'x-rincon-cpcontainer:1006006cplaylist_spotify%3aplaylist-%(id)s?sid=2&flags=108&sn=23' %
        { kind = kind, id = id }
    track.upnp_class = 'object.container.playlistContainer.#DEFAULT'
    track.id = '1006006cplaylist_spotify%3aplaylist-%(id)s' % { kind = kind, id = id }
    return track
  end
  if kind == 'track' then
    track.uri = 'x-sonos-http:tr:%(id)s.mp3?sid=2&flags=8224&sn=23' % { kind = kind, id = id }
    track.upnp_class = 'object.item.audioItem.musicTrack.#DEFAULT'
    track.id = '10032020tr%3a%(id)s' % { kind = kind, id = id }
    return track
  end
  return nil
end

local function appleMetadata(kind,
                             -- 'album' | 'libraryalbum' | 'track' | 'librarytrack' | 'song' | 'playlist' | 'libraryplaylist' | unknown
                             id, region)
  if not region then region = '52231' end
  local track = {
    title = '',
    cdudn = "SA_RINCON%(region)s_X_#Svc%(region)s-0-Token" % { region = region },
  }
  local trackLabels = { song = 'song', track = 'song', librarytrack = 'librarytrack' }
  if kind:match('album') then
    track.uri = 'x-rincon-cpcontainer:1004206c%(kind)s:%(id)s?sid=204' % { kind = kind, id = id }
    track.id = '1004206c%(kind)s%3a%(id)s'
    track.upnp_class = 'object.item.audioItem.musicAlbum'
    track.parentid = '00020000album%3a'
    return track
  end
  if kind:match('playlist') then
    track.uri = 'x-rincon-cpcontainer:1006206c%(kind)s:%(id)s?sid=204' % { kind = kind, id = id }
    track.id = '1006206c%(kind)s%3a%(id)s'
    track.upnp_class = 'object.container.playlistContainer'
    track.parentid = '00020000playlist%3a'
    return track
  end
  if kind:match('track') or kind:match('song') then
    track.uri = 'x-sonos-http:%(trackLabels[kind])s:%(id)s.mp4?sid=204' % { kind = kind, id = id }
    track.id = '10032020%(trackLabels[kind])s%3a%(id)s'
    track.upnp_class = 'object.item.audioItem.musicTrack'
    track.parentid = '1004206calbum%3a'
    return track
  end
  log.debug('Don\'t support this Apple Music kind ' .. kind)
  return nil
end

function M.guess_track(trackUri, spotifyRegion)
  if not spotifyRegion then spotifyRegion = '2311' end
  log.debug('Guessing metadata for ' .. trackUri)
  local title = trackUri:gsub('%.%w+$', ''):match('.*/(.*)$') or ''
  local track = {
  }
  if (trackUri:starts_with('x-file-cifs')) then
    track.id = trackUri:gsub('x-file-cifs', 'S'):gsub('%s', '%20')
    track.title = title:gsub('%20', ' ')
    track.parentid = 'A:TRACKS'
    track.upnp_class = get_upnp_class(track.parentid)
    track.uri = trackUri
    track.cdudn = 'RINCON_AssociatedZPUDN'
    return track
  end
  if (trackUri:starts_with('file:///jffs/settings/savedqueues.rsq#') or trackUri:starts_with('sonos:playlist:')) then
    local queueId = trackUri.match("%d+")
    if (queueId) then
      track.uri = 'file:///jffs/settings/savedqueues.rsq#%(queueId)s' % { queueId = queueId }
      track.upnp_class = 'object.container.playlistContainer'
      track.id = 'SQ:%(queueId[0])s' % { queueId = queueId }
      track.cdudn = 'RINCON_AssociatedZPUDN'
      return track
    end
  end
  if (trackUri:starts_with('x-rincon-playlist')) then
    local parentID = trackUri:match('.*#(.*)%/.*')
    assert(parentID)
    track.id = '%(parentID)s/%(title)s' % { parentID = parentID, title = title:gsub("%s", '%20') }
    track.title = title:gsub('%20', ' ')
    track.upnp_class = get_upnp_class(parentID)
    track.parentid = parentID
    track.cdudn = 'RINCON_AssociatedZPUDN'
    return track
  end

  if (trackUri:starts_with('x-sonosapi-stream:')) then
    track.upnp_class = 'object.item.audioItem.audioBroadcast'
    track.title = 'Some radio station'
    track.id = '10092020_xxx_xxxx' -- Add station ID from url (regex?)
    return track
  end

  if (trackUri:starts_with('x-rincon-cpcontainer:1006206ccatalog')) then -- Amazon prime container
    track.uri = trackUri
    track.id = trackUri:gsub('x-rincon-cpcontainer:', '')
    track.upnp_class = 'object.container.playlistContainer'
    return track
  end

  if (trackUri:starts_with('x-rincon-cpcontainer:100d206cuser-fav')) then -- Sound Cloud likes
    track.uri = trackUri
    track.id = trackUri:gsub('x-rincon-cpcontainer:', '')
    track.upnp_class = 'object.container.albumList'
    track.cdudn = 'SA_RINCON40967_X_#Svc40967-0-Token'
    return track
  end

  if (trackUri:starts_with('x-rincon-cpcontainer:1006206cplaylist')) then -- Sound Cloud playlists
    track.uri = trackUri
    track.id = trackUri:gsub('x-rincon-cpcontainer:', '')
    track.upnp_class = 'object.container.playlistContainer'
    track.cdudn = 'SA_RINCON40967_X_#Svc40967-0-Token'
    return track
  end

  if (trackUri:starts_with('x-rincon-cpcontainer:1004006calbum-')) then -- Deezer Album
    local numbers = trackUri:match("%d+")
    if (numbers and numbers:len() >= 2) then
      return deezerMetadata('album', numbers)
    end
  end

  local kind, id

  kind, id = trackUri:match('x-rincon-cpcontainer:1004206c([^:]+):([%.%w]+)')
  if (id) then -- Apple Music Album
    return appleMetadata(kind, id)
  end

  kind, id = trackUri:match('x-rincon-cpcontainer:1006206c([^:]+):([%.%w]+)')
  if (id) then -- Apple Music Playlist
    return appleMetadata(kind, id)
  end

  kind, id = trackUri:match('x-sonos-http:([^:]+):([%.%w]+)%.mp4%?.*sid=204')
  if (id and 'song' == kind or 'librarytrack' == kind) then -- Apple Music Track
    return appleMetadata(kind, id)
  end

  if (trackUri:starts_with('x-rincon-cpcontainer:10fe206ctracks-artist-')) then -- Deezer Artists Top Tracks
    local numbers = trackUri:matches('%d+')
    if (numbers and #numbers >= 3) then
      return deezerMetadata('artistTopTracks', numbers[3])
    end
  end

  if (trackUri:starts_with('x-rincon-cpcontainer:1006006cplaylist_spotify%3aplaylist-')) then -- Deezer Playlist
    local numbers = trackUri:matches('%d+')
    if (numbers and #numbers >= 3) then
      return deezerMetadata('playlist', numbers[3])
    end
  end

  if (trackUri:starts_with('x-sonos-http:tr%3a') and trackUri:match('sid=2')) then -- Deezer Track
    local numbers = trackUri:match('%d+')
    if (numbers) then
      return deezerMetadata('track', numbers)
    end
  end

  local parts = trackUri:split(':')
  if ((#parts == 3 or #parts == 5) and parts[1] == 'spotify') then
    return spotifyMetadata(trackUri, parts[2], spotifyRegion)
  end

  if (#parts == 3 and parts[1] == 'deezer') then
    return deezerMetadata(parts[2], parts[3])
  end

  if (#parts == 3 and parts[1] == 'apple') then
    return appleMetadata(parts[2], parts[3])
  end

  if (#parts == 2 and parts[1] == 'radio' and parts[2]:starts_with('s')) then
    local stationId = parts[2]
    track.upnp_class = 'object.item.audioItem.audioBroadcast'
    track.title = 'Some radio station'
    track.id = '10092020_xxx_xxxx' -- Add station ID from url (regex?)
    track.uri = 'x-sonosapi-stream:%(stationId)s?sid=254&flags=8224&sn=0' % { stationId = stationId }
    return track
  end

  log.debug('Don\'t support this TrackUri (yet) ' .. trackUri)
  return nil
end

return M