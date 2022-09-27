local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"

local discovery = require('discovery')
local commands = require('commands')
local lifecycles = require('lifecycles')
local config = require('config')

local function setup_timer(driver)
  local success = false
  if not driver.player_cache.timer then
    local timer = driver:call_on_schedule(
      config.PLAYER_UPDATE_SCHEDULE_PERIOD,
      function ()
        return commands.handle_player_refresh(driver)
      end,
    'Player Refresh schedule')
    if (driver.player_cache.timer) then -- someone else already set it up..
      driver:cancel_timer(timer)
    else
      driver.player_cache.timer = timer
      success = true
    end
  end
  return success
end

local function cancel_timer(driver, timer)
  if driver.player_cache.timer then
    driver:cancel_timer(timer or driver.player_cache.timer)
    driver.player_cache.timer = timer and driver.player_cache.timer or nil
  end
end

local function driver_lifecycle(driver, event)
  if('shutdown' == event) then
    driver:cancel_timer()
  end
end

local driver = Driver("Sonos LAN", {
    player_cache = {},
    setup_timer = setup_timer,
    cancel_timer = cancel_timer,
    driver_lifecycle = driver_lifecycle,
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
        [capabilities.audioMute.commands.setMute.NAME] = commands.handle_mute_command,
        [capabilities.audioMute.commands.mute.NAME] = commands.handle_mute_command,
        [capabilities.audioMute.commands.unmute.NAME] = commands.handle_mute_command,
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
      }, --[[
      [capabilities.switchLevel.ID] = {
        [capabilities.switchLevel.commands.setLevel.NAME] = commands.handle_set_track,
      },]]
      [capabilities.mediaPlayback.ID] = {
        [capabilities.mediaPlayback.commands.play.NAME] = commands.handle_track_command,
        [capabilities.mediaPlayback.commands.pause.NAME] = commands.handle_track_command,
        [capabilities.mediaPlayback.commands.stop.NAME] = commands.handle_track_command,
      },
      [capabilities.mediaPresets.ID] = {
        [capabilities.mediaPresets.commands.playPreset.NAME] = commands.handle_track_command,
      },
      [capabilities.mediaPlaybackRepeat.ID] = {
        [capabilities.mediaPlaybackRepeat.commands.setPlaybackRepeatMode.NAME] = commands.handle_play_mode,
      },
      [capabilities.mediaPlaybackShuffle.ID] = {
        [capabilities.mediaPlaybackShuffle.commands.setPlaybackShuffle.NAME] = commands.handle_play_mode,
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