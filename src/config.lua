local config = {}
-- device info
-- NOTE: In the future this information
-- may be submitted through the Developer
-- Workspace to avoid hardcoded values.
config.SPEAKER_PROFILE='Sonos.Speaker.LAN.v1'
config.DEVICE_TYPE='LAN'
config.SCHEDULE_PERIOD=15
config.MANUFACTURER='Sonos' 
config.UPDATE_MAX_FREQUENCY = 10

--config.URN='urn:schemas-upnp-org:device:ZonePlayer:1'
config.URN='urn:smartspeaker-audio:service:SpeakerGroup:1'
-- SSDP Config
config.MC_ADDRESS='239.255.255.250'
config.MC_PORT=1900
config.MC_TIMEOUT=10
config.MSEARCH=table.concat({
  'M-SEARCH * HTTP/1.1',
  'HOST: 239.255.255.250:1900',
  'MAN: "ssdp:discover"',
  'MX: 4',
  'ST: '..config.URN
}, '\r\n')


return config