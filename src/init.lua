local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"

local discovery = require('discovery')
local commands = require('commands')
local lifecycles = require('lifecycles')

local driver = Driver("Sonos LAN", {
    discovery = discovery.start,
    lifecycle_handlers = lifecycles,
    supported_capabilities = {
      capabilities.audioMute,
      capabilities.audioVolume,
      capabilities.audioStream,
      capabilities.audioNotification,
      capabilities.refresh
    },    
    capability_handlers = {
      [capabilities.audioMute.ID] = {
        [capabilities.audioMute.commands.setMute.NAME] = commands.handle_volume_command,
        [capabilities.audioMute.commands.mute.NAME] = commands.handle_volume_command,
        [capabilities.audioMute.commands.unmute.NAME] = commands.handle_volume_command,
      },
      [capabilities.audioVolume.ID] = {
        [capabilities.audioVolume.commands.setVolume.NAME] = commands.handle_volume_command,
        [capabilities.audioVolume.commands.volumeUp.NAME] = commands.handle_volume_command,
        [capabilities.audioVolume.commands.volumeDown.NAME] = commands.handle_volume_command,
      },
      [capabilities.audioStream.ID] = {
        [capabilities.audioStream.commands.startAudio.NAME] = commands.handle_track_command,
        [capabilities.audioStream.commands.stopAudio.NAME] = commands.handle_track_command,
      },
      [capabilities.audioNotification.ID] = {
        [capabilities.audioNotification.commands.playTrack.NAME] = commands.handle_track_command,
        [capabilities.audioNotification.commands.playTrackAndRestore.NAME] = commands.handle_track_command,
        [capabilities.audioNotification.commands.playTrackAndResume.NAME] = commands.handle_track_command,
      },
      [capabilities.refresh.ID] = {
        [capabilities.refresh.commands.refresh.NAME] = commands.handle_refresh,
      }
    }
  })


--------------------
-- Initialize Driver
driver:run()