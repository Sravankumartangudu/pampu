# Changelog

## 1.2.2 — 2026-10-30

🔗 The Mac remembers your iPhone.

- **Paired iPhones are kept when Pampu restarts.** The Mac saved them but couldn't read them back,
  so after a restart, a log-out or an update it forgot every iPhone and asked you to pair again.

## 1.2.1 — 2026-10-30

📶 The iPhone's signal bars work.

- **The signal bars now fill up as you bring the iPhone close.** iOS often hears the Mac's Bluetooth
  signal without its name, so the iPhone couldn't tell it was the Mac it was connected to, and the
  bars stayed empty. Bringing it close to drop by itself didn't work either. The iPhone now uses the
  strongest unnamed Pampu signal when it can't hear the Mac by name.
- The Mac's status line says when Bluetooth is still starting up.
- With one Mac nearby, the iPhone says *Found — connecting…* rather than asking you to pick one.

## 1.2.0 — 2026-10-30

🎆 15 drop effects, plus Random. The iPhone throws the stack in style and the Mac plays the
matching landing.

- **Pick one in Settings › Drop effect on the iPhone**, with a live preview that plays as you
  choose. **🎲 Random** (the new default) picks a different one for every drop.
- **The effects:** ✨ Classic, 🚀 Rocket, ✈️ Paper Plane, 🕳️ Black Hole, 🎉 Confetti,
  🎆 Fireworks, 🌌 Hyperspace, ☄️ Comet, 🫧 Bubbles, 🪄 Magic Dust, ⚡ Lightning, 🌀 Portal,
  💥 Shatter, 💖 Hearts and 🌪️ Tornado. Each has its own throw, particles and haptics on the iPhone,
  and its own landing on the Mac: the rocket lands on its flames, the comet streaks in, the
  cards drop out of a portal, the lightning strikes them into place…
- **🪂 › Landing Effect on the Mac:** *Same as the iPhone* (default), Random, or always one effect.
  Picking one plays it straight away so you can see it.
- An older iPhone or Mac without effects still works: the Mac plays the classic landing.
- `--demo <effect>` plays one effect, and `scripts/effects.sh` draws every effect's frames.

## 1.1.0 — 2026-10-30

👆 Swipe up to drop, like NameDrop, with both screens reacting together.

- **Swipe the stack up on the iPhone.** It follows your finger and fans out, ticks when letting go
  will drop it, then flies off the top of the screen. A small flick works too. Chevrons over the
  stack show it can be swiped, and it lifts when the iPhone is close.
- **The Mac follows along live.** Its panel now slides down out of the menu bar with three empty
  slots. As you swipe, cards drop into them and the panel brightens. When you let go, the real
  thumbnails of what you threw slide in before the first byte arrives.
- **Swipe the panel away on the Mac:** two fingers up, or drag it up. If you put it away
  mid-drop, it comes back when the drop is done.
- **When brought close: Swipe Up (new default) or Drop Right Away**, in the iPhone's Settings.
  This replaces the *Send when brought close* switch.
- If the iPhone disconnects mid-drop, the Mac now says so instead of waiting.
- `--demo` plays the swipe and the throw too.

## 1.0.0 — 2026-10-29

🪂 First release: NameDrop-style drops from your iPhone to your Mac.

- **Bring it close and it drops**: pick photos, files or a link on the iPhone, hold the top of
  the iPhone near the Mac, and they land in `~/Downloads/Pampu`. The iPhone buzzes and a glow
  rolls down its screen; a matching panel drops in under the Mac's menu bar with live progress,
  thumbnails, **Open** and **Show in Finder**.
- **Share sheet**: Photos, Files, Safari or any app › Share › **Pampu**.
- **No shared network needed**: a direct, encrypted peer-to-peer link (MultipeerConnectivity,
  over peer-to-peer Wi-Fi and Bluetooth). Works on office and guest Wi-Fi, and with no Wi-Fi at all.
- **Pair once**: matching code on both screens and one click on the Mac. After that every drop
  is checked with a per-iPhone secret.
- **Sorted for you**: Photos, Screenshots, Videos, Audio, Documents, Archives and Other folders
  (can be turned off), names never overwrite, and links and text go to the clipboard.
- Signal-strength closeness (Touching / Close / Nearby) with a live reading, a Send button for
  when Bluetooth is off, several Macs to pick from, and a choice between original HEIC and
  compatible JPEG photos.
- Mac: 🪂 menu-bar menu with Receiving on/off, Recent Drops, drop folder, sounds, paired iPhones,
  Appearance System / Light / Dark, and open at login. iPhone: Appearance System / Light / Dark.
