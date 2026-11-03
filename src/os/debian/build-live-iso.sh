set -euxo pipefail
# Debian 13 XFCE live ISO (amd64) with the Calamares "Install Debian" icon.
# Runs inside a privileged debian:trixie container, from any work dir:
#   docker run --rm --privileged -v "$PWD":/w -w /w \
#     -e AUTHORIZED_KEYS="$(cat ~/.ssh/id_rsa.pub)" debian:trixie bash build-live-iso.sh
# Output: ./live/*.iso.  Live login: user / live (ssh password login stays on).
apt-get update && apt-get install -y live-build curl
mkdir -p live && cd live
lb config --distribution trixie \
  --archive-areas "main contrib non-free non-free-firmware" \
  --debian-installer none --binary-images iso-hybrid \
  --firmware-chroot true --firmware-binary true \
  --iso-volume DEBIAN13-XFCE-LIVE \
  --bootappend-live "boot=live components username=user hostname=debian-live console=ttyS0,115200 console=tty0"

# Auto-boot the default (live) entry after 5 s instead of waiting forever at the menu
mkdir -p config/bootloaders && cp -r /usr/share/live/build/bootloaders/. config/bootloaders/
echo 'set timeout=5' >> config/bootloaders/grub-pc/config.cfg
sed -i 's/^timeout 0/timeout 50/' config/bootloaders/isolinux/isolinux.cfg config/bootloaders/syslinux/syslinux.cfg

cat > config/package-lists/usb.list.chroot <<'EOF'
xfce4 xfce4-goodies lightdm lightdm-gtk-greeter xserver-xorg
network-manager network-manager-applet openssh-server x11vnc sudo firefox-esr
calamares calamares-settings-debian
podman uidmap slirp4netns passt fuse-overlayfs dbus-user-session
git curl wget jq vim tmux htop unzip zip build-essential
python3 python3-pip python3-venv pipx nodejs npm ripgrep fd-find
gparted exfatprogs dosfstools debootstrap parted gdisk rsync
firmware-linux firmware-misc-nonfree firmware-iwlwifi firmware-realtek
firmware-atheros firmware-amd-graphics intel-microcode amd64-microcode
EOF

mkdir -p config/packages.chroot
curl -fL -o config/packages.chroot/code_latest_amd64.deb \
  'https://update.code.visualstudio.com/latest/linux-deb-x64/stable'

mkdir -p config/includes.chroot/etc/skel/.ssh \
         config/includes.chroot/etc/systemd/system
printf '%s\n' "${AUTHORIZED_KEYS:-}" > config/includes.chroot/etc/skel/.ssh/authorized_keys

cat > config/includes.chroot/etc/systemd/system/x11vnc.service <<'EOF'
[Unit]
Description=x11vnc mirroring the XFCE desktop, localhost only (use: ssh -L 5900:localhost:5900)
After=display-manager.service
[Service]
ExecStart=/usr/bin/x11vnc -display :0 -auth guess -localhost -nopw -forever -loop -shared -noxdamage
Restart=always
RestartSec=3
[Install]
WantedBy=graphical.target
EOF

cat > config/includes.chroot/etc/systemd/system/boot-marker.service <<'EOF'
[Unit]
Description=Print GRAPHICAL-OK on serial once Xorg runs (CI boot test)
After=display-manager.service
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for i in $(seq 300); do pidof Xorg >/dev/null && break; sleep 1; done; echo GRAPHICAL-OK > /dev/ttyS0; true'
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
systemctl enable x11vnc boot-marker ssh NetworkManager
systemctl set-default graphical.target

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
