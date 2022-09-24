local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local commands = require('commands')
local log = require "log"

local discovery = require('discovery')
local commands = require('commands')
local lifecycles = require('lifecycles')

local driver = Driver("Sonos LAN", {
    player_cache = {},
    discovery = discovery.start,
    lifecycle_handlers = lifecycles,
    supported_capabilities = {
      capabilities.audioMute,
      capabilities.audioVolume,
      capabilities.audioStream,
      capabilities.audioNotification,
      capabilities.switch,
      capabilities.switchLevel,
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
      [capabilities.switch.ID] = {
        [capabilities.switch.commands.on.NAME] = commands.handle_track_command,
        [capabilities.switch.commands.off.NAME] = commands.handle_track_command,
      },
      [capabilities.switchLevel.ID] = {
        [capabilities.switchLevel.commands.setLevel.NAME] = commands.handle_set_track,
      },
      [capabilities.mediaPlayback.ID] = {
        [capabilities.mediaPlayback.commands.play.NAME] = commands.handle_track_command,
        [capabilities.mediaPlayback.commands.pause.NAME] = commands.handle_track_command,
        [capabilities.mediaPlayback.commands.stop.NAME] = commands.handle_track_command,
      },
      [capabilities.mediaPresets.ID] = {
        [capabilities.mediaPresets.commands.playPreset.NAME] = commands.handle_track_command,
      },
      [capabilities.mediaTrackControl.ID] = {
        [capabilities.mediaTrackControl.commands.nextTrack.NAME] = commands.handle_track_nav,
        [capabilities.mediaTrackControl.commands.previousTrack.NAME] = commands.handle_track_nav,
      },
      [capabilities.audioStream.ID] = {
        [capabilities.audioStream.commands.startAudio.NAME] = commands.handle_track_command,
        [capabilities.audioStream.commands.stopAudio.NAME] = commands.handle_track_command,
      },
      [capabilities.refresh.ID] = {
        [capabilities.refresh.commands.refresh.NAME] = commands.handle_refresh,
      }
    }
  })


--------------------
-- Initialize Driver
driver:run()