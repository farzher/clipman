# ClipMan
Clipboard manager for Windows. Alternative to [Ditto](https://github.com/sabrogden/Ditto).

Nowhere near as advanced as Ditto, but this does support db encryption https://github.com/sabrogden/Ditto/issues/171#issuecomment-934690415

# Screenshot
![](https://i.imgur.com/gLrmKk0.png)

# Features
- database encryption
- streamer mode - everytime clipman's opened all information is censored until you click or hit tab
- images compressed using webp to keep the .db file small
  - the original image is saved to the %temp% folder and will be used until it's gone
- start typing to filter to clips containing that text
- right click -> Context - goto the first time a clip was copied to see what else was copied around that same time
- hover over the right half of a clip to get a quick detailed view of it
  - text / files / images - expand to fill the window
  - text that is an imgur link or youtube link - renders as an image

# Roadmap
- use 0 RAM while idle in the background

# Usage
Download the repo then run `release/clipman.exe`

# Build From Source
0. have #the_compiler(beta 0.1.088, built on 10 March 2024)
1. run `dev.bat` or `build_release.bat`

# Understanding The Source Code
- first.jai         - the build script
- src/main.jai      - the main game loop
- src/stuff.jai     - just a mess of stuff
- src/functions.jai - relatively pure dependency free functions
- src/modules/      - old/hacked versions of standard library modules + 3rd party modules + custom modules
