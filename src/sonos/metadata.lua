local xmlutil = require('xmlutil')
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"
local utils = require("st.utils")
local log = require "log"

local music_services = {
  ['38'] = '7digital',
  ['321'] = '80s80s',
  ['198'] = 'Anghami',
  ['201'] = 'Apple Music',
  ['204'] = 'Apple Music',
  ['275'] = 'ARTRADIO',
  ['306'] = 'Kollekt.fm',
  ['239'] = 'Audible',
  ['219'] = 'Audiobooks.com',
  ['157'] = 'Bandcamp',
  ['307'] = 'Bookmate',
  ['283'] = 'Calm',
  ['144'] = 'Calm Radio',
  ['256'] = 'CBC Radio & Music',
  ['191'] = 'Classical Archives',
  ['315'] = 'Convoy Network',
  ['213'] = 'Custom Channels',
  ['2'] = 'Deezer',
  ['234'] = 'deliver.media',
  ['285'] = 'Epidemic Spaces',
  ['182'] = 'FamilyStream',
  ['217'] = 'FIT Radio Workout Music',
  ['192'] = 'focus@will',
  ['167'] = 'Gaana',
  ['279'] = 'Global Player',
  ['36'] = 'Hearts of Space',
  ['45'] = 'hotelradio.fm',
  ['310'] = 'iBroadcast',
  ['271'] = 'IDAGIO',
  ['300'] = 'JUKE',
  ['305'] = 'Libby by OverDrive',
  ['221'] = 'LivePhish+',
  ['260'] = 'Minidisco',
  ['181'] = 'Mixcloud',
  ['171'] = 'Mood Mix',
  ['33'] = 'Murfie',
  ['262'] = 'My Cloud Home',
  ['268'] = 'myTuner Radio',
  ['203'] = 'Napster',
  ['277'] = 'NRK Radio',
  ['230'] = 'NTS Radio',
  ['222'] = 'nugs.net',
  ['324'] = 'Piraten.FM',
  ['212'] = 'Plex',
  ['233'] = 'Pocket Casts',
  ['265'] = 'PowerApp',
  ['31'] = 'Qobuz',
  ['294'] = 'Radio Javan',
  ['308'] = 'Radio Paradise',
  ['264'] = 'radio.net',
  ['154'] = 'Radionomy',
  ['162'] = 'radioPup',
  ['312'] = 'Radioshop',
  ['223'] = 'RauteMusik.FM',
  ['270'] = 'Relisten',
  ['150'] = 'RUSC',
  ['164'] = 'Saavn',
  ['160'] = 'SoundCloud',
  ['189'] = 'SOUNDMACHINE',
  ['218'] = 'Soundsuit.fm',
  ['295'] = 'Soundtrack Player',
  ['9'] = 'Spotify',
  ['163'] = 'Spreaker',
  ['184'] = 'Stingray Music',
  ['13'] = 'Stitcher',
  ['237'] = 'storePlay',
  ['226'] = 'Storytel',
  ['235'] = 'Sveriges Radio',
  ['211'] = 'The Music Manager',
  ['174'] = 'TIDAL',
  ['287'] = 'toníque',
  ['169'] = 'Tribe of Noise',
  ['254'] = 'TuneIn',
  ['193'] = 'Tunify for Business',
  ['231'] = 'Wolfgang\'s Music',
  ['272'] = 'Worldwide FM',
  ['317'] = 'Yogi Tunes',
  ['284'] = 'YouTube Music',
  ['999'] = 'My Music Library',
  ['303'] = 'Sonos Radio',
}

local M = {}
local st_metatable = getmetatable('')

local function interp(s, tab)
  return (s:gsub('%%%((%a%w*)%)([-0-9%.]*[cdeEfgGiouxXsq])',
    function(k, fmt) return tab[k] and ("%" .. fmt):format(tab[k]) or
          '%(' .. k .. ')' .. fmt
    end))
end
st_metatable.__mod = interp

local function str_matches(s, pattern)
  local t = {}
  for v in string.gmatch(s, pattern) do
    table.insert(t, v)
  end
  return t
end

local function str_split(s, separator)
  local t = {}
  for v in string.gmatch(s, "[^" .. separator .. "]+") do
    table.insert(t, v)
  end
  return t
end

local function str_trim(s)
  s = s:gsub('^%s+', '')
  s = s:gsub('%s+$', '')
  return s
end

local function str_starts_with(s, prefix)
  return s:match('^' .. prefix)
end

local char_to_hex = function(c)
  return string.format("%%%02X", string.byte(c))
end

local function urlencode(url)
  if url == nil then
    return
  end
  url = url:gsub("\n", "\r\n")
  url = url:gsub("([^%w ])", char_to_hex)
  url = url:gsub(" ", "+")
  return url
end

local hex_to_char = function(x)
  return string.char(tonumber(x, 16))
end

local urldecode = function(url)
  if url == nil then
    return
  end
  url = url:gsub("+", " ")
  url = url:gsub("%%(%x%x)", hex_to_char)
  return url
end



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

function M.is_radio(uri)
  return uri:match('x-sonosapi-stream:') or
      uri:match('x-sonosapi-radio:') or
      uri:match('pndrradio:') or
      uri:match('x-sonosapi-hls:') or
      uri:match('hls-radio:') or
      uri:match('m3u8') or
      uri:match('x-sonosprog-http:');
end

function M.duration_in_seconds(str)
  if not str then return nil end
  local hours, minutes, seconds = str:match('(%d+):(%d+):(%d+)')
  return seconds and tonumber(hours) * 60 * 60 + tonumber(minutes) * 60 + tonumber(seconds)
end

function M.duration_in_hms(time)
  if type(time) ~= 'number' then return nil end
  local hours = math.floor((time % 86400)/3600)
  local minutes = math.floor((time % 3600)/60)
  local seconds = math.floor(time % 60)
  return string.format("%02d:%02d:%02d",hours,minutes,seconds)
end

function M.to_int(str)
  return tonumber(str)
end

function M.to_bool(str)
  if '0' == str then return false end
  return true
end

local vars = {
  GroupVolume = 'volume#to_int',
  GroupMute = 'mute',
  LastChange = 'event',
  CurrentPlayMode = 'play_mode',
  TransportState = 'state',
  NumberOfTracks = 'playing.num_tracks#to_int',
  CurrentTrack = 'playing.num#to_int',
  CurrentTrackMetaData = 'playing.metadata',
  CurrentTrackURI = 'playing.uri',
  CurrentTrackDuration = 'playing.duration#duration_in_seconds',
}

local function fix_event_xml(xml)
  return xml:gsub('(val=")([^"]-DIDL%-Lite.-/DIDL%-Lite[^"]-)("/>)', function (x, y, z) return x..xmlutil.xml_encode(xmlutil.xml_decode(y))..z end)
end

local function set_field(result, path, value)
  if not path or not value then return end
  local steps = str_split(path, '%.')
  local where = result
  for i=1,#steps-1 do
      where = where[steps[i]]
  end
  local field, conv = steps[#steps]:match('([^#]+)#?(.*)')
  where[field] = conv and '' ~= conv and M[conv](value) or value
end

function M.parse_event(event, result, host, port)
  --log.debug('before fixing'..event)
  event = fix_event_xml(event)
  --log.debug('after fixing'..event)
  local xmlres = xml_handler:new()
  local xml_parser = xml2lua.parser(xmlres)
  xml_parser:parse(event)
  local items = xmlres and xmlres.root and xmlres.root.Event and xmlres.root.Event.InstanceID or nil
  if items then
      if not result then result = {} end
      if not result.playing then result.playing = {} end
      for key, value in pairs(items) do
          set_field(result, vars[key], value and value._attr and value._attr.val or nil)
      end
  end
  if result and result.playing and result.playing.metadata then
      local track = M.parse_didl(result.playing.metadata, host, port)
      if track and track[1] then
          for key, value in pairs(track[1]) do
              if value and '' ~= value then
                  result.playing[key] = value
              end
          end
      end
  end
  result.event = nil
  log.debug(utils.stringify_table(result))
  return result
end

function M.parse_properties(event, host, port)
  local xmlres = xml_handler:new()
  local xml_parser = xml2lua.parser(xmlres)
  xml_parser:parse(event)

  local properties = xmlres and xmlres.root and xmlres.root['e:propertyset']['e:property'] or nil
  log.info(utils.stringify_table(properties))
  properties = properties and not properties[1] and {properties} or properties
  local result = {}
  for i, property in ipairs(properties) do
      for var, value in pairs(property) do
          if vars[var] then
              set_field(result, vars[var], value)
          else
              log.warn(var.." unassigned value "..value)
          end
      end
  end
  if result.event then result = M.parse_event(result.event, result, host, port) end
  log.debug(utils.stringify_table(result))
  return result
end


local function fix_xml_problems(didl)
  local fixing = didl:match('<DIDL%-Lite xmlns%:dc%=&quot;') or didl:match('<[^>]+&gt;')
  if fixing then
    didl = didl:gsub('(<r:resMD>)(.-)(</r:resMD>)', function(x,y,z) return x..xmlutil.xml_encode(xmlutil.xml_decode(y))..z end)
  --[[
  if didl:match('<DIDL%-Lite xmlns%:dc%=&quot;') then
      log.warn("messed up xml - fixing &quot;")
      didl = didl:gsub('&quot;','"')
      fixed = true
  end
  if didl:match('<[^>]+&gt;') then
      log.warn("messed up xml - fixing tag&gt;")
      didl = didl:gsub('<([^>]+)&gt;','<%1>')
      fixed = true
  end
  --]]
    log.info('xml is messed up again... fixing...')
    log.debug("fixed xml is...: "..didl) 
  end
  return didl
end

function M.parse_didl(didl, host, port)
  if (type(didl) == 'table' or not didl or not didl:match('^<DIDL')) then return nil end
  local result = nil

  didl = fix_xml_problems(didl)
  local result_handler = xml_handler:new()
  local result_parser = xml2lua.parser(result_handler)
  result_parser:parse(didl)
  if not result_handler.root or not result_handler.root['DIDL-Lite'] then return nil end

  local parsed_items = result_handler.root['DIDL-Lite'].item or result_handler.root['DIDL-Lite'].container
  if not parsed_items then return nil end
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
      local streamContent = str_split(didl_item['r:streamContent'], '-')
      if (#streamContent == 2) then
        track.artist = str_trim(streamContent[1])
        track.title = str_trim(streamContent[2])
      else
        track.artist = streamContent[1].trim()
        if (didl_item['r:radioShowMd'] and type(didl_item['r:radioShowMd']) == 'string') then
          local radioShowMd = str_split(didl_item['r:radioShowMd'],',')
          track.title = str_trim(radioShowMd[1])
        end
      end
    end
    if (didl_item['upnp:albumArtURI']) then
      local uri = type(didl_item['upnp:albumArtURI']) == "table" and didl_item['upnp:albumArtURI'][1] or
          didl_item['upnp:albumArtURI']
      -- Github user @hklages discovered that the album uri sometimes doesn't work because of encodings
      -- See https://github.com/svrooij/node-sonos-ts/issues/93 if you found and album art uri that doesn't work
      local art = uri:gsub('&amp;', '&'); -- :gsub(/%25/g, '%'):gsub(/%3a/gi, ':')
      track.art = art:match('^http') and art or
          'http://%(host)s:%(port)s%(art)s' % { host = host, port = port, art = art }
    end

    if (didl_item.res) then
      track.duration = M.duration_in_seconds(didl_item.res._attr and didl_item.res._attr.duration or nil)
      track.uri = didl_item.res[1]
      track.service = M.guess_service(track)
      track.type = M.guess_type(track)
      track.protocol_info = didl_item.res._attr and didl_item.res._attr.protocolInfo or nil
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
      '<item id="%(itemId)s" restricted="true"%(parentattr)s>' % { itemId = itemId, parentattr = parent_attr }
  if (includeResource) then metadata = metadata ..
        '<res protocolInfo="%(proto)s" duration="%(duration)s">%(uri)s</res>' %
        { proto = protocolInfo, duration = (track.duration or ''), uri = xmlutil.xml_encode(track.uri) }
  end
  if (track.art) then metadata = metadata .. '<upnp:albumArtURI>%(art)s</upnp:albumArtURI>' % { art = track.art } end
  if (track.title) then metadata = metadata .. '<dc:title>%(title)s</dc:title>' % { title = track.title } end
  if (track.artist) then metadata = metadata .. '<dc:creator>%(artist)s</dc:creator>' % { artist = track.artist } end
  if (track.album) then metadata = metadata .. '<upnp:album>%(album)s</upnp:album>' % { album = track.album } end
  if (track.upnp_class) then metadata = metadata ..
        '<upnp:class>%(upnpclass)s</upnp:class>' % { upnpclass = track.upnp_class }
  end
  if track.metadata then
    metadata = metadata .. '<r:resMD>'..xmlutil.xml_encode(track.metadata)..'</r:resMD>'
  end
  metadata = metadata ..
      '<desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">%(localCdudn)s</desc>' %
      { localCdudn = localCdudn }
  metadata = metadata .. '</item></DIDL-Lite>'
  return metadata
end

function M.guess_metadata_and_track(trackUri, spotifyRegion)
  if not spotifyRegion then spotifyRegion = '3079' end
  local metadata = M.guess_track(trackUri, spotifyRegion)

  return {
    uri = (not metadata or not metadata.uri) and trackUri or xmlutil.xml_decode(metadata.uri),
    metadata = metadata or ''
  }
end

local function spotify_metadata(trackUri, kind, region)
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
    track.art = '/getaa?s=1&u='..urlencode(track.uri)
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

local function deezer_metadata(kind, -- 'album' | 'artistTopTracks' | 'playlist' | 'track' | unknown
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
    track.art = '/getaa?s=1&u='..urlencode(track.uri)
    return track
  end
  return nil
end

local function apple_metadata(kind,
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
  if kind:match('playlist') or kind:match('station') then
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
    track.art = '/getaa?s=1&u='..urlencode(track.uri)
    return track
  end
  log.debug('Don\'t support this Apple Music kind ' .. kind)
  return nil
end

function M.guess_service(track)
  local service_id = track.uri and track.uri:match('sid=(%d+)') or nil
  service_id = service_id or track.art and (track.art:match('sid%%3d(%d+)') or track.art:match('sid=(%d+)'))
  service_id = service_id or (track.uri and track.uri:match('x%-file%-cifs') or (track.art and track.art:match('x%-file%-cifs'))) and '999'
  if not service_id and track.uri then
    for id, service in pairs(music_services) do
      local name = service:gsub(' Music',''):gsub('[\'%s%-%&]+',''):lower()
      if track.uri:match(name) then
        service_id = id
        break
      end
    end
  end
  return service_id and music_services[service_id] or nil
end

function M.guess_type(track)
  local types = {
    ['object.item.audioItem.musicTrack'] = 'Track',
    ['object.container.album.musicAlbum'] = 'Album',
    ['object.container.playlistContainer'] = 'Playlist',
    ['object.item.audioItem.audioBroadcast'] = 'Radio',
    ['object.container.albumList'] = 'Playlist'
  }
  return track.upnp_class and types[track.upnp_class:gsub('%.#.*','')] or (track.uri and track.uri:match('radio') and 'Radio') or nil
end

function M.guess_track(trackUri, spotifyRegion)
  if not spotifyRegion then spotifyRegion = '3079' end -- US: 3079, EU: 2311
  log.debug('Guessing metadata for ' .. trackUri)
  local title = trackUri:gsub('%.%w+$', ''):match('.*/(.*)$') or ''
  local track = {
  }
  track.service = M.guess_service({uri = trackUri})
  if (str_starts_with(trackUri, 'x-file-cifs')) then
    track.id = trackUri:gsub('x-file-cifs', 'S'):gsub('%s', '%20')
    track.title = title:gsub('%20', ' ')
    track.parentid = 'A:TRACKS'
    track.upnp_class = get_upnp_class(track.parentid)
    track.uri = trackUri
    track.cdudn = 'RINCON_AssociatedZPUDN'
    return track
  end
  if (str_starts_with(trackUri, 'file:///jffs/settings/savedqueues.rsq#') or str_starts_with(trackUri, 'sonos:playlist:')) then
    local queueId = trackUri.match("%d+")
    if (queueId) then
      track.uri = 'file:///jffs/settings/savedqueues.rsq#%(queueId)s' % { queueId = queueId }
      track.upnp_class = 'object.container.playlistContainer'
      track.id = 'SQ:%(queueId[0])s' % { queueId = queueId }
      track.cdudn = 'RINCON_AssociatedZPUDN'
      return track
    end
  end
  if (str_starts_with(trackUri,'x-rincon-playlist')) then
    local parentID = trackUri:match('.*#(.*)%/.*')
    assert(parentID)
    track.id = '%(parentID)s/%(title)s' % { parentID = parentID, title = title:gsub("%s", '%20') }
    track.title = title:gsub('%20', ' ')
    track.upnp_class = get_upnp_class(parentID)
    track.parentid = parentID
    track.cdudn = 'RINCON_AssociatedZPUDN'
    return track
  end

  if (str_starts_with(trackUri,'x-sonosapi-stream:')) then
    track.upnp_class = 'object.item.audioItem.audioBroadcast'
    track.title = 'Some radio station'
    track.id = '10092020_xxx_xxxx' -- Add station ID from url (regex?)
    return track
  end

  if (str_starts_with(trackUri,'x-rincon-cpcontainer:1006206ccatalog')) then -- Amazon prime container
    track.uri = trackUri
    track.id = trackUri:gsub('x-rincon-cpcontainer:', '')
    track.upnp_class = 'object.container.playlistContainer'
    return track
  end

  if (str_starts_with(trackUri,'x-rincon-cpcontainer:100d206cuser-fav')) then -- Sound Cloud likes
    track.uri = trackUri
    track.id = trackUri:gsub('x-rincon-cpcontainer:', '')
    track.upnp_class = 'object.container.albumList'
    track.cdudn = 'SA_RINCON40967_X_#Svc40967-0-Token'
    return track
  end

  if (str_starts_with(trackUri,'x-rincon-cpcontainer:1006206cplaylist')) then -- Sound Cloud playlists
    track.uri = trackUri
    track.id = trackUri:gsub('x-rincon-cpcontainer:', '')
    track.upnp_class = 'object.container.playlistContainer'
    track.cdudn = 'SA_RINCON40967_X_#Svc40967-0-Token'
    return track
  end

  if (str_starts_with(trackUri,'x-rincon-cpcontainer:1004006calbum-')) then -- Deezer Album
    local numbers = trackUri:match("%d+")
    if (numbers and numbers:len() >= 2) then
      return deezer_metadata('album', numbers)
    end
  end

  local kind, id

  kind, id = trackUri:match('x-rincon-cpcontainer:1004206c([^:]+):([%.%w]+)')
  if (id) then -- Apple Music Album
    return apple_metadata(kind, id)
  end

  kind, id = trackUri:match('x-rincon-cpcontainer:1006206c([^:]+):([%.%w]+)')
  if (id) then -- Apple Music Playlist
    return apple_metadata(kind, id)
  end

  kind, id = trackUri:match('x-sonos-http:([^:]+):([%.%w]+)%.mp4%?.*sid=204')
  if (id and 'song' == kind or 'librarytrack' == kind) then -- Apple Music Track
    return apple_metadata(kind, id)
  end

  if (str_starts_with(trackUri,'x-rincon-cpcontainer:10fe206ctracks-artist-')) then -- Deezer Artists Top Tracks
    local numbers = str_matches(trackUri, '%d+')
    if (numbers and #numbers >= 3) then
      return deezer_metadata('artistTopTracks', numbers[3])
    end
  end

  if (str_starts_with(trackUri,'x-rincon-cpcontainer:1006006cplaylist_spotify%3aplaylist-')) then -- Deezer Playlist
    local numbers = str_matches(trackUri, '%d+')
    if (numbers and #numbers >= 3) then
      return deezer_metadata('playlist', numbers[3])
    end
  end

  if (str_starts_with(trackUri,'x-sonos-http:tr%3a') and trackUri:match('sid=2')) then -- Deezer Track
    local numbers = trackUri:match('%d+')
    if (numbers) then
      return deezer_metadata('track', numbers)
    end
  end

  local parts = str_split(trackUri, ':')
  if ((#parts == 3 or #parts == 5) and parts[1] == 'spotify') then
    return spotify_metadata(trackUri, parts[2], spotifyRegion)
  end

  if (#parts == 3 and parts[1] == 'deezer') then
    return deezer_metadata(parts[2], parts[3])
  end

  if (#parts == 3 and parts[1] == 'apple') then
    return apple_metadata(parts[2], parts[3])
  end

  if(#parts == 3 and (parts[1] == 'hls-radio' or parts[3]:match('m3u8'))) then
    track.upnp_class = 'object.item.audioItem.audioBroadcast'
    track.title = parts[3]:match('([%w%-]+)%.org') or parts[3]:match('([%w%-]+)%.com') or 'Some radio station'
    track.id = '10092020_'..(track.title or 'radio') -- Add station ID from url (regex?)
    track.title = track.title:match('[Rr]adio') and track.title or track.title:gsub("^%l", string.upper)..' Radio'
    track.uri = trackUri:match('^hls-radio:') and trackUri or 'hls-radio:'..trackUri
    return track
  end

  if (#parts == 2 and parts[1] == 'radio' and str_starts_with(parts[2],'s')) then
    local stationId = parts[2]
    track.upnp_class = 'object.item.audioItem.audioBroadcast'
    track.title = 'TuneIn Radio Station'
    track.id = '10092020_'..stationId -- Add station ID from url (regex?)
    track.uri = 'x-sonosapi-stream:%(stationId)s?sid=254&flags=8224&sn=0' % { stationId = stationId }
    return track
  end

  log.debug('Don\'t support this TrackUri (yet) ' .. trackUri)
  return nil
end

function M.sonos_track_from_service_uri(uri)
  if uri:match('%.m3u8$') and not uri:match('^hls-radio') then
    return 'hls-radio:'..uri
  end
  local spotify_type, spotify_track_id = uri:match('spotify%.com/([^/]+)/([^/]+)')
  if 'track' == spotify_type and spotify_track_id then
    return 'x-sonos-spotify:spotify:'..spotify_type..':'..spotify_track_id..'?sid=9&flags=8224&sn=3'
  end
  if 'album' == spotify_type and spotify_track_id then
    return 'x-sonos-spotify:spotify:'..spotify_type..':'..spotify_track_id..'?sid=9&flags=8224&sn=3'
  end
  if 'show' == spotify_type and spotify_track_id then
    return 'x-sonos-spotify:spotify:'..spotify_type..':'..spotify_track_id..'?sid=9&flags=8224&sn=3'
  end
  if 'station' == spotify_type and spotify_track_id then
    return 'x-sonos-spotify:spotify:'..spotify_type..':'..spotify_track_id..'?sid=9&flags=8224&sn=3'
  end
  local apple_country, apple_type, apple_title, apple_id = uri:match('apple%.com/([^/]+)/([^/]+)/([^/]+)/([^/+)')

  return uri
end

return M
