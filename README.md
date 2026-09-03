# Claude-lxde-inst.sh

A single script that turns a stock **Raspberry Pi OS Lite 64-bit** install
(Raspberry Pi 5, 2GB RAM) into a minimal **standard LXDE-pi desktop** on X11
at 1920x1080. There is no substitute panel, compositor, app launcher or
notification daemon — the panel is the real `lxpanel-pi`, the desktop
background/icons come from `pcmanfm --desktop`, and the window manager is
Openbox, exactly as stock Raspberry Pi OS wires them together
(`lxsession -s LXDE-pi -e LXDE`).

Raspberry Pi OS is currently based on **Debian 13 "Trixie"**. The Raspberry Pi
desktop meta-packages `rpd-x-core` and `rpd-graphics` come from
`archive.raspberrypi.com`; everything else comes from Debian Trixie `arm64`.

## Usage

Copy `Claude-lxde-inst.sh` onto the Raspberry Pi 5 (Lite 64-bit, freshly
flashed, connected to the network) — `scp` it over, or download it directly
onto the Pi — then:

```bash
chmod +x Claude-lxde-inst.sh
./Claude-lxde-inst.sh
sudo reboot
```

Run it as your normal user (the one with sudo rights) — **not** as root; the
script refuses to run under `sudo ./Claude-lxde-inst.sh` or as `root` directly.

After rebooting, the Pi boots to a text console, auto-logs in on tty1, and
`startx` launches the LXDE-pi session automatically.

## The session

`~/.xinitrc` runs `lxsession -s LXDE-pi -e LXDE` — the same invocation stock
Raspberry Pi OS's own `startlxde-pi` script uses. lxsession reads
`~/.config/lxsession/LXDE-pi/desktop.conf` (window manager = Openbox, dark GTK
theme, Numix-Circle icons, `Ubuntu Nerd Font 11`) and its `autostart` file,
which starts exactly two things:

```
@lxpanel --profile LXDE-pi
@pcmanfm --desktop --profile LXDE-pi
```

That's the real panel (with its normal network / volume / battery / power /
updater / eject plugins) and the real desktop manager. Nothing else runs —
**no compositor, no second panel, no notification daemon, no separate app
launcher.** Those aren't part of a standard LXDE install, so this script
doesn't add them.

`/etc/xdg/lxsession/LXDE-pi/autostart` is blanked by the installer: lxsession
merges the system file with the per-user one, and leaving the system default
in place would start lxpanel and pcmanfm a second time.

### The "app menu"

Right-click the desktop, or press `Super+Space` / `Alt+F2`, for Openbox's own
built-in root menu (Terminal, File Manager, vimb, Mousepad, Geany, Image
Viewer, PDF Viewer, Flameshot, Pi-Apps, raspi-config, Lock, Log Out). It's a
zero-dependency Openbox feature — no jgmenu, no rofi — and its background is
set to the exact requested `#262626` (R:38 G:38 B:38) via Openbox's own theme
keys (`menu.items.bg.color` in `~/.themes/PiDark/openbox-3/themerc`).

lxpanel-pi's own Applications menu (the start button on the panel) is also
present as standard; a small `~/.config/gtk-3.0/gtk.css` override nudges its
GTK popup background to the same color, since that one is drawn by GTK rather
than Openbox.

### Why no display manager

`rpd-x-core` depends on `rpd-common`, which pulls in **lightdm** and
**pi-greeter**. A resident greeter plus a `graphical.target` boot costs roughly
60–80MB of RAM for nothing here, so the installer disables lightdm and sets the
default target back to `multi-user.target`. `sudo systemctl enable lightdm &&
sudo systemctl set-default graphical.target` restores it if you want it.

## What gets installed

| Category | Packages / components |
|---|---|
| Pi desktop metas | `rpd-x-core`, `rpd-graphics` (the latter needs Recommends — it is a Recommends-only meta-package) |
| X11 | `xserver-xorg`, `xinit`, `x11-xserver-utils`, libinput driver, base fonts |
| LXDE-pi (via rpd-x-core / rpd-common) | `lxsession`, `openbox`, `lxpanel-pi`, `pcmanfm`, `lxterminal` |
| Terminal / browser | LXTerminal, vimb |
| Editors | Mousepad, Geany |
| File manager | PCManFM (+ gvfs/udisks2 for removable media), `lxappearance` |
| Dev tools | `build-essential` (gcc/g++/make), `raspi-config`, `raspi-utils-core`, `raspi-utils-dt`, GPIO libs, Pi-Apps |
| SSH | dropbear (replaces openssh-server if present, to save RAM) |
| Extras | flameshot, lximage-qt, qpdfview, fastfetch, git, curl, `suckless-tools` (slock) |
| Prompt | Oh My Posh (active), Starship (installed as an alternative) |
| Theming | Kvantum-Dark (Qt apps), Numix-Circle icons, Ubuntu Nerd Font 11 |

Pi-Apps is installed from the upstream 64-bit installer, then
`~/pi-apps/manage install Min` and `~/pi-apps/manage install 'Geany Dark Mode'`
are run. All three steps are non-fatal: a Pi-Apps failure does not undo the
rest of the install.

### LXTerminal, not QTerminal

The request allowed either. LXTerminal wins on memory: it is a plain GTK/VTE
process (~25MB RSS) rather than a Qt one (~50MB+ once QtCore/QtGui/QtWidgets
and qtermwidget are mapped in). It's also literally the standard LXDE
terminal and already an `rpd-common` dependency, so choosing it also avoids
installing `qterminal` + `qtermwidget` at all.

## Colours

| Thing | Colour |
|---|---|
| Desktop background (pcmanfm) | `#383C48` — R:56 G:60 B:72 |
| Openbox app menu background | `#262626` — R:38 G:38 B:38, exact |
| Active window border | `#4C7BC4` (blue), 1px |
| Inactive window border | `#1B1D24` (very dark), 1px |
| Accent (menu selection) | `#4C7BC4` |

Kvantum-Dark is applied to the Qt applications (qpdfview, lximage-qt,
flameshot) through qt5ct/qt6ct. Everything else — LXTerminal, PCManFM,
Mousepad, Geany, vimb, lxpanel — is GTK, and gets a dark look through
lxsession's own `[GTK]` theme keys (`sNet/ThemeName=Adwaita` with
`gtk-application-prefer-dark-theme=1`), which is the standard LXDE mechanism
for this, not a hand-rolled substitute.

## Fonts

`Ubuntu.zip` and `UbuntuMono.zip` are fetched from the latest Nerd Fonts
release and only the **Regular** faces are installed into
`/usr/local/share/fonts/UbuntuNerdFont`.

The family names are then read back from `fc-list` rather than hardcoded —
Nerd Fonts has renamed these families between releases (`Ubuntu Nerd Font` vs
`UbuntuSans Nerd Font`), and a wrong family name silently falls back to a
default font everywhere. Note that each archive also ships a `... Nerd Font
Mono` family, in which only the *added icon glyphs* are single-width; the
underlying face is still proportional. The real fixed-pitch family is the one
from `UbuntuMono.zip`, and that is what the terminal and Qt's "fixed" font use.

`/etc/fonts/local.conf` maps the generic `sans-serif` / `Sans` / `monospace`
aliases onto those families, so applications that ask for a generic font get
the Nerd Font too. Size 11 is used everywhere.

## Prompt

Both prompt tools asked for are installed, but only one can own `PS1`. Oh My
Posh is the one wired up ("Oh-my-posh for bash prompt tool"), with its built-in
default theme; Starship is installed with its default theme and is one
commented line away at the end of `~/.bashrc`:

```bash
if command -v oh-my-posh >/dev/null 2>&1; then
    eval "$(oh-my-posh init bash)"
elif command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
```

`export PATH=$PATH:$HOME/.local/bin` is added to `~/.bashrc` (Oh My Posh is
installed there).

## Keys and mouse

| Binding | Action |
|---|---|
| `Super`+`Return` | LXTerminal |
| `Super`+`Space` / `Alt`+`F2` | Openbox root menu (app launcher) |
| `Super`+`E` | PCManFM |
| `Super`+`D` | show desktop |
| `Super`+`L` | lock screen (`slock`) |
| `Print` | flameshot |
| `Alt`+`F4` / `Alt`+`Tab` | close / next window |
| `Alt`+drag / `Alt`+right-drag | move / resize (there are no titlebars to grab) |
| `Alt`+`F7` / `Alt`+`F8` | keyboard move / resize |
| Right-click desktop | Openbox root menu |

Logging out is "Log Out" in the root menu (runs `lxsession-logout`), or the
panel's own power/logout plugin.

## Notes and caveats

* **Disk, not RAM.** `rpd-graphics` is a Recommends-only meta-package
  (GStreamer, ffmpeg, Vulkan, Mesa). It must be installed with Recommends
  enabled or it installs nothing at all, and it is several hundred MB of
  libraries and codecs. It costs disk space, not memory.
* `rpd-x-core` only exists in the Raspberry Pi archive. The script checks for
  it up front (`apt-cache show rpd-x-core`, which doesn't depend on
  `apt-cache policy`'s text formatting the way an earlier draft did) and
  explains what's missing rather than letting apt fail with "Unable to locate
  package".
* The script requires an `arm64` userland and stops otherwise
  (`FORCE_ARCH=1` overrides).
* Pi 5 GPIO uses the RP1 chip, so classic `RPi.GPIO` does not work —
  `python3-rpi-lgpio` (a drop-in replacement), `python3-gpiozero`,
  `python3-libgpiod` and `gpiod` are installed instead.
* dropbear becomes the SSH server on port 22 and `openssh-server` is disabled
  if it was active, since running both would conflict on the port.
* A polkit authentication agent (needed for GUI password prompts, e.g. a WPA
  passphrase change through NetworkManager) is started via lxsession's own
  `polkit/command` session key, using a small script that tries a few known
  install paths for the `mate-polkit-bin` agent `rpd-common` installs.
* The installer is re-runnable: the `.bashrc` edits are guarded by `grep`, and
  Pi-Apps is skipped if `~/pi-apps` already exists.

## Origin

This script is `install-rpi-LXDE/install.sh` from the
`krys314-rpi5-claude` repository, renamed to `Claude-lxde-inst.sh` for
standalone download. The repository also has an earlier, non-standard build
at its root (Openbox + picom + tint2 + jgmenu + rofi + dunst rather than the
real LXDE-pi stack) — this script supersedes that approach entirely.
