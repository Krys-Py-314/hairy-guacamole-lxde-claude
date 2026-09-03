#!/usr/bin/env bash
#
# Raspberry Pi 5 (2GB) - Minimal Standard LXDE Desktop Installer
# Target: Raspberry Pi OS Lite 64-bit (Debian Trixie based)
#
# Builds the actual standard Raspberry Pi LXDE desktop (LXDE-pi profile):
# lxsession drives the session, Openbox is the window manager (1px square
# borders, no titlebars), lxpanel-pi is the panel (with its normal Pi
# plugins - menu, network, volume, battery, power, updater, eject), and
# pcmanfm draws the desktop background/icons. No compositor, no extra
# panel, no extra notification daemon, no extra app launcher - those are
# not part of a standard LXDE install, so this script does not add them.
# Themed dark with Kvantum-Dark for Qt apps and a hand-tuned dark GTK
# preference for everything else, Numix-Circle icons, Ubuntu Nerd Font at
# size 11 system-wide, and Oh My Posh for the bash prompt.
#
# The Raspberry Pi desktop meta-packages rpd-x-core and rpd-graphics are
# installed as requested; the display manager (lightdm) they pull in is
# disabled again afterwards, because booting to a console + autologin +
# startx costs noticeably less RAM than keeping a greeter resident.
#
# Usage on the Pi:
#   git clone https://github.com/Krys-Py-314/krys314-rpi5-claude.git
#   cd krys314-rpi5-claude/install-rpi-LXDE
#   chmod +x install.sh
#   ./install.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Colors for output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please do not run this script as root. Run as normal user with sudo privileges."
    exit 1
fi

print_status "Starting Raspberry Pi 5 Minimal LXDE/Openbox Setup..."

# ---------------------------------------------------------------------------
# Architecture check - every package name in this script was verified
# against the Debian Trixie arm64 repositories. A 32-bit userland (armhf)
# is a different package set and is known to break Pi-Apps on Trixie.
# ---------------------------------------------------------------------------
DPKG_ARCH="$(dpkg --print-architecture 2>/dev/null || echo unknown)"
if [ "$DPKG_ARCH" != "arm64" ]; then
    print_error "This system reports dpkg architecture '${DPKG_ARCH}', not 'arm64'."
    print_error "This script targets Raspberry Pi OS Lite 64-bit only. A 32-bit"
    print_error "(armhf) install uses a different package set and is known to break"
    print_error "Pi-Apps on Trixie ('Your system is 32-bit ... Pi-Apps is supporting"
    print_error "64-bit only going forward')."
    print_error "Check with: dpkg --print-architecture ; uname -m"
    print_error "Expected: arm64 / aarch64. If you see armhf / armv7l, re-flash using"
    print_error "Raspberry Pi Imager -> Raspberry Pi OS (other) -> 'Raspberry Pi OS"
    print_error "Lite (64-bit)' (not a 'Legacy' or plain 'Raspberry Pi OS Lite' entry)."
    print_error "Set FORCE_ARCH=1 before running this script to proceed anyway."
    if [ "${FORCE_ARCH:-0}" != "1" ]; then
        exit 1
    fi
    print_warning "FORCE_ARCH=1 set - continuing on a non-arm64 system at your own risk."
fi

# ---------------------------------------------------------------------------
# Basic sanity / constants
# ---------------------------------------------------------------------------
TARGET_USER="$(whoami)"
TARGET_HOME="$HOME"
TARGET_GROUP="$(id -gn)"

# The LXDE-pi profile name lxsession/lxpanel/pcmanfm all share, exactly as
# used by stock Raspberry Pi OS ("exec /usr/bin/lxsession -s LXDE-pi -e LXDE").
LXDE_PROFILE="LXDE-pi"

DESKTOP_BG="#383C48"          # R:56 G:60 B:72
ACTIVE_BORDER="#4C7BC4"       # light/mid blue for the focused window border
INACTIVE_BORDER="#1B1D24"     # very dark border for unfocused windows
MENU_BG="#262626"             # R:38 G:38 B:38 - Openbox root menu background
UI_FG="#E6E6E6"
ACCENT="#4C7BC4"
# Font families are re-resolved from fc-list after the Nerd Font is
# installed (see section 9); these are the fallbacks used if that fails.
NERD_FONT_DISPLAY="Ubuntu Nerd Font"
NERD_FONT_MONO="UbuntuMono Nerd Font"
UI_FONT_SIZE="11"

if ! command -v sudo >/dev/null 2>&1; then
    print_error "sudo is required but not installed. Install sudo as root first, then re-run this script."
    exit 1
fi

mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/.config" "$TARGET_HOME/.themes" \
         "$TARGET_HOME/.local/share/applications" "$TARGET_HOME/.local/share/fonts"

# ---------------------------------------------------------------------------
# 1. APT base setup
# ---------------------------------------------------------------------------
# rpd-common pulls in lightdm; without this apt can stop on a debconf
# prompt half way through an otherwise unattended run.
export DEBIAN_FRONTEND=noninteractive

print_status "Updating package lists..."
sudo apt-get update

# Recommends are off by default: on a 2GB Pi they are what turns a small
# desktop into a large one. rpd-graphics is the one place that genuinely
# needs them - it is a Recommends-only meta-package and installs nothing
# without them - and it is called with plain apt-get further down.
APT_INSTALL="sudo apt-get install -y -o APT::Install-Recommends=false"

# ---------------------------------------------------------------------------
# 2. X11 minimal environment
# ---------------------------------------------------------------------------
print_status "Installing minimal X11 environment..."
$APT_INSTALL \
    xserver-xorg \
    xinit \
    xauth \
    x11-xserver-utils \
    xserver-xorg-input-libinput \
    xfonts-base \
    fonts-dejavu-core

# ---------------------------------------------------------------------------
# 2b. The Raspberry Pi LXDE desktop (rpd-x-core) + graphics support
#
# rpd-x-core is the Raspberry Pi "X11 desktop" meta-package on Trixie (it
# replaced raspberrypi-ui-mods). It depends on rpd-common, which brings
# lxsession, pcmanfm, lxterminal, raspi-config, pishutdown, NetworkManager,
# PipeWire, qt5ct/qt6ct and polkit; rpd-x-core itself adds xserver-xorg,
# xinit, x11-xserver-utils, Openbox and lxpanel-pi (with its normal plugin
# set: menu, network, volume, battery, power, updater, eject, bluetooth).
# This is the actual standard LXDE-pi stack - nothing here is replaced by
# a substitute panel/menu/compositor/notifier.
#
# rpd-graphics only has Recommends (gstreamer, ffmpeg, mesa-vulkan-drivers,
# ...), so it MUST be installed with recommends enabled or it installs
# nothing at all. It is libraries and codecs: disk cost, not RAM cost.
# ---------------------------------------------------------------------------
# rpd-* only exists in the Raspberry Pi archive, not in Debian. Checking up
# front turns "E: Unable to locate package rpd-x-core" into an explanation.
# `apt-cache show` (not `policy`, whose "Candidate:" line format has been
# known to shift between apt versions and trip up text-scraping) simply
# succeeds iff the package's metadata is present in some configured source.
if ! apt-cache show rpd-x-core >/dev/null 2>&1; then
    print_error "The package 'rpd-x-core' is not available from any configured apt source."
    print_error "It comes from the Raspberry Pi archive, which every Raspberry Pi OS"
    print_error "install has in /etc/apt/sources.list.d/raspi.list:"
    print_error "    deb http://archive.raspberrypi.com/debian/ trixie main"
    print_error "This script targets Raspberry Pi OS Lite 64-bit; on plain Debian arm64"
    print_error "that archive has to be added (and its key installed) first."
    exit 1
fi

print_status "Installing the Raspberry Pi LXDE desktop (rpd-x-core)..."
$APT_INSTALL rpd-x-core

print_status "Installing rpd-graphics (needs Recommends - it is a Recommends-only meta-package)..."
sudo apt-get install -y rpd-graphics

# ---------------------------------------------------------------------------
# 2c. Boot to console, not to a display manager
#
# rpd-common depends on lightdm + pi-greeter. A resident greeter and a
# graphical.target boot cost roughly 60-80MB of RAM for nothing here: the
# machine autologins on tty1 and runs startx (section 22). Disable rather
# than purge, so 'sudo systemctl enable lightdm' restores it if wanted.
# ---------------------------------------------------------------------------
print_status "Disabling the lightdm display manager (booting to console + startx uses less RAM)..."
sudo systemctl disable lightdm >/dev/null 2>&1 || true
sudo systemctl stop lightdm >/dev/null 2>&1 || true
sudo systemctl set-default multi-user.target >/dev/null 2>&1 || true

print_status "Configuring KMS/modesetting driver for the Pi 5 (vc4/RP1 GPU)..."
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/99-vc4.conf >/dev/null <<'EOF'
Section "OutputClass"
    Identifier "vc4"
    MatchDriver "vc4"
    Driver "modesetting"
    Option "PrimaryGPU" "true"
EndSection
EOF

print_status "Forcing the console resolution to 1920x1080 for X..."
sudo tee /etc/X11/xorg.conf.d/98-resolution.conf >/dev/null <<'EOF'
Section "Monitor"
    Identifier "HDMI-1"
    Option "PreferredMode" "1920x1080"
EndSection

Section "Screen"
    Identifier "Screen0"
    Monitor "HDMI-1"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080"
    EndSubSection
EndSection
EOF

# ---------------------------------------------------------------------------
# 3. Tools
# ---------------------------------------------------------------------------
# LXTerminal rather than QTerminal: it is the LXDE terminal, it is already
# pulled in by rpd-common, and it is a plain GTK/VTE process (~25MB RSS)
# instead of a Qt one (~50MB+ once QtCore/QtGui/QtWidgets and qtermwidget
# are mapped in), which is the smaller memory footprint asked for.
print_status "Installing LXTerminal, vimb, Mousepad, Geany, PCManFM..."
$APT_INSTALL \
    lxterminal \
    lxappearance \
    vimb \
    mousepad \
    geany \
    geany-common \
    pcmanfm \
    gvfs \
    gvfs-backends \
    udisks2 \
    xdg-user-dirs \
    xarchiver \
    suckless-tools

# ---------------------------------------------------------------------------
# 4. Development tools
# ---------------------------------------------------------------------------
print_status "Installing development toolchain (gcc, g++, make)..."
$APT_INSTALL build-essential

print_status "Installing raspi-config and Raspberry Pi hardware utilities..."
# The old libraspberrypi-bin package (vcgencmd, vcdbg, ...) has been retired
# on current Raspberry Pi OS and split into raspi-utils-core (hardware
# utilities) and raspi-utils-dt (device-tree utilities: dtoverlay, dtparam).
$APT_INSTALL \
    raspi-config \
    raspi-utils-core \
    raspi-utils-dt \
    raspberrypi-sys-mods

print_status "Installing GPIO libraries (Pi 5 uses the RP1 chip - classic RPi.GPIO does not work, using rpi-lgpio instead)..."
$APT_INSTALL \
    python3-rpi-lgpio \
    python3-gpiozero \
    python3-libgpiod \
    gpiod

print_status "Installing dropbear SSH server..."
$APT_INSTALL dropbear

if systemctl is-enabled ssh >/dev/null 2>&1 || systemctl is-active ssh >/dev/null 2>&1; then
    print_warning "openssh-server is active and would conflict with dropbear on port 22. Disabling it."
    sudo systemctl disable --now ssh >/dev/null 2>&1 || true
fi

if [ -f /etc/default/dropbear ]; then
    sudo sed -i 's/^NO_START=.*/NO_START=0/' /etc/default/dropbear || true
fi

sudo systemctl enable --now dropbear >/dev/null 2>&1 || sudo systemctl enable --now dropbear.socket >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 5. Other utilities
# ---------------------------------------------------------------------------
print_status "Installing flameshot, lximage-qt, qpdfview, fastfetch, git, curl..."
$APT_INSTALL \
    flameshot \
    lximage-qt \
    qpdfview \
    fastfetch \
    git \
    curl \
    unzip \
    ca-certificates

# ---------------------------------------------------------------------------
# 6. Theming: Kvantum, Numix-Circle icons, Qt config tools
# ---------------------------------------------------------------------------
print_status "Installing Kvantum (Qt5 + Qt6), qt5ct/qt6ct, and Numix-Circle icons..."
$APT_INSTALL \
    qt5-style-kvantum \
    qt6-style-kvantum \
    qt-style-kvantum-themes \
    qt5ct \
    qt6ct \
    numix-icon-theme-circle \
    alsa-utils

# ---------------------------------------------------------------------------
# 7. Starship prompt
# ---------------------------------------------------------------------------
print_status "Installing Starship prompt..."
$APT_INSTALL starship

# ---------------------------------------------------------------------------
# 7b. Oh My Posh (the active bash prompt)
#
# Not packaged in Debian, so it comes from the upstream installer, which
# detects aarch64 and drops a single static Go binary in the directory given
# with -d. ~/.local/bin is on PATH via .bashrc (section 20).
#
# Both prompt tools were asked for. Only one can own PS1, so Oh My Posh is
# the one wired up ("Oh-my-posh for bash prompt tool"); Starship is
# installed with its default theme and left one commented line away in
# .bashrc if you would rather use it.
# ---------------------------------------------------------------------------
print_status "Installing Oh My Posh prompt..."
if ! curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$TARGET_HOME/.local/bin"; then
    print_warning "Oh My Posh install failed; .bashrc will fall back to the Starship prompt."
fi

# ---------------------------------------------------------------------------
# 8. Ubuntu Nerd Font (system-wide)
#
# Two archives: Ubuntu.zip is the proportional family (used for every UI
# font below) and UbuntuMono.zip is the fixed-width one (used for the
# terminal and for Qt's "fixed" font). Only the Regular faces are copied,
# as asked - that keeps /usr/local/share/fonts small.
# ---------------------------------------------------------------------------
print_status "Installing Ubuntu Nerd Font (Regular) system-wide..."
NERD_FONT_TMP="$(mktemp -d)"
NERD_FONT_VERSION="$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || true)"
if [ -z "$NERD_FONT_VERSION" ]; then
    NERD_FONT_VERSION="v3.4.0"
    print_warning "Could not query the latest Nerd Fonts release; falling back to ${NERD_FONT_VERSION}."
fi

sudo mkdir -p /usr/local/share/fonts/UbuntuNerdFont
for NERD_ZIP in Ubuntu UbuntuMono; do
    if curl -fsSL -o "$NERD_FONT_TMP/${NERD_ZIP}.zip" \
        "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONT_VERSION}/${NERD_ZIP}.zip"; then
        unzip -oq "$NERD_FONT_TMP/${NERD_ZIP}.zip" -d "$NERD_FONT_TMP/${NERD_ZIP}"
        sudo find "$NERD_FONT_TMP/${NERD_ZIP}" -iname "*Regular*.ttf" \
            -exec cp {} /usr/local/share/fonts/UbuntuNerdFont/ \;
    else
        print_warning "Failed to download ${NERD_ZIP} Nerd Font; a default font will be used instead."
    fi
done
sudo fc-cache -f >/dev/null 2>&1 || true
rm -rf "$NERD_FONT_TMP"

# Resolve the family names actually registered with fontconfig rather than
# hardcoding them: Nerd Fonts has renamed these families between releases
# ("Ubuntu Nerd Font" vs "UbuntuSans Nerd Font", "UbuntuMono Nerd Font" vs
# "UbuntuSansMono Nerd Font"), and a wrong family name silently falls back
# to a default font in every config file written below.
#
# Note that every Nerd Font archive ships three families - e.g. Ubuntu.zip
# gives "Ubuntu Nerd Font", "Ubuntu Nerd Font Mono" and "Ubuntu Nerd Font
# Propo". The "... Nerd Font Mono" one only means the *added* icon glyphs
# are single-width; the underlying Ubuntu face is still proportional, so it
# is a poor terminal font. The real fixed-pitch family is the one from
# UbuntuMono.zip, which is why the mono match below is anchored on a family
# name that *starts* with UbuntuMono/UbuntuSansMono.
nerd_families() {
    fc-list : family 2>/dev/null | tr ',' '\n' | sed 's/^ *//; s/ *$//' | sort -u
}
pick_family() {
    nerd_families | grep -iE "$1" | head -1 || true
}

FOUND_FONT="$(pick_family '^ubuntu(sans)? nerd font$')"
[ -z "$FOUND_FONT" ] && FOUND_FONT="$(pick_family '^ubuntu.* nerd font$')"
[ -n "$FOUND_FONT" ] && NERD_FONT_DISPLAY="$FOUND_FONT"

FOUND_MONO="$(pick_family '^ubuntu(sans)?mono nerd font$')"
[ -z "$FOUND_MONO" ] && FOUND_MONO="$(pick_family '^ubuntu.* nerd font mono$')"
if [ -n "$FOUND_MONO" ]; then
    NERD_FONT_MONO="$FOUND_MONO"
else
    NERD_FONT_MONO="Monospace"
    print_warning "No Ubuntu Mono Nerd Font family found; terminals will use Monospace."
fi
print_status "UI font: '${NERD_FONT_DISPLAY} ${UI_FONT_SIZE}'  /  monospace font: '${NERD_FONT_MONO}'"

# Make it the system-wide default for the generic sans-serif / monospace
# aliases, so applications that ask for "Sans" (rather than a named family)
# also get the Nerd Font.
sudo tee /etc/fonts/local.conf >/dev/null <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer><family>${NERD_FONT_DISPLAY}</family></prefer>
  </alias>
  <alias>
    <family>Sans</family>
    <prefer><family>${NERD_FONT_DISPLAY}</family></prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer><family>${NERD_FONT_MONO}</family></prefer>
  </alias>
  <match target="pattern">
    <test qual="any" name="family"><string>Monospace</string></test>
    <edit name="family" mode="assign" binding="same"><string>${NERD_FONT_MONO}</string></edit>
  </match>
</fontconfig>
EOF
sudo fc-cache -f >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 9. Openbox theme: 1px square borders, no titlebar text/buttons,
#    blue/dark borders, and the root-menu ("app menu") background color.
# ---------------------------------------------------------------------------
print_status "Building the custom Openbox theme (square windows, 1px border, no titles)..."
mkdir -p "$TARGET_HOME/.themes/PiDark/openbox-3"
cat > "$TARGET_HOME/.themes/PiDark/openbox-3/themerc" <<EOF
window.active.border.color: ${ACTIVE_BORDER}
window.inactive.border.color: ${INACTIVE_BORDER}
window.active.title.bg: Flat Solid
window.active.title.bg.color: ${ACTIVE_BORDER}
window.inactive.title.bg: Flat Solid
window.inactive.title.bg.color: ${INACTIVE_BORDER}
window.active.label.bg: Parentrelative
window.inactive.label.bg: Parentrelative
window.active.label.text.color: ${ACTIVE_BORDER}
window.inactive.label.text.color: ${INACTIVE_BORDER}
window.active.button.unpressed.image.color: ${ACTIVE_BORDER}
window.inactive.button.unpressed.image.color: ${INACTIVE_BORDER}
window.active.handle.bg: Flat Solid
window.active.handle.bg.color: ${INACTIVE_BORDER}
window.inactive.handle.bg: Flat Solid
window.inactive.handle.bg.color: ${INACTIVE_BORDER}
border.width: 1
padding.width: 0
padding.height: 0
window.client.padding.height: 0
window.handle.width: 4
menu.items.bg: Flat Solid
menu.items.bg.color: ${MENU_BG}
menu.items.text.color: ${UI_FG}
menu.items.active.bg: Flat Solid
menu.items.active.bg.color: ${ACCENT}
menu.items.active.text.color: #FFFFFF
menu.title.bg: Flat Solid
menu.title.bg.color: ${ACCENT}
menu.title.text.color: #FFFFFF
menu.border.color: ${ACCENT}
menu.border.width: 1
osd.bg: Flat Solid
osd.bg.color: ${MENU_BG}
osd.label.text.color: ${UI_FG}
font.active.title: Sans Bold 1
font.inactive.title: Sans Bold 1
font.menu.title: ${NERD_FONT_DISPLAY} ${UI_FONT_SIZE}
font.menu.item: ${NERD_FONT_DISPLAY} ${UI_FONT_SIZE}
font.osd.title: ${NERD_FONT_DISPLAY} ${UI_FONT_SIZE}
EOF

# ---------------------------------------------------------------------------
# 10. Openbox rc.xml
#
# The root-menu below is Openbox's own built-in menu support (no extra
# package) - it is what "right-click the desktop" opens, standing in for a
# separate app-launcher menu without adding one. Its colors come from the
# themerc's menu.* keys above, which is how "the background color of app
# menu" is met precisely.
# ---------------------------------------------------------------------------
print_status "Writing Openbox configuration (rc.xml)..."
mkdir -p "$TARGET_HOME/.config/openbox"
cat > "$TARGET_HOME/.config/openbox/rc.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
  </focus>
  <placement>
    <policy>Smart</policy>
    <center>yes</center>
  </placement>
  <theme>
    <name>PiDark</name>
    <titleLayout></titleLayout>
    <keepBorder>yes</keepBorder>
    <animateIconify>no</animateIconify>
    <font place="ActiveWindow">
      <name>Sans</name>
      <size>1</size>
      <weight>Bold</weight>
    </font>
    <font place="InactiveWindow">
      <name>Sans</name>
      <size>1</size>
      <weight>Bold</weight>
    </font>
  </theme>
  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names><name>1</name></names>
    <popupTime>0</popupTime>
  </desktops>
  <resize>
    <drawContents>yes</drawContents>
    <popupShow>Nonpixel</popupShow>
  </resize>
  <margins><top>0</top><bottom>0</bottom><left>0</left><right>0</right></margins>
  <keyboard>
    <keybind key="W-space">
      <action name="ShowMenu"><menu>root-menu</menu></action>
    </keybind>
    <keybind key="A-F2">
      <action name="ShowMenu"><menu>root-menu</menu></action>
    </keybind>
    <keybind key="W-e">
      <action name="Execute"><command>pcmanfm</command></action>
    </keybind>
    <keybind key="W-Return">
      <action name="Execute"><command>lxterminal</command></action>
    </keybind>
    <keybind key="Print">
      <action name="Execute"><command>flameshot gui</command></action>
    </keybind>
    <keybind key="A-F4">
      <action name="Close"/>
    </keybind>
    <keybind key="A-Tab">
      <action name="NextWindow"/>
    </keybind>
    <keybind key="W-d">
      <action name="ToggleShowDesktop"/>
    </keybind>
    <keybind key="W-l">
      <action name="Execute"><command>slock</command></action>
    </keybind>
    <!-- There is no titlebar to grab (see the PiDark theme / titleLayout
         above), so moving and resizing relies on: Alt+Left-drag / Alt+Right-
         drag anywhere on a window (bound under <mouse> below), or these two
         classic X11 keyboard fallbacks - press, move the mouse, click to
         drop. -->
    <keybind key="A-F7">
      <action name="Move"/>
    </keybind>
    <keybind key="A-F8">
      <action name="Resize"/>
    </keybind>
  </keyboard>
  <mouse>
    <context name="Frame">
      <mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="Middle" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="Right" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="A-Left" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="A-Left" action="Drag"><action name="Move"/></mousebind>
      <mousebind button="A-Right" action="Drag"><action name="Resize"/></mousebind>
    </context>
    <context name="Client">
      <!-- Without this, clicking inside a window's content area (e.g. to
           bring a terminal that's partially covered by another window
           back to front) does nothing: Openbox never raises/focuses on a
           plain click there unless this is bound explicitly. This also
           fixes the active/inactive border color never updating, since
           that follows Openbox's internal focus state, which was never
           actually changing on click before this. -->
      <mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="Middle" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="Right" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
    </context>
    <context name="Root">
      <mousebind button="Right" action="Press">
        <action name="ShowMenu"><menu>root-menu</menu></action>
      </mousebind>
    </context>
  </mouse>
  <menu>
    <menu id="root-menu" label="Applications">
      <item label="LXTerminal"><action name="Execute"><command>lxterminal</command></action></item>
      <item label="File Manager"><action name="Execute"><command>pcmanfm</command></action></item>
      <item label="Web Browser (vimb)"><action name="Execute"><command>vimb</command></action></item>
      <separator/>
      <item label="Mousepad"><action name="Execute"><command>mousepad</command></action></item>
      <item label="Geany"><action name="Execute"><command>geany</command></action></item>
      <separator/>
      <item label="Image Viewer"><action name="Execute"><command>lximage-qt</command></action></item>
      <item label="PDF Viewer"><action name="Execute"><command>qpdfview</command></action></item>
      <item label="Screenshot (Flameshot)"><action name="Execute"><command>flameshot gui</command></action></item>
      <separator/>
      <item label="Pi-Apps"><action name="Execute"><command>${TARGET_HOME}/pi-apps/gui</command></action></item>
      <item label="Raspberry Pi Configuration"><action name="Execute"><command>lxterminal -e sudo raspi-config</command></action></item>
      <separator/>
      <item label="Lock Screen"><action name="Execute"><command>slock</command></action></item>
      <item label="Log Out"><action name="Execute"><command>lxsession-logout</command></action></item>
      <separator/>
      <item label="Reconfigure Openbox"><action name="Reconfigure"/></item>
      <item label="Exit Openbox"><action name="Exit"><prompt>yes</prompt></action></item>
    </menu>
  </menu>
  <applications>
    <application name="*" class="*">
      <decor>yes</decor>
      <maximized>no</maximized>
    </application>
  </applications>
</openbox_config>
EOF

# ---------------------------------------------------------------------------
# 11. The LXDE-pi session: lxsession config + autostart
#
# This is the standard Raspberry Pi LXDE session, not a substitute: it
# starts lxpanel-pi (the real panel, with its normal network/volume/
# battery/power/updater/eject plugins) and 'pcmanfm --desktop' (which
# draws the desktop background and icons) - nothing more. There is no
# compositor, no second panel, no notification daemon and no separate
# launcher; that matches a standard LXDE install, and each of those
# processes not started is memory not used.
#
# /etc/xdg/lxsession/<profile>/autostart is blanked because lxsession
# merges the system-wide autostart file with the per-user one - leaving
# the system default in place would start lxpanel and pcmanfm twice.
# ---------------------------------------------------------------------------
print_status "Writing the LXDE-pi session configuration..."
sudo mkdir -p "/etc/xdg/lxsession/${LXDE_PROFILE}"
sudo tee "/etc/xdg/lxsession/${LXDE_PROFILE}/autostart" >/dev/null <<EOF
# Intentionally empty - see ~/.config/lxsession/${LXDE_PROFILE}/autostart.
EOF

mkdir -p "$TARGET_HOME/.config/lxsession/${LXDE_PROFILE}"

# A polkit authentication agent is what shows the GUI password prompt for
# privileged actions (e.g. a WPA passphrase change via NetworkManager).
# rpd-common depends on mate-polkit-bin for this; the [Session] key below
# is lxsession's own, standard way to launch whichever session's agent -
# tried in order in case the exact install path differs by release.
cat > "$TARGET_HOME/.local/bin/polkit-agent.sh" <<'EOF'
#!/bin/sh
for AGENT in /usr/lib/mate-polkit/polkit-mate-authentication-agent-1 \
             /usr/libexec/polkit-mate-authentication-agent-1 \
             /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 \
             /usr/libexec/polkit-gnome-authentication-agent-1 \
             /usr/bin/lxpolkit; do
    if [ -x "$AGENT" ]; then exec "$AGENT"; fi
done
exit 0
EOF
chmod +x "$TARGET_HOME/.local/bin/polkit-agent.sh"

cat > "$TARGET_HOME/.config/lxsession/${LXDE_PROFILE}/desktop.conf" <<EOF
[Session]
window_manager=openbox
disable_autostart=no
polkit/command=${TARGET_HOME}/.local/bin/polkit-agent.sh
clipboard/command=/bin/true
keyring/command=/bin/true
xsettings_manager/command=build-in
proxy_manager/command=build-in
quit_manager/command=lxsession-logout
lock_manager/command=slock
terminal_manager/command=lxterminal

[GTK]
sNet/ThemeName=Adwaita
sNet/IconThemeName=Numix-Circle
sGtk/FontName=${NERD_FONT_DISPLAY} ${UI_FONT_SIZE}
sGtk/CursorThemeName=Adwaita
iGtk/CursorThemeSize=24
iGtk/ToolbarStyle=3
iGtk/ButtonImages=0
iGtk/MenuImages=1
iNet/EnableEventSounds=0
iNet/EnableInputFeedbackSounds=0
iXft/Antialias=1
iXft/Hinting=1
sXft/HintStyle=hintslight
sXft/RGBA=rgb
EOF

cat > "$TARGET_HOME/.config/lxsession/${LXDE_PROFILE}/autostart" <<EOF
@lxpanel --profile ${LXDE_PROFILE}
@pcmanfm --desktop --profile ${LXDE_PROFILE}
EOF

# ---------------------------------------------------------------------------
# 12. pcmanfm: desktop background color + file manager preferences
#
# pcmanfm --desktop (started above) is what draws the desktop background
# and icons in LXDE - this is where the exact R:56 G:60 B:72 color is set,
# rather than xsetroot, since pcmanfm repaints over anything xsetroot draws.
# ---------------------------------------------------------------------------
print_status "Configuring the pcmanfm desktop (background color R:56 G:60 B:72)..."
mkdir -p "$TARGET_HOME/.config/pcmanfm/${LXDE_PROFILE}"
cat > "$TARGET_HOME/.config/pcmanfm/${LXDE_PROFILE}/desktop-items-0.conf" <<EOF
[*]
wallpaper_mode=color
wallpaper_common=1
wallpaper=
desktop_bg=${DESKTOP_BG}
desktop_fg=${UI_FG}
desktop_shadow=${DESKTOP_BG}
desktop_font=${NERD_FONT_DISPLAY} ${UI_FONT_SIZE}
show_wm_menu=0
sort=mtime;ascending;
show_documents=0
show_trash=1
show_mounts=1
EOF

mkdir -p "$TARGET_HOME/.config/pcmanfm/default"
cat > "$TARGET_HOME/.config/pcmanfm/default/pcmanfm.conf" <<EOF
[ui]
always_show_tabs=0
max_tab_chars=32
win_width=900
win_height=600
show_menu_bar=0

[volume]
mount_on_startup=1
mount_removable=1
autorun=0
EOF

# ---------------------------------------------------------------------------
# 13. LXTerminal
#
# Colors are written as rgb(r,g,b), the format lxterminal itself writes;
# the palette is the standard "Linux" 16-color set on the same dark
# background as the rest of the desktop.
# ---------------------------------------------------------------------------
print_status "Writing LXTerminal configuration..."
mkdir -p "$TARGET_HOME/.config/lxterminal"
cat > "$TARGET_HOME/.config/lxterminal/lxterminal.conf" <<EOF
[general]
fontname=${NERD_FONT_MONO} ${UI_FONT_SIZE}
selchars=-A-Za-z0-9,./?%&#:_
scrollback=2000
bgcolor=rgb(36,38,46)
fgcolor=rgb(230,230,230)
palette_color_0=rgb(27,29,36)
palette_color_1=rgb(192,57,43)
palette_color_2=rgb(106,153,85)
palette_color_3=rgb(245,212,66)
palette_color_4=rgb(76,123,196)
palette_color_5=rgb(158,110,190)
palette_color_6=rgb(86,182,194)
palette_color_7=rgb(230,230,230)
palette_color_8=rgb(90,94,108)
palette_color_9=rgb(224,108,97)
palette_color_10=rgb(152,195,121)
palette_color_11=rgb(229,192,123)
palette_color_12=rgb(97,175,239)
palette_color_13=rgb(198,120,221)
palette_color_14=rgb(134,214,220)
palette_color_15=rgb(255,255,255)
disallowbold=false
cursorblinks=false
cursorunderline=false
audiblebell=false
tabpos=top
geometry_columns=100
geometry_rows=30
hidescrollbar=true
hidemenubar=true
hideclosebutton=true
hidepointer=false
disablef10=false
disablealt=false
scrollonoutput=false
scrollonkey=true
EOF

# ---------------------------------------------------------------------------
# 14. vimb (dark)
# ---------------------------------------------------------------------------
print_status "Writing vimb configuration..."
mkdir -p "$TARGET_HOME/.config/vimb"
cat > "$TARGET_HOME/.config/vimb/config" <<EOF
set default-fg = ${UI_FG}
set default-bg = #24262E
set status-color-bg = ${MENU_BG}
set status-color-fg = ${UI_FG}
set input-color-bg = ${MENU_BG}
set input-color-fg = ${UI_FG}
set completion-bg-normal = #24262E
set completion-fg-normal = ${UI_FG}
set completion-bg-active = ${ACCENT}
set completion-fg-active = #FFFFFF
set home-page = about:blank
EOF

# ---------------------------------------------------------------------------
# 15. GTK apps (LXTerminal, PCManFM, Mousepad, Geany, vimb, lxpanel):
#     dark preference + icon theme + a menu-popup background close to the
#     requested "something like R:38 G:38 B:38".
# ---------------------------------------------------------------------------
print_status "Configuring GTK dark preference and Numix-Circle icon theme..."
mkdir -p "$TARGET_HOME/.config/gtk-3.0"
cat > "$TARGET_HOME/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita
gtk-icon-theme-name=Numix-Circle
gtk-font-name=${NERD_FONT_DISPLAY} ${UI_FONT_SIZE}
gtk-cursor-theme-size=24
EOF

# A small CSS override so the GTK menu popups (lxpanel's Applications menu
# in particular) land on the exact requested color, rather than whatever
# shade Adwaita-dark's own menu background happens to be.
cat > "$TARGET_HOME/.config/gtk-3.0/gtk.css" <<EOF
menu, .menu, popover.menu, popover.background {
    background-color: ${MENU_BG};
}
EOF

cat > "$TARGET_HOME/.gtkrc-2.0" <<EOF
gtk-theme-name="Adwaita-dark"
gtk-icon-theme-name="Numix-Circle"
gtk-font-name="${NERD_FONT_DISPLAY} ${UI_FONT_SIZE}"
EOF

# ---------------------------------------------------------------------------
# 16. Kvantum (Qt apps: qpdfview, lximage-qt, flameshot)
# ---------------------------------------------------------------------------
print_status "Applying Kvantum-Dark to Qt apps (qt5ct/qt6ct + Kvantum)..."
mkdir -p "$TARGET_HOME/.config/Kvantum"
cat > "$TARGET_HOME/.config/Kvantum/kvantum.kvconfig" <<'EOF'
[General]
theme=KvantumDark
EOF

mkdir -p "$TARGET_HOME/.config/qt5ct" "$TARGET_HOME/.config/qt6ct"
for QTCONF in "$TARGET_HOME/.config/qt5ct/qt5ct.conf" "$TARGET_HOME/.config/qt6ct/qt6ct.conf"; do
cat > "$QTCONF" <<EOF
[Appearance]
style=kvantum
icon_theme=Numix-Circle
[Fonts]
fixed="${NERD_FONT_MONO},${UI_FONT_SIZE},-1,5,50,0,0,0,0,0"
general="${NERD_FONT_DISPLAY},${UI_FONT_SIZE},-1,5,50,0,0,0,0,0"
EOF
done

# Make Qt apps actually use qt5ct/qt6ct + Kvantum system-wide for this user.
if ! grep -q "QT_QPA_PLATFORMTHEME" "$TARGET_HOME/.xprofile" 2>/dev/null; then
cat >> "$TARGET_HOME/.xprofile" <<'EOF'
export QT_QPA_PLATFORMTHEME=qt5ct
export QT_STYLE_OVERRIDE=kvantum
EOF
fi
chmod +x "$TARGET_HOME/.xprofile"

# ---------------------------------------------------------------------------
# 17. flameshot theme
# ---------------------------------------------------------------------------
print_status "Setting flameshot to a dark UI..."
mkdir -p "$TARGET_HOME/.config/flameshot"
cat > "$TARGET_HOME/.config/flameshot/flameshot.ini" <<EOF
[General]
uiColor=${ACCENT}
contrastUiColor=#2B2E38
drawColor=#F5D442
savePath=${TARGET_HOME}/Pictures
showStartupLaunchMessage=false
EOF

# ---------------------------------------------------------------------------
# 18. bashrc: PATH, fastfetch, Oh My Posh
# ---------------------------------------------------------------------------
print_status "Updating .bashrc (PATH, Oh My Posh prompt, fastfetch banner)..."
touch "$TARGET_HOME/.bashrc"

if ! grep -qF 'export PATH=$PATH:$HOME/.local/bin' "$TARGET_HOME/.bashrc"; then
    echo 'export PATH=$PATH:$HOME/.local/bin' >> "$TARGET_HOME/.bashrc"
fi

if ! grep -q 'oh-my-posh init bash' "$TARGET_HOME/.bashrc"; then
    cat >> "$TARGET_HOME/.bashrc" <<'EOF'

# Prompt. Oh My Posh with its built-in default theme; falls back to
# Starship (also installed, also default theme) if the binary is missing.
# To use Starship instead, comment the oh-my-posh branch out.
if command -v oh-my-posh >/dev/null 2>&1; then
    eval "$(oh-my-posh init bash)"
elif command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
EOF
fi

if ! grep -q 'fastfetch' "$TARGET_HOME/.bashrc"; then
    cat >> "$TARGET_HOME/.bashrc" <<'EOF'

# Show system info banner on interactive login shells only
case $- in
    *i*) command -v fastfetch >/dev/null 2>&1 && fastfetch ;;
esac
EOF
fi

# ---------------------------------------------------------------------------
# 19. .xinitrc - start the standard LXDE-pi session
#
# lxsession is the LXDE session manager; -s/-e name the session so it reads
# ~/.config/lxsession/LXDE-pi/{desktop.conf,autostart} and exports
# XDG_CURRENT_DESKTOP. It starts Openbox itself (window_manager=openbox).
# This is exactly the invocation stock Raspberry Pi OS's own startlxde-pi
# script uses. If lxsession is somehow missing, fall back to a bare
# openbox-session so the machine still comes up with a usable desktop.
# ---------------------------------------------------------------------------
print_status "Writing .xinitrc..."
cat > "$TARGET_HOME/.xinitrc" <<EOF
#!/bin/sh
[ -f "\$HOME/.xprofile" ] && . "\$HOME/.xprofile"
xset -dpms
xset s off
xset s noblank
# 1920x1080 is also pinned in /etc/X11/xorg.conf.d/98-resolution.conf; this
# is the runtime belt-and-braces for outputs that report a different
# preferred mode over EDID.
xrandr --output "\$(xrandr | awk '/ connected/{print \$1; exit}')" --mode 1920x1080 2>/dev/null || true

if command -v lxsession >/dev/null 2>&1; then
    exec lxsession -s ${LXDE_PROFILE} -e LXDE
fi
exec openbox-session
EOF
chmod +x "$TARGET_HOME/.xinitrc"

# ---------------------------------------------------------------------------
# 20. Autologin on tty1 + auto-startx (no display manager -> smaller footprint)
# ---------------------------------------------------------------------------
print_status "Configuring console autologin + auto-startx on tty1..."
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${TARGET_USER} --noclear %I \$TERM
EOF
sudo systemctl daemon-reload

if [ ! -f "$TARGET_HOME/.bash_profile" ]; then
cat > "$TARGET_HOME/.bash_profile" <<'EOF'
# Load the normal interactive shell config (PATH, Oh My Posh, fastfetch, ...)
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
EOF
fi

if ! grep -q 'exec startx' "$TARGET_HOME/.bash_profile" 2>/dev/null; then
cat >> "$TARGET_HOME/.bash_profile" <<'EOF'

# Auto-start the GUI on the first virtual console only
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi
EOF
fi

# ---------------------------------------------------------------------------
# 21. Pi-Apps (64-bit) + post-install app installs
# ---------------------------------------------------------------------------
print_status "Installing Pi-Apps..."
if [ ! -d "$TARGET_HOME/pi-apps" ]; then
    # Guarded explicitly: if the Pi-Apps installer itself fails (network
    # hiccup, unsupported arch, etc.) it must not abort the rest of this
    # script via set -e/pipefail - everything already configured above
    # (X11, LXDE, theming, dev tools, dropbear, ...) is still valuable
    # even if Pi-Apps can't be installed.
    if ! wget -qO- https://raw.githubusercontent.com/Botspot/pi-apps/master/install | bash; then
        print_error "Pi-Apps installer failed (see output above). Skipping Min / Geany Dark Mode install."
        print_error "You can retry manually later with: wget -qO- https://raw.githubusercontent.com/Botspot/pi-apps/master/install | bash"
    fi
else
    print_warning "Pi-Apps already present at $TARGET_HOME/pi-apps, skipping installer."
fi

if [ -x "$TARGET_HOME/pi-apps/manage" ]; then
    print_status "Installing Pi-Apps package: Min..."
    "$TARGET_HOME/pi-apps/manage" install Min || print_warning "Pi-Apps 'Min' install reported an error; check ~/pi-apps/logs."

    print_status "Installing Pi-Apps package: Geany Dark Mode..."
    "$TARGET_HOME/pi-apps/manage" install "Geany Dark Mode" || print_warning "Pi-Apps 'Geany Dark Mode' install reported an error; check ~/pi-apps/logs."
else
    print_error "Pi-Apps manage script not found; skipping Min / Geany Dark Mode install."
fi

# ---------------------------------------------------------------------------
# 22. Ownership / permissions cleanup
# ---------------------------------------------------------------------------
print_status "Fixing file ownership..."
sudo chown -R "${TARGET_USER}:${TARGET_GROUP}" "$TARGET_HOME"

xdg-user-dirs-update 2>/dev/null || true

# ---------------------------------------------------------------------------
# 23. Done
# ---------------------------------------------------------------------------
print_status "-----------------------------------------------------------"
print_status "Installation complete."
print_status "Reboot to start the graphical session automatically:"
print_status "    sudo reboot"
print_status ""
print_status "Notes:"
print_status " * dropbear is now your SSH server on port 22 (openssh-server was disabled if present)."
print_status " * This is the standard LXDE-pi session: lxsession + Openbox + lxpanel-pi + pcmanfm,"
print_status "   started from ~/.xinitrc. lightdm was installed by rpd-x-core and disabled again -"
print_status "   'sudo systemctl enable lightdm && sudo systemctl set-default graphical.target'"
print_status "   restores it if you want a login greeter."
print_status " * No compositor, second panel, or notification daemon is installed - lxpanel-pi's"
print_status "   own network/volume/battery/power/updater/eject plugins are the standard ones."
print_status " * Kvantum-Dark is applied to Qt apps (qpdfview, lximage-qt, flameshot) via qt5ct/qt6ct."
print_status "   Everything else is GTK, themed dark via lxsession + a gtk-3.0 settings/css override."
print_status " * Right-click the desktop, or Super+Space / Alt+F2, opens Openbox's own app menu -"
print_status "   that is where the R:38 G:38 B:38 background is applied exactly."
print_status " * Super+Return opens LXTerminal, Super+E opens the file manager, Super+L locks the screen."
print_status " * Oh My Posh drives the bash prompt; Starship is installed as an alternative"
print_status "   (swap the branches in the prompt block at the end of ~/.bashrc)."
print_status "-----------------------------------------------------------"
