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
