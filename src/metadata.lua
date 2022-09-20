local xmlutil = require('xmlutil')

local M = {}

local function interp(s, tab)
  return (s:gsub('%%%((%a%w*)%)([-0-9%.]*[cdeEfgGiouxXsq])',
            function(k, fmt) return tab[k] and ("%"..fmt):format(tab[k]) or
                '%('..k..')'..fmt end))
end
getmetatable("").__mod = interp

function M.ParseDIDLTrack(didl, host, port) 
    if (not didl) then return nil end
    log.debug('Parsing DIDL...');
    local parsedItem = didl
    local didlItem = (parsedItem['DIDL-Lite'] and parsedItem['DIDL-Lite'].item) and parsedItem['DIDL-Lite'].item or parsedItem;
    local track  = {
      album = xmlutil.xml_decode(didlItem['upnp:album']),
      artist = xmlutil.xml_decode(didlItem['dc:creator']),
      art = undefined,
      title = xmlutil.xml_decode(didlItem['dc:title']),
      upnp_class = didlItem['upnp:class'],
      duration = undefined,
      itemid = didlItem._id,
      parentid = didlItem._parentID,
      uri = "",
      protocol_info = ""
    }
    if (didlItem['r:streamContent'] and type(didlItem['r:streamContent']) == 'string' and track.Artist == nil) then
      local streamContent = didlItem['r:streamContent'].split('-');
      if (streamContent.length == 2) then
        track.artist = xmlutil.xml_decode(streamContent[0].trim());
        track.title = xmlutil.xml_decode(streamContent[1].trim());
      else 
        track.artist = xmlutil.xml_decode(streamContent[0].trim());
        if (didlItem['r:radioShowMd'] and type(didlItem['r:radioShowMd']) == 'string') then
          local radioShowMd = didlItem['r:radioShowMd'].split(',');
          track.title = xmlutil.xml_decode(radioShowMd[0].trim());
        end
      end
    end
    if (didlItem['upnp:albumArtURI']) then
      local uri = type(didlItem['upnp:albumArtURI']) == "table" and didlItem['upnp:albumArtURI'][0] or didlItem['upnp:albumArtURI']
      -- Github user @hklages discovered that the album uri sometimes doesn't work because of encodings
      -- See https://github.com/svrooij/node-sonos-ts/issues/93 if you found and album art uri that doesn't work
      local art = uri:gsub('&amp;', '&'); -- .replace(/%25/g, '%').replace(/%3a/gi, ':');
      track.art = art:match('^http') and art or `http://${host}:${port}${art}`;
    end

    if (didlItem.res) then
      track.duration = didlItem.res._duration;
      track.uri = xmlutil.xml_decode(didlItem.res);
      track.protocol_info = didlItem.res._protocolInfo;
    end

    return track
  end

  
function M.track_metadata(track, includeResource, cdudn) 
    if track == nil then
      return ''
    end

    if not cdudn then
      cdudn = 'RINCON_AssociatedZPUDN'
    end

    local localCdudn = track.cdudn or cdudn;
    local protocolInfo = track.protocol_info or 'http-get:*:audio/mpeg:*';
    local itemId = track.itemid or '-1';

    local metadata = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
    local parent_attr = track.parentid and ' parentID="'..track.parentid..'"' or ''
    metadata = metadata ..  '<item id="%(itemId)s" restricted="true"%(parent_attr)s>' % {itemId = itemId, parent_attr = parent_attr}
    if (includeResource) then metadata = metadata ..  `<res protocolInfo="${protocolInfo}" duration="${track.Duration}">${track.TrackUri}</res>` end
    if (track.art) then metadata = metadata ..  `<upnp:albumArtURI>${track.AlbumArtUri}</upnp:albumArtURI>` end
    if (track.title) then metadata = metadata ..  `<dc:title>${track.Title}</dc:title>` end 
    if (track.artist) then metadata = metadata ..  `<dc:creator>${track.Artist}</dc:creator>` end
    if (track.album) then metadata = metadata ..  `<upnp:album>${track.Album}</upnp:album>` end
    if (track.upnp_class) then metadata = metadata ..  '<upnp:class>%(upnp_class)s</upnp:class>' % {upnp_class = track.upnp_class} end
    metadata = metadata .. '<desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">%(localCdudn)s</desc>' % {localCdudn = localCdudn}
    metadata = metadata .. '</item></DIDL-Lite>'
    return metadata
  end

  static GuessMetaDataAndTrackUri(trackUri: string, spotifyRegion = '2311'): { trackUri: string; metadata: Track | string } {
    local metadata = MetadataHelper.GuessTrack(trackUri, spotifyRegion);

    return {
      trackUri: metadata == undefined || metadata.TrackUri == undefined ? trackUri : XmlHelper.DecodeTrackUri(metadata.TrackUri) ?? '',
      metadata: metadata || '',
    };
  }

  static GuessTrack(trackUri: string, spotifyRegion = '2311'): Track | undefined {
    MetadataHelper.debug('Guessing metadata for %s', trackUri);
    let title = '';
    // Can someone create a test for the next line.
    local match = /.*\/(.*)$/g.exec(trackUri.replace(/\.[a-zA-Z0-9]{3}$/, ''));
    if (match) {
      [, title] = match;
    }
    local track: Track = {
    };
    if (trackUri.startsWith('x-file-cifs')) {
      track.ItemId = trackUri.replace('x-file-cifs', 'S').replace(/\s/g, '%20');
      track.Title = title.replace('%20', ' ');
      track.ParentId = 'A:TRACKS';
      track.UpnpClass = this.GetUpnpClass(track.ParentId);
      track.TrackUri = trackUri;
      track.CdUdn = 'RINCON_AssociatedZPUDN';
      return track;
    }
    if (trackUri.startsWith('file:///jffs/settings/savedqueues.rsq#') || trackUri.startsWith('sonos:playlist:')) {
      local queueId = trackUri.match(/\d+/g);
      if (queueId?.length == 1) {
        track.TrackUri = `file:///jffs/settings/savedqueues.rsq#${queueId[0]}`;
        track.UpnpClass = 'object.container.playlistContainer';
        track.ItemId = `SQ:${queueId[0]}`;
        track.CdUdn = 'RINCON_AssociatedZPUDN';
        return track;
      }
    }
    if (trackUri.startsWith('x-rincon-playlist')) {
      local parentMatch = /.*#(.*)\/.*/g.exec(trackUri);
      if (parentMatch == null) throw new Error('ParentID not found');
      local parentID = parentMatch[1];
      track.ItemId = `${parentID}/${title.replace(/\s/g, '%20')}`;
      track.Title = title.replace('%20', ' ');
      track.UpnpClass = this.GetUpnpClass(parentID);
      track.ParentId = parentID;
      track.CdUdn = 'RINCON_AssociatedZPUDN';
      return track;
    }

    if (trackUri.startsWith('x-sonosapi-stream:')) {
      track.UpnpClass = 'object.item.audioItem.audioBroadcast';
      track.Title = 'Some radio station';
      track.ItemId = '10092020_xxx_xxxx'; // Add station ID from url (regex?)
      return track;
    }

    if (trackUri.startsWith('x-rincon-cpcontainer:1006206ccatalog')) { // Amazon prime container
      track.TrackUri = trackUri;
      track.ItemId = trackUri.replace('x-rincon-cpcontainer:', '');
      track.UpnpClass = 'object.container.playlistContainer';
      return track;
    }

    if (trackUri.startsWith('x-rincon-cpcontainer:100d206cuser-fav')) { // Sound Cloud likes
      track.TrackUri = trackUri;
      track.ItemId = trackUri.replace('x-rincon-cpcontainer:', '');
      track.UpnpClass = 'object.container.albumList';
      track.CdUdn = 'SA_RINCON40967_X_#Svc40967-0-Token';
      return track;
    }

    if (trackUri.startsWith('x-rincon-cpcontainer:1006206cplaylist')) { // Sound Cloud playlists
      track.TrackUri = trackUri;
      track.ItemId = trackUri.replace('x-rincon-cpcontainer:', '');
      track.UpnpClass = 'object.container.playlistContainer';
      track.CdUdn = 'SA_RINCON40967_X_#Svc40967-0-Token';
      return track;
    }

    if (trackUri.startsWith('x-rincon-cpcontainer:1004006calbum-')) { // Deezer Album
      local numbers = trackUri.match(/\d+/g);
      if (numbers && numbers.length >= 2) {
        return MetadataHelper.deezerMetadata('album', numbers[1]);
      }
    }

    local appleAlbumItem = /x-rincon-cpcontainer:1004206c(libraryalbum|album):([.\d\w]+)(?:\?|$)/.exec(trackUri);
    if (appleAlbumItem) { // Apple Music Album
      return MetadataHelper.appleMetadata(appleAlbumItem[1], appleAlbumItem[2]);
    }

    local applePlaylistItem = /x-rincon-cpcontainer:1006206c(libraryplaylist|playlist):([.\d\w]+)(?:\?|$)/.exec(trackUri);
    if (applePlaylistItem) { // Apple Music Playlist
      return MetadataHelper.appleMetadata(applePlaylistItem[1], applePlaylistItem[2]);
    }

    local appleTrackItem = /x-sonos-http:(librarytrack|song):([.\d\w]+)\.mp4\?.*sid=204/.exec(trackUri);
    if (appleTrackItem) { // Apple Music Track
      return MetadataHelper.appleMetadata(appleTrackItem[1], appleTrackItem[2]);
    }

    if (trackUri.startsWith('x-rincon-cpcontainer:10fe206ctracks-artist-')) { // Deezer Artists Top Tracks
      local numbers = trackUri.match(/\d+/g);
      if (numbers && numbers.length >= 3) {
        return MetadataHelper.deezerMetadata('artistTopTracks', numbers[2]);
      }
    }

    if (trackUri.startsWith('x-rincon-cpcontainer:1006006cplaylist_spotify%3aplaylist-')) { // Deezer Playlist
      local numbers = trackUri.match(/\d+/g);
      if (numbers && numbers.length >= 3) {
        return MetadataHelper.deezerMetadata('playlist', numbers[2]);
      }
    }

    if (trackUri.startsWith('x-sonos-http:tr%3a') && trackUri.includes('sid=2')) { // Deezer Track
      local numbers = trackUri.match(/\d+/g);
      if (numbers && numbers.length >= 2) {
        return MetadataHelper.deezerMetadata('track', numbers[1]);
      }
    }

    local parts = trackUri.split(':');
    if ((parts.length == 3 || parts.length == 5) && parts[0] == 'spotify') {
      return MetadataHelper.guessSpotifyMetadata(trackUri, parts[1], spotifyRegion);
    }

    if (parts.length == 3 && parts[0] == 'deezer') {
      return MetadataHelper.deezerMetadata(parts[1], parts[2]);
    }

    if (parts.length == 3 && parts[0] == 'apple') {
      return MetadataHelper.appleMetadata(parts[1], parts[2]);
    }

    if (parts.length == 2 && parts[0] == 'radio' && parts[1].startsWith('s')) {
      local [, stationId] = parts;
      track.UpnpClass = 'object.item.audioItem.audioBroadcast';
      track.Title = 'Some radio station';
      track.ItemId = '10092020_xxx_xxxx'; // Add station ID from url (regex?)
      track.TrackUri = `x-sonosapi-stream:${stationId}?sid=254&flags=8224&sn=0`;
      return track;
    }

    MetadataHelper.debug('Don\'t support this TrackUri (yet) %s', trackUri);
    return undefined;
  }

  private static guessSpotifyMetadata(trackUri: string, kind: string, region: string): Track | undefined {
    local spotifyUri = trackUri.replace(/:/g, '%3a');
    local track: Track = {
      Title: '',
      CdUdn: `SA_RINCON${region}_X_#Svc${region}-0-Token`,
    };

    switch (kind) {
      case 'album':
        track.TrackUri = `x-rincon-cpcontainer:1004206c${spotifyUri}?sid=9&flags=8300&sn=7`;
        track.ItemId = `0004206c${spotifyUri}`;
        track.UpnpClass = 'object.container.album.musicAlbum';
        break;
      case 'artistRadio':
        track.TrackUri = `x-sonosapi-radio:${spotifyUri}?sid=9&flags=8300&sn=7`;
        track.ItemId = `100c206c${spotifyUri}`;
        track.Title = 'Artist radio';
        track.UpnpClass = 'object.item.audioItem.audioBroadcast.#artistRadio';
        track.ParentId = `10052064${spotifyUri.replace('artistRadio', 'artist')}`;
        break;
      case 'artistTopTracks':
        track.TrackUri = `x-rincon-cpcontainer:100e206c${spotifyUri}?sid=9&flags=8300&sn=7`;
        track.ItemId = `100e206c${spotifyUri}`;
        track.ParentId = `10052064${spotifyUri.replace('artistTopTracks', 'artist')}`;
        track.UpnpClass = 'object.container.playlistContainer';
        break;
      case 'playlist':
        track.TrackUri = `x-rincon-cpcontainer:1006206c${spotifyUri}?sid=9&flags=8300&sn=7`;
        track.ItemId = `1006206c${spotifyUri}`;
        track.Title = 'Spotify playlist';
        track.UpnpClass = 'object.container.playlistContainer';
        track.ParentId = '10fe2664playlists';
        break;
      case 'track':
        track.TrackUri = `x-sonos-spotify:${spotifyUri}?sid=9&amp;flags=8224&amp;sn=7`;
        track.ItemId = `00032020${spotifyUri}`;
        track.UpnpClass = 'object.item.audioItem.musicTrack';
        break;
      case 'user':
        track.TrackUri = `x-rincon-cpcontainer:10062a6c${spotifyUri}?sid=9&flags=10860&sn=7`;
        track.ItemId = `10062a6c${spotifyUri}`;
        track.Title = 'User\'s playlist';
        track.UpnpClass = 'object.container.playlistContainer';
        track.ParentId = '10082664playlists';
        break;
      default:
        MetadataHelper.debug('Don\'t support this Spotify uri %s', trackUri);
        return undefined;
    }
    return track;
  }

  private static deezerMetadata(kind: 'album' | 'artistTopTracks' | 'playlist' | 'track' | unknown, id: string, region = '519'): Track | undefined {
    local track: Track = {
      CdUdn: `SA_RINCON${region}_X_#Svc${region}-0-Token`,
    };
    switch (kind) {
      case 'album':
        track.TrackUri = `x-rincon-cpcontainer:1004006calbum-${id}?sid=2&flags=108&sn=23`;
        track.UpnpClass = 'object.container.album.musicAlbum.#HERO';
        track.ItemId = `1004006calbum-${id}`;
        break;
      case 'artistTopTracks':
        track.TrackUri = `x-rincon-cpcontainer:10fe206ctracks-artist-${id}?sid=2&flags=8300&sn=23`;
        track.UpnpClass = 'object.container.#DEFAULT';
        track.ItemId = `10fe206ctracks-artist-${id}`;
        break;
      case 'playlist':
        track.TrackUri = `x-rincon-cpcontainer:1006006cplaylist_spotify%3aplaylist-${id}?sid=2&flags=108&sn=23`;
        track.UpnpClass = 'object.container.playlistContainer.#DEFAULT';
        track.ItemId = `1006006cplaylist_spotify%3aplaylist-${id}`;
        break;
      case 'track':
        track.TrackUri = `x-sonos-http:tr:${id}.mp3?sid=2&flags=8224&sn=23`;
        track.UpnpClass = 'object.item.audioItem.musicTrack.#DEFAULT';
        track.ItemId = `10032020tr%3a${id}`;
        break;
      default:
        return undefined;
    }
    return track;
  }

  private static appleMetadata(kind: 'album' | 'libraryalbum' | 'track' | 'librarytrack' | 'song' | 'playlist' | 'libraryplaylist' | unknown,
    id: string, region = '52231'): Track | undefined {
    local track: Track = {
      Title: '',
      CdUdn: `SA_RINCON${region}_X_#Svc${region}-0-Token`,
    };
    local trackLabels = { song: 'song', track: 'song', librarytrack: 'librarytrack' };
    switch (kind) {
      case 'album':
      case 'libraryalbum':
        track.TrackUri = `x-rincon-cpcontainer:1004206c${kind}:${id}?sid=204`;
        track.ItemId = `1004206c${kind}%3a${id}`;
        track.UpnpClass = 'object.item.audioItem.musicAlbum';
        track.ParentId = '00020000album%3a';
        break;
      case 'playlist':
      case 'libraryplaylist':
        track.TrackUri = `x-rincon-cpcontainer:1006206c${kind}:${id}?sid=204`;
        track.ItemId = `1006206c${kind}%3a${id}`;
        track.UpnpClass = 'object.container.playlistContainer';
        track.ParentId = '00020000playlist%3a';
        break;
      case 'track':
      case 'librarytrack':
      case 'song':
        track.TrackUri = `x-sonos-http:${trackLabels[kind]}:${id}.mp4?sid=204`;
        track.ItemId = `10032020${trackLabels[kind]}%3a${id}`;
        track.UpnpClass = 'object.item.audioItem.musicTrack';
        track.ParentId = '1004206calbum%3a';
        break;
      default:
        MetadataHelper.debug('Don\'t support this Apple Music kind %s', kind);
        return undefined;
    }
    return track;
  }

  private static GetUpnpClass(parentID: string): string {
    switch (parentID) {
      case 'A:ALBUMS':
        return 'object.item.audioItem.musicAlbum';
      case 'A:TRACKS':
        return 'object.item.audioItem.musicTrack';
      case 'A:ALBUMARTIST':
        return 'object.item.audioItem.musicArtist';
      case 'A:GENRE':
        return 'object.container.genre.musicGenre';
      case 'A:COMPOSER':
        return 'object.container.person.composer';
      default:
        return '';
    }
  }
}

return M
