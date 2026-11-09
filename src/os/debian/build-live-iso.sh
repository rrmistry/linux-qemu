set -euxo pipefail
# Debian 13 live ISO (amd64): GNOME (default, touch/2-in-1) + XFCE (light), Calamares "Install Debian" icon.
# Every boot entry exists twice: "GNOME: ..." (desktop=gnome -> GDM/Wayland) and "XFCE: ..." (desktop=xfce -> LightDM).
# Runs inside a privileged debian:trixie container, from any work dir:
#   docker run --rm --privileged -v "$PWD":/w -w /w \
#     -e AUTHORIZED_KEYS="$(cat ~/.ssh/id_rsa.pub)" debian:trixie bash build-live-iso.sh
# Output: ./live/*.iso.  Live login: user / live (ssh password login stays on).
apt-get update && apt-get install -y live-build curl
# live-build's GRUB default entry uses a bare glob (vmlinuz-*amd64): with two Debian kernels it would pick
# the first (6.12) and label it with the last flavour ("surface"). Pick the newest, like its syslinux code.
f=/usr/lib/live/build/binary_grub_cfg
perl -pi -e 's/\$\(basename chroot\/boot\/vmlinuz-\*\$\{DEFAULT_FLAVOUR\}\)/\$(basename "\$(ls -1 chroot\/boot\/vmlinuz-*\${DEFAULT_FLAVOUR} | sort -V | tail -n 1)")/; s/Live system \(\$\{_FLAVOUR\}/Live system (\${FLAVOUR_LIVE}/' $f
grep -q 'sort -V | tail -n 1' $f && ! grep -q 'Live system (${_FLAVOUR}' $f || { echo 'live-build patch failed'; exit 1; }
# live-build copies MokManager (mmx64.efi) next to shim only in its shim-only fallback. Ship it in the normal
# signed path too, so shim can run MokManager to enroll the linux-surface key (Secure Boot stays on).
f=/usr/lib/live/build/binary_grub-efi
cat > /tmp/mm.pl <<'PL'
my $n = 0;
while (<>) {
  print;
  if (!$n && index($_, '/grub-efi-temp/EFI/boot/boot\$efi_name.efi') >= 0) {
    print "\t\tcp -a \${_CHROOT_DIR}/usr/lib/shim/mm\\\$efi_name.efi.signed \${_CHROOT_DIR}/grub-efi-temp/EFI/boot/mm\\\$efi_name.efi\n"; $n = 1;
  }
}
PL
perl -i /tmp/mm.pl $f
[ "$(grep -c 'grub-efi-temp/EFI/boot/mm' $f)" -eq 2 ] || { echo 'live-build MokManager patch failed'; exit 1; }
mkdir -p live && cd live
lb config --distribution trixie \
  --archive-areas "main contrib non-free non-free-firmware" \
  --debian-installer none --binary-images iso-hybrid \
  --firmware-chroot true --firmware-binary false \
  --iso-volume DEBIAN13-LIVE --linux-flavours "amd64 surface" \
  --debootstrap-options "--include=ca-certificates" \
  --bootappend-live "boot=live components username=user hostname=debian-live console=ttyS0,115200 console=tty0"

# Auto-boot the default (live) entry after 5 s instead of waiting forever at the menu
mkdir -p config/bootloaders && cp -r /usr/share/live/build/bootloaders/. config/bootloaders/
echo 'set timeout=5' >> config/bootloaders/grub-pc/config.cfg
sed -i 's/^timeout 0/timeout 50/' config/bootloaders/isolinux/isolinux.cfg config/bootloaders/syslinux/syslinux.cfg

cat > config/package-lists/usb.list.chroot <<'EOF'
xfce4 xfce4-goodies lightdm lightdm-gtk-greeter xserver-xorg
gnome-core libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-gtk3
network-manager network-manager-applet openssh-server x11vnc sudo firefox-esr
calamares calamares-settings-debian
podman uidmap slirp4netns passt fuse-overlayfs dbus-user-session
git curl wget jq vim tmux htop unzip zip build-essential
python3 python3-pip python3-venv pipx ripgrep fd-find
gparted exfatprogs dosfstools debootstrap parted gdisk rsync
firmware-linux firmware-misc-nonfree firmware-iwlwifi firmware-realtek
firmware-atheros firmware-amd-graphics intel-microcode amd64-microcode
iptsd libwacom-surface iio-sensor-proxy bluez blueman alsa-utils usbutils
mokutil shim-helpers-amd64-signed
xserver-xorg-input-wacom onboard thermald
firmware-sof-signed firmware-intel-sound firmware-intel-graphics firmware-intel-misc firmware-mediatek
firmware-brcm80211 firmware-cirrus firmware-libertas firmware-nvidia-graphics firmware-ti-connectivity
EOF

# Kernels (all in one ISO; GRUB lists each as "Live system, kernel <version>"):
#  - default: Debian trixie-backports kernel + firmware + Mesa (newest hardware), Debian-signed: Secure Boot OK
#  - Debian 6.12 LTS (stable), Debian-signed: fallback if the newer kernel misbehaves
#  - linux-surface: Surface keyboard/trackpad (Debian lacks surface_aggregator_hub) + touch (IPTS); Secure Boot off
# Installed systems keep all three and pick the default per machine (kernel-default.cfg below).
echo 'deb http://deb.debian.org/debian trixie-backports main contrib non-free non-free-firmware' \
  | tee config/archives/backports.list.chroot > config/archives/backports.list.binary
curl -fsSL https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc \
  -o config/archives/linux-surface.key.chroot
cp config/archives/linux-surface.key.chroot config/archives/linux-surface.key.binary
echo 'deb [arch=amd64] https://pkg.surfacelinux.com/debian release main' \
  | tee config/archives/linux-surface.list.chroot > config/archives/linux-surface.list.binary

mkdir -p config/includes.chroot/etc/skel/.ssh \
         config/includes.chroot/etc/systemd/system
printf '%s\n' "${AUTHORIZED_KEYS:-}" > config/includes.chroot/etc/skel/.ssh/authorized_keys

mkdir -p config/includes.chroot/etc/default/grub.d
cat > config/includes.chroot/etc/default/grub.d/kernel-default.cfg <<'EOF'
# Installed system: Surface -> linux-surface kernel, anything else -> Debian's signed kernel (Secure Boot OK)
if grep -qs '^Microsoft' /sys/class/dmi/id/sys_vendor; then k='*-surface'; else k='*-amd64'; fi
GRUB_TOP_LEVEL=$(ls /boot/vmlinuz-$k 2>/dev/null | sort -V | tail -1)
EOF

# Surface + Secure Boot on: queue the linux-surface signing key (CN=linux-surface) for MokManager, no keyboard needed.
# Next boot, shim shows MokManager (blue screen; the Surface keyboard works there): Enroll MOK > Continue > Yes >
# password "surface" > Reboot. Then "Live system, kernel *-surface" boots with Secure Boot still on.
mkdir -p config/includes.chroot/usr/local/sbin
cat > config/includes.chroot/usr/local/sbin/surface-mok <<'EOF'
#!/bin/sh
cer=/usr/share/linux-surface-secureboot/surface.cer
grep -qs '^Microsoft' /sys/class/dmi/id/sys_vendor || exit 0
mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled' || exit 0
mokutil --test-key $cer | grep -qE 'already enrolled|enrollment request' && exit 0
printf 'surface\nsurface\n' | mokutil --import $cer || exit 0
echo MOK-QUEUED > /dev/ttyS0 2>/dev/null || true
EOF
chmod +x config/includes.chroot/usr/local/sbin/surface-mok
cat > config/includes.chroot/etc/systemd/system/surface-mok.service <<'EOF'
[Unit]
Description=Queue linux-surface Secure Boot key for MokManager (Microsoft hardware, Secure Boot on)
ConditionPathExists=/sys/firmware/efi
After=sys-firmware-efi-efivars.mount
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/surface-mok
[Install]
WantedBy=multi-user.target
EOF

# desktop= on the kernel command line picks the display manager (no desktop=: the default, GDM)
mkdir -p config/includes.chroot/usr/lib/systemd/system-generators config/includes.chroot/etc/lightdm/lightdm.conf.d
cat > config/includes.chroot/usr/lib/systemd/system-generators/desktop-select <<'EOF'
#!/bin/sh
case " $(cat /proc/cmdline) " in *" desktop=xfce "*) dm=lightdm;; *" desktop=gnome "*) dm=gdm;; *) exit 0;; esac
ln -sf /usr/lib/systemd/system/$dm.service "$2/display-manager.service"
EOF
chmod +x config/includes.chroot/usr/lib/systemd/system-generators/desktop-select
printf '[Seat:*]\nuser-session=xfce\nautologin-session=xfce\n' > config/includes.chroot/etc/lightdm/lightdm.conf.d/60-xfce.conf

# The GRUB/syslinux menus live-build generates, duplicated: GNOME entries first (default), then XFCE
cat > config/hooks/normal/9000-desktops.hook.binary <<'EOF'
#!/bin/sh
set -e
f=boot/grub/grub.cfg
awk '
function emit(d, D,  b) { b = blk; gsub(/menuentry "Live system/, "menuentry \"" D ": Live system", b)
  gsub(/boot=live/, "boot=live desktop=" d, b); if (d == "xfce") gsub(/ --hotkey=l/, "", b); printf "%s", b }
/^menuentry "Live system/ { if (done) exit 1; inb = 1 }
inb { blk = blk $0 "\n"; if ($0 ~ /^}/) inb = 0; next }
blk != "" && !done { emit("gnome", "GNOME"); emit("xfce", "XFCE"); done = 1 }
{ print }' $f > $f.new && mv $f.new $f
f=isolinux/live.cfg
{ sed -e 's/^label live-/label gnome-/' -e 's/Live system/GNOME: Live system/' -e 's/boot=live/boot=live desktop=gnome/' $f; echo
  sed -e '/menu default/d' -e 's/^label live-/label xfce-/' -e 's/Live system/XFCE: Live system/' -e 's/boot=live/boot=live desktop=xfce/' $f
} > $f.new && mv $f.new $f
grep 'menuentry "' boot/grub/grub.cfg; grep 'menu label' isolinux/live.cfg
g=$(grep -c 'desktop=gnome' boot/grub/grub.cfg); [ "$g" -eq 8 ] && [ "$(grep -c 'desktop=xfce' boot/grub/grub.cfg)" -eq 8 ]
grep -q 'desktop=gnome' isolinux/live.cfg && grep -q 'desktop=xfce' isolinux/live.cfg
EOF
chmod +x config/hooks/normal/9000-desktops.hook.binary

cat > config/includes.chroot/etc/systemd/system/x11vnc.service <<'EOF'
[Unit]
Description=x11vnc mirroring the XFCE desktop, localhost only (use: ssh -L 5900:localhost:5900)
After=display-manager.service
[Service]
ExecCondition=/bin/systemctl is-active -q lightdm
ExecStart=/usr/bin/x11vnc -display :0 -auth guess -localhost -nopw -forever -loop -shared -noxdamage
Restart=always
RestartSec=3
[Install]
WantedBy=graphical.target
EOF

cat > config/includes.chroot/etc/systemd/system/boot-marker.service <<'EOF'
[Unit]
Description=Print GRAPHICAL-OK on serial once Xorg/GNOME Shell runs (CI boot test)
After=display-manager.service
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for i in $(seq 300); do pidof Xorg gnome-shell >/dev/null && break; sleep 1; done; echo GRAPHICAL-OK > /dev/ttyS0; true'
[Install]
WantedBy=graphical.target
EOF

cat > config/hooks/normal/9000-usb.hook.chroot <<'EOF'
#!/bin/sh
set -e
chmod 700 /etc/skel/.ssh && chmod 600 /etc/skel/.ssh/authorized_keys
rm -f /etc/ssh/ssh_host_*          # never ship shared host keys; regenerated at boot
mkdir -p /etc/systemd/system/ssh.service.d
printf '[Service]\nExecStartPre=\nExecStartPre=/usr/bin/ssh-keygen -A\nExecStartPre=/usr/sbin/sshd -t\n' \
  > /etc/systemd/system/ssh.service.d/hostkeys.conf
systemctl enable x11vnc boot-marker ssh NetworkManager surface-mok
# linux-surface signing cert (from its MOK package; not installed: its postinst may try an interactive mokutil)
cd /tmp && apt-get download linux-surface-secureboot-mok && dpkg-deb -x linux-surface-secureboot-mok_*.deb /tmp/mok
install -D -m644 /tmp/mok/usr/share/linux-surface-secureboot/surface.cer /usr/share/linux-surface-secureboot/surface.cer
rm -rf /tmp/mok /tmp/linux-surface-secureboot-mok_*.deb; cd /
systemctl set-default graphical.target
# Default display manager GDM (GNOME); desktop-select switches to LightDM for desktop=xfce
test -e /usr/lib/systemd/system/gdm.service && test -e /usr/lib/systemd/system/lightdm.service
ln -sf /usr/lib/systemd/system/gdm.service /etc/systemd/system/display-manager.service
echo /usr/sbin/gdm3 > /etc/X11/default-display-manager
ls /usr/lib/live/config/ | tr '\n' ' '
# Backports kernel/firmware/Mesa on top of stable; keep the stable 6.12 kernel as a fallback boot entry
apt-mark manual $(dpkg -l 'linux-image-6.*-amd64' | awk '/^ii/{print $2}')
apt-get install -y -t trixie-backports linux-image-amd64 \
  $(dpkg -l 'firmware-*' 'mesa-*' libgl1-mesa-dri libglx-mesa0 libegl-mesa0 libgbm1 2>/dev/null | awk '/^ii/{print $2}')
ls /boot/vmlinuz-*; test "$(ls /boot/vmlinuz-*-amd64 | wc -l)" -eq 2   # stable 6.12 + backports
# linux-surface's kernel .deb doesn't depend on initramfs-tools, so it can install before it and get no initrd
for k in /boot/vmlinuz-*; do v=${k#/boot/vmlinuz-}; [ -e /boot/initrd.img-$v ] || update-initramfs -c -k "$v"; done

# Neovim latest release + rrmistry.nvim (AstroNvim) for the live user, plugins pre-synced
curl -fL https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz | tar xz -C /opt
ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
git clone https://github.com/rrmistry/rrmistry.nvim /etc/skel/.config/nvim
HOME=/etc/skel timeout 900 nvim --headless "+Lazy! sync" +qa || echo "WARN: Lazy sync failed"
sleep 10; pkill -f tree-sitter || true; sleep 2   # nvim leaves parser builds running on exit
rm -rf /etc/skel/.cache || true
EOF
chmod +x config/hooks/normal/9000-usb.hook.chroot

lb build
ls -lh *.iso
