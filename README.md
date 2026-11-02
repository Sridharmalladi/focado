<div align="center">

# Focado

**A small pixel avocado that keeps your focus block company.**

</div>

Focado is a macOS Pomodoro timer in a compact desktop window. Start a 25-minute focus session, take a break, and check the remaining time in the avocado's pit. The pixel art is drawn in Swift.

## Download

[Download Focado for Mac](https://github.com/Sridharmalladi/focado/releases/latest/download/Focado.dmg), open the DMG, and drag Focado into Applications. Focado requires macOS 14 or later on an Apple silicon Mac.

The app is ad-hoc signed rather than notarized. On first launch, macOS may ask you to allow Focado in **System Settings → Privacy & Security**.

## Build

Requires macOS 14 or later and Swift 5.9+. From the repository root, run:

```bash
./build_app.sh
```

The script creates and ad-hoc signs `Focado.app` for local use.

To create the release disk image:

```bash
./package_dmg.sh
```
