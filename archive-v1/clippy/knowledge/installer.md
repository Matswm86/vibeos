# Installer Flow (live ISO only)

When the user is running VibeOS from a live USB and wants to install it
to disk, the flow is:

1. **Connect to Wi-Fi first** — top-right system tray, click the network
   icon, pick their network, type the password. You can confirm with
   the user that they're online before continuing.
2. **Click the yellow "Install VibeOS" button in your titlebar.** That
   spawns Calamares (the installer) via `pkexec`, which prompts for the
   live-session password (usually blank or `vibeos`).
3. **Calamares walks them through 5 screens:**
   - *Welcome*: language pick.
   - *Location*: timezone (auto-detected if online).
   - *Keyboard*: layout (auto-detected from locale).
   - *Partitions*: simplest path is "Erase disk" — ONLY safe if the user
     has nothing on this disk they want to keep. If they have Windows or
     another OS to preserve, recommend "Manual partitioning" and tell
     them to ask you for help, or to back up first.
   - *Users*: name, username, computer name, password. Username should
     be lowercase, no spaces.
   - *Summary + Install*: shows what will happen. Last chance to cancel.
4. **Wait ~10–20 minutes** for files to copy.
5. **Reboot.** Remove the USB stick when prompted.
6. **First login**: same username/password they just set. You'll be there
   to greet them again.

## What to say if they're nervous

- "Erase disk" wipes EVERYTHING on that disk. If they have files they
  want to keep, stop the install and tell them to back up first.
- The install is **reversible** until they click the final "Install"
  button on the Summary screen. Up to that point, closing Calamares does
  nothing.
- If Wi-Fi isn't working, the install still works — VibeOS bundles
  Ollama locally so you (Vibbey) keep working offline. The user can set
  up Wi-Fi later from the installed system.

## Common stuck points

- **Calamares won't start** → live user might not have polkit rules. Tell
  them to open Konsole and run `sudo calamares -d` directly.
- **Disk not showing in partition step** → it's a hardware RAID or weird
  USB enclosure. Reboot, drop into BIOS, switch SATA mode to AHCI.
- **Install hangs at 100%** → almost always cosmetic. Wait 60 seconds.
  If still stuck, reboot — the install is usually done, the post-install
  hook just crashed.

## Tooling

You have a `[[RUN: install_vibeos]]` tool that does the same thing as
the yellow button. Prefer the button (it shows a polished confirm
dialog) but the tool is there if the user types "install it" in chat.
You can also run `[[RUN: is_live_session]]` to check whether you're on
the live ISO — exit_code=0 means yes.
