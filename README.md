# FaceLock

A tiny macOS menu bar app that locks your Mac when you walk away.

It watches the webcam for a face. If it sees no face and you haven't touched the keyboard or mouse for a while (30 seconds by default), it locks the screen. When you come back, unlock with Touch ID or your password like always.

Free and open source. No accounts, no network, no tracking. Camera frames are checked on your Mac and thrown away right after.

## How it works

- Checks for a face once per second using Apple's Vision framework.
- Typing or moving the mouse counts as "you're here", so it won't lock you out in bad lighting.
- The camera turns off while the screen is locked and when the Mac sleeps.
- It only checks that *a* face is there, not *whose* face. It's a walk-away lock, not a security system.

## Install

You need macOS 13 or newer and the Xcode Command Line Tools (`xcode-select --install`).

```
git clone https://github.com/flaviob/face-lock.git
cd face-lock
./build.sh
open ~/Applications/FaceLock.app
```

Click Allow when macOS asks for camera access.

## Menu

- **Enabled**: pause it during video calls or whenever you like
- **Lock after**: 10 seconds to 5 minutes
- **Start at login**
- **Lock now**

Icons: an eye means it sees you, an eye with a warning means no face, a crossed-out eye means paused.

## Notes

- Locking uses the same system call as Ctrl+Cmd+Q (a private macOS API). If Apple removes it, the app falls back to sleeping the display.
- If you rebuild, macOS may ask for camera permission again.
- The whole app is one Swift file: `Sources/main.swift`.

## License

MIT
