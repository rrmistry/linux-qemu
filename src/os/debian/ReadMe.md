# Debian 13 XFCE qcow2 (Haven / QEMU)

Ready-to-boot Debian 13 desktop image, no cloud-init seed needed. Built by
`.github/workflows/debian-vm.yaml` (manual trigger: `gh workflow run debian-vm.yaml`).

- arm64: https://github.com/rrmistry/linux-qemu/releases/download/debian-13-vm/debian-13-xfce-arm64.qcow2
- amd64: https://github.com/rrmistry/linux-qemu/releases/download/debian-13-vm/debian-13-xfce-amd64.qcow2

Contents: XFCE (auto-login `debian` / `debian`), Firefox ESR, Neovim + [rrmistry.nvim](https://github.com/rrmistry/rrmistry.nvim),
rootless podman, git, Python, Node.js LTS. VS Code installs in the background on first boot (needs network).

Haven: import the URL above, pick the matching arch. The display is QEMU's own VNC, so no VNC server runs in the guest.
On arm64 under emulation (TCG), give the desktop ~5 min after boot to draw.

Plain QEMU (arm64):

```shell
qemu-system-aarch64 -M virt -cpu max -m 2048 -smp 2 -bios QEMU_EFI.fd \
  -drive file=debian-13-xfce-arm64.qcow2,if=virtio -device virtio-gpu-pci \
  -device qemu-xhci -device usb-kbd -device usb-tablet -nic user,model=virtio-net-pci
```

Local build (Linux, same arch as target): `sudo ./build-vm.sh`

# Debian 13 XFCE live USB ISO (amd64)

Boots a full XFCE desktop on any x86_64 PC (UEFI or BIOS), with an "Install Debian" (Calamares) icon to install to disk.
Built by `.github/workflows/debian-live-usb.yaml` (manual: `gh workflow run debian-live-usb.yaml`), boot-tested in CI.

- Live login `user` / `live`; ssh (password + keys from repo variable `LIVE_SSH_AUTHORIZED_KEYS`), x11vnc on localhost:5900
  (`ssh -L 5900:localhost:5900 user@<ip>`), Firefox ESR, Neovim + rrmistry.nvim, podman, dev tools, gparted, firmware.
- Two kernels in the boot menu: **Live system (amd64)** (default) is Debian's signed kernel and works with
  Secure Boot on, for any laptop. **Live system (surface)** is [linux-surface](https://github.com/linux-surface/linux-surface)
  (Surface keyboard/trackpad/touch) and needs Secure Boot off. Installed systems keep both; GRUB defaults to
  linux-surface on Microsoft hardware, Debian's kernel elsewhere (`/etc/default/grub.d/kernel-default.cfg`).
- ISO is ~2.2 GB, over the 2 GiB release limit, so it is a workflow artifact (kept 7 days):
  `gh run download -n debian-13-xfce-live-amd64-iso`
- Write to USB (macOS; use `/bin/dd`, GNU dd rejects `4m`):
  `diskutil unmountDisk /dev/diskN && sudo /bin/dd if=debian-13-xfce-live-amd64.iso of=/dev/rdiskN bs=4m status=progress`
- Local build: `docker run --rm --privileged -v "$PWD":/w -w /w -e AUTHORIZED_KEYS="$(cat ~/.ssh/id_rsa.pub)" debian:trixie bash build-live-iso.sh`
