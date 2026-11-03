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
- Three kernels. Default **Live system (amd64)** = Debian trixie-backports kernel + firmware + Mesa (newest hardware).
  Also listed as **Live system, kernel <version>**: Debian 6.12 LTS (fallback) and `*-surface`
  ([linux-surface](https://github.com/linux-surface/linux-surface): Surface keyboard/trackpad/touch).
  Both Debian kernels boot with Secure Boot on; linux-surface needs its key enrolled once (below) or Secure Boot off. Installed systems keep all
  three; GRUB defaults to linux-surface on Microsoft hardware, newest Debian kernel elsewhere
  (`/etc/default/grub.d/kernel-default.cfg`).
- ISO is ~3.4 GB, over the 2 GiB release limit, so it is a workflow artifact (kept 7 days):
  `gh run download -n debian-13-xfce-live-amd64-iso`
- Write to USB (macOS; use `/bin/dd`, GNU dd rejects `4m`):
  `diskutil unmountDisk /dev/diskN && sudo /bin/dd if=debian-13-xfce-live-amd64.iso of=/dev/rdiskN bs=4m status=progress`
- Local build: `docker run --rm --privileged -v "$PWD":/w -w /w -e AUTHORIZED_KEYS="$(cat ~/.ssh/id_rsa.pub)" debian:trixie bash build-live-iso.sh`
- **Surface with Secure Boot on** (one-time per machine): boot the default entry and wait ~1 min; the linux-surface
  key is queued automatically (`surface-mok.service`). Hold power to turn off, power on: shim shows MokManager
  (blue screen) → Enroll MOK → Continue → Yes → password `surface` → Reboot. Then pick
  **Live system, kernel …-surface** (until the key is enrolled it fails with `bad shim signature`). Verified on a
  Surface Book 3: keyboard, trackpad and touch work. (Or simply turn Secure Boot off in the Surface UEFI: hold Volume Up at power on.)
