# SmartThings Edge Driver for LAN Based Sonos Control

This is a Edge driver for LAN based Sonos Control. This uses the SOAP API as it is the best documented, but I will likely add a Websocket implementation when the LAN based WebSocket implementation is publicly available (is not right now). This does NOT use the Sonos cloud API

## Driver Installation

1. Click on [Driver Invite Link](https://bestow-regional.api.smartthings.com/invite/VD2NLgQwpNj5)
2. Login to your SmartThings Account
3. Follow the flow to Accept Terms
4. Enroll your Hub
5. Install the Driver from the Available Drivers Button


## App Configuration

1. Now go to your SmartThings app and **Add a Device** > **Scan Nearby**.

2. All your speakers should be automatically detected and added. If all are not found, just keep repeating step 1 till all are found.

3. Each of the speakers will also show up as a switch to make it easier to use in Routines.

4. If you go to the Settings of the speaker (top right three dots / Settings) you can add the **names** of the Sonos favorites or Sonos playlists from your Sonos app.

5. There is also a dimmer on each speaker, that you can set to any value (between 0 - 100) - this is used to pick WHICH of the names in the settings you want to play when you turn the switch on. Depending on where the dimmer is, it will pick that name from the settings list to play (e.g., if there are only two names in the list in Settings, anything less than 50% will play the first, and anything over 50% will play the second, and so on) - again this is to enable track control using just dimmers and switches which are robustly supported in Routines, etc. Eventually when media playing is more robustly supported in Routines, this will be a hack that is no longer necessary.

Note: Dimmer value of 0% has a special meaning, which is to not play any of the favorites in the settings, but simply hit play on existing queue
