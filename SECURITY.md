# Security policy

## Reporting a problem

Please report security problems privately through GitHub:
**Security → Report a vulnerability** on this repository. Don't open a public issue for them.

Include what you found, how to reproduce it, and the Pampu version (🪂 menu → About on the Mac,
Settings on the iPhone). You'll get a reply within a week.

## Supported versions

Only the latest release gets fixes. Update from the
[latest release](https://github.com/Sravankumartangudu/pampu/releases/latest).

## How Pampu protects what you send

- **Direct and encrypted.** The iPhone and the Mac talk over Apple's MultipeerConnectivity with
  encryption required. Nothing goes through a server, a cloud or an account. There are no
  analytics or ads.
- **Pairing.** The first time, the iPhone shows a 4-digit code and the Mac asks you, showing the
  same code, before it trusts that iPhone. Each pairing creates a fresh random 32-byte secret.
- **Every connection is checked.** The Mac sends a new random challenge each time an iPhone
  connects. The iPhone answers with an HMAC-SHA256 of the challenge, keyed with its secret, and
  the Mac compares it in constant time. Files from an iPhone that hasn't passed are cancelled
  before they're saved.
- **Previews.** When you swipe, the iPhone sends small 120-pixel previews of the first three items
  ahead of the files, over the same encrypted link. The Mac only shows them for a paired iPhone,
  and keeps them in memory for the length of the panel.
- **Safe file names.** Incoming names are cut to the last path part, with slashes and colons
  replaced and line breaks and leading dots removed, so a file can't land outside the drop folder or hide
  itself. Existing files are never overwritten (" 2", " 3"… is added).
- **Links don't open by themselves** unless you turn on Open Links Automatically, and then only
  `http` and `https` links.
- **Turning it off.** Uncheck Receiving in the 🪂 menu to stop the Mac being visible at all.
  Forget an iPhone (🪂 › Paired iPhones) and it has to pair again.

## What's stored

- **Mac:** settings in the app's preferences (`com.stangudu.pampu`), and paired iPhones (id, name,
  secret) in `~/Library/Application Support/Pampu/devices.json`, readable only by your user
  account (folder 0700, file 0600). Received files go to the drop folder you choose.
- **iPhone:** this iPhone's id and name, each Mac's pairing secret and the drop settings in the
  Keychain (this device only, after first unlock), shared between the app and its Share
  extension. Items waiting to send are copied to the app's temporary folder and removed after
  they're sent or cleared.
- **Status files (Mac):** small local files in `~/.nexus/` (a heartbeat with the name, version
  and ready / receiving, and a copy of the 🪂 menu) for Nexus, the author's local app monitor.
  They hold no file contents and never leave the Mac.

## Permissions

- **Bluetooth (both):** the Mac sends out a small signal and the iPhone measures how strong it
  is, to tell when they're close. Nothing else is read.
- **Local network (both):** needed by MultipeerConnectivity to find and talk to the other device.
- **Photos (iPhone):** none. The system photo picker hands over only what you pick.
