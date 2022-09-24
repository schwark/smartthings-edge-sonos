local config = {}
-- device info
-- NOTE: In the future this information
-- may be submitted through the Developer
-- Workspace to avoid hardcoded values.
config.SPEAKER_PROFILE='Sonos.Speaker.LAN.v1'
config.DEVICE_TYPE='LAN'
config.MANUFACTURER='Sonos' 
config.PLAYER_UPDATE_SCHEDULE_PERIOD=600
config.PLAYER_UPDATE_MAX_FREQUENCY=600
config.STATE_UPDATE_SCHEDULE_PERIOD=15
config.FILTER_SPEAKERS='Master Bedroom'
--config.URN='urn:schemas-upnp-org:device:ZonePlayer:1'
config.URN='urn:smartspeaker-audio:service:SpeakerGroup:1'
-- SSDP Config
config.MC_ADDRESS='239.255.255.250'
config.MC_PORT=1900
config.MC_TIMEOUT=10
config.SONOS_HTTP_PORT = '1400'
config.MSEARCH=table.concat({
  'M-SEARCH * HTTP/1.1',
  'HOST: 239.255.255.250:1900',
  'MAN: "ssdp:discover"',
  'MX: 4',
  'ST: '..config.URN,
  '',
  ''
}, '\r\n')


return config