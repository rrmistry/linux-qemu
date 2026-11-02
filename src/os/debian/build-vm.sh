#!/bin/bash
# Build a ready-to-boot Debian 13 XFCE qcow2 (for Haven / plain QEMU) from the official
# Debian generic cloud image. No cloud-init seed needed: user, desktop and network are baked in.
# Runs as root on a Linux host of the SAME arch (packages are installed via plain chroot).
#   sudo ARCH=arm64 ./build-vm.sh   ->  debian-13-xfce-arm64.qcow2
set -euxo pipefail

ARCH=${ARCH:-$(dpkg --print-architecture)}            # amd64 | arm64
OUT=${OUT:-debian-13-xfce-${ARCH}.qcow2}
DISK_SIZE=${DISK_SIZE:-32G}                            # virtual size; qcow2 file stays small
case $ARCH in amd64) CODE=linux-deb-x64 NVIM=x86_64 ;; arm64) CODE=linux-deb-arm64 NVIM=arm64 ;; esac

curl -fL -o base.qcow2 "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-${ARCH}.qcow2"
qemu-img resize base.qcow2 "$DISK_SIZE"

modprobe nbd max_part=16
qemu-nbd --discard=unmap -c /dev/nbd0 base.qcow2
trap 'umount -R /mnt/vm 2>/dev/null || true; qemu-nbd -d /dev/nbd0' EXIT
udevadm settle
growpart /dev/nbd0 1
e2fsck -fy /dev/nbd0p1 || true
resize2fs /dev/nbd0p1

mkdir -p /mnt/vm
mount /dev/nbd0p1 /mnt/vm
mount /dev/nbd0p15 /mnt/vm/boot/efi
for d in dev dev/pts proc sys; do mount --bind /$d /mnt/vm/$d; done
mv /mnt/vm/etc/resolv.conf /mnt/vm/etc/resolv.conf.orig 2>/dev/null || true
cp -L /etc/resolv.conf /mnt/vm/etc/resolv.conf
printf '#!/bin/sh\nexit 101\n' > /mnt/vm/usr/sbin/policy-rc.d   # don't start services in chroot
chmod +x /mnt/vm/usr/sbin/policy-rc.d

chroot /mnt/vm /bin/bash -euxo pipefail <<EOF
export DEBIAN_FRONTEND=noninteractive
# ponytail: no docs/man/translations - keeps the qcow2 under GitHub's 2 GiB release-asset cap
cat > /etc/dpkg/dpkg.cfg.d/01-slim <<'CFG'
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright
path-exclude=/usr/share/man/*
path-exclude=/usr/share/info/*
path-exclude=/usr/share/locale/*
path-include=/usr/share/locale/en*
path-include=/usr/share/locale/locale.alias
CFG
echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries   # CI mirrors occasionally reset
apt-get update
apt-get -y full-upgrade
apt-get install -y \
  xfce4 xfce4-goodies lightdm lightdm-gtk-greeter xserver-xorg \
  network-manager network-manager-applet openssh-server sudo firefox-esr
# Dev + container tools without "recommends" (skips buildah, compilers pulled by pip, ...)
apt-get install -y --no-install-recommends \
  podman uidmap slirp4netns passt fuse-overlayfs dbus-user-session \
  git curl wget jq vim tmux htop unzip zip build-essential \
  python3 python3-pip python3-venv pipx ripgrep fd-find

# Node.js latest LTS (bundles npm); Debian's npm drags in hundreds of node-* packages
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# Neovim latest release (Debian's is too old for AstroNvim)
curl -fL https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM}.tar.gz | tar xz -C /opt
ln -sf /opt/nvim-linux-${NVIM}/bin/nvim /usr/local/bin/nvim
nvim --version | head -1

# VS Code installs on first boot (1 GB installed: baking it in breaks the 2 GiB release cap).
# Its postinst adds Microsoft's apt repo so apt keeps it updated afterwards.
echo 'code code/add-microsoft-repo boolean true' | debconf-set-selections
cat > /etc/systemd/system/install-vscode.service <<'UNIT'
[Unit]
Description=Install latest VS Code (first boot)
Wants=network-online.target
After=network-online.target
ConditionPathExists=!/usr/bin/code
[Service]
Type=oneshot
Environment=DEBIAN_FRONTEND=noninteractive
ExecStart=/usr/bin/curl -fL --retry 5 -o /var/tmp/code.deb https://update.code.visualstudio.com/latest/${CODE}/stable
ExecStart=/usr/bin/apt-get install -y -o DPkg::Lock::Timeout=600 /var/tmp/code.deb
ExecStartPost=/bin/sh -c 'rm -f /var/tmp/code.deb; for t in /dev/ttyS0 /dev/ttyAMA0; do echo VSCODE-OK > \$t; done 2>/dev/null; true'
Restart=on-failure
RestartSec=60
TimeoutStartSec=infinity
[Install]
WantedBy=multi-user.target
UNIT
systemctl enable install-vscode

# Login: debian/debian, auto-login to XFCE. ponytail: fixed public password is OK only because
# Haven's QEMU uses user-mode net (nothing can connect in). Change it with passwd if exposed.
useradd -m -s /bin/bash -G sudo,users debian
echo debian:debian | chpasswd
grep -q '^debian:' /etc/subuid || usermod --add-subuids 100000-165535 --add-subgids 100000-165535 debian
mkdir -p /etc/lightdm/lightdm.conf.d
printf '[Seat:*]\nautologin-user=debian\n' > /etc/lightdm/lightdm.conf.d/50-autologin.conf
systemctl set-default graphical.target

# Neovim config (AstroNvim) with plugins pre-synced; mason LSPs/parsers install on first nvim launch
runuser -l debian -c 'git clone https://github.com/rrmistry/rrmistry.nvim ~/.config/nvim'
runuser -l debian -c 'timeout 900 nvim --headless "+Lazy! sync" +qa' || echo "WARN: Lazy sync failed"
sleep 10; pkill -u debian || true   # nvim leaves parser builds running on exit

# No seed disk in Haven: turn cloud-init off; NetworkManager does DHCP on any NIC
touch /etc/cloud/cloud-init.disabled
echo debian-vm > /etc/hostname
sed -i 's/^127.0.1.1.*//; \$a 127.0.1.1 debian-vm' /etc/hosts
# Cloud images ship without ssh host keys (cloud-init made them); make unique ones on first boot
mkdir -p /etc/systemd/system/ssh.service.d
printf '[Service]\nExecStartPre=\nExecStartPre=/usr/bin/ssh-keygen -A\nExecStartPre=/usr/sbin/sshd -t\n' \
  > /etc/systemd/system/ssh.service.d/hostkeys.conf
rm -f /etc/ssh/ssh_host_*

# Boot marker for CI: one line on the serial port once X is up
cat > /etc/systemd/system/boot-marker.service <<'UNIT'
[Unit]
Description=Print GRAPHICAL-OK on serial once Xorg runs (CI boot test)
After=display-manager.service
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for i in \$(seq 300); do pidof Xorg >/dev/null && break; sleep 1; done; for t in /dev/ttyS0 /dev/ttyAMA0; do echo GRAPHICAL-OK > \$t 2>/dev/null; done; true'
[Install]
WantedBy=graphical.target
UNIT
systemctl enable boot-marker NetworkManager

truncate -s 0 /etc/machine-id
# Purge old kernels: every INSTALLED linux-image-<ver> except the newest one in /boot
keep=\$(ls /boot/vmlinuz-* | sort -V | tail -1 | sed 's|.*/vmlinuz-||')
dpkg-query -W -f='\${db:Status-Abbrev} \${Package}\n' 'linux-image-[0-9]*' \\
  | awk -v keep="linux-image-\$keep" '/^ii/ && \$2 != keep {print \$2}' | xargs -r apt-get -y purge
ls /boot/vmlinuz-* && grep -q '^\s*linux' /boot/grub/grub.cfg   # fail the build if no bootable kernel
apt-get -y autoremove --purge
apt-get clean
dpkg-query -W -f='\${Installed-Size}\t\${Package}\n' | sort -n | tail -25
du -sh / --exclude=/proc --exclude=/sys --exclude=/dev 2>/dev/null || true
rm -rf /var/lib/apt/lists/*
EOF

rm /mnt/vm/usr/sbin/policy-rc.d
rm -f /mnt/vm/etc/resolv.conf
mv /mnt/vm/etc/resolv.conf.orig /mnt/vm/etc/resolv.conf 2>/dev/null || true
fstrim -v /mnt/vm
umount -R /mnt/vm
qemu-nbd -d /dev/nbd0
trap - EXIT

qemu-img convert -p -c -O qcow2 -o compression_type=zstd,cluster_size=2M base.qcow2 "$OUT"
rm base.qcow2
ls -lh "$OUT"
# GitHub release assets are capped at 2 GiB
[ "$(stat -c %s "$OUT")" -lt 2147483648 ] || { echo "image too big for a release asset"; exit 1; }
