# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository creates QEMU virtual machines for Linux distributions using cloud-init configuration. The primary focus is on Alpine Linux, with infrastructure for supporting additional distributions.

## Key Commands

### Development Environment Setup
```bash
# Install dependencies via devbox (recommended)
devbox shell

# Required packages: act (GitHub Actions runner), go-task (task runner), qemu
```

### Build and Test Commands
```bash
# Build and test Alpine VM using Task
task alpine-qemu-setup

# Test GitHub Actions workflows locally
task github-actions

# Build seed image manually 
cd src/os/alpine
mkisofs -output alpine-seed.img -volid CIDATA -joliet -rock user-data meta-data
```

### VM Management
```bash
# Create and run Alpine VM
cd src/os/alpine
./alpine-qemu-setup.sh

# Environment variables for customization:
# VM_NAME=my-vm DISK_SIZE=40G MEMORY=4096 CPUS=4 ./alpine-qemu-setup.sh
```

## Architecture

### Directory Structure
- `src/os/alpine/` - Alpine Linux VM configuration and scripts
- `src/os/debian/` - Debian 13 XFCE: qcow2 from the cloud image (`build-vm.sh`) and live USB ISO via live-build (`build-live-iso.sh`); see its ReadMe.md
- New distros: add `src/os/<distro>/` + a manual (`workflow_dispatch`) workflow with a QEMU boot test
- `.github/workflows/` - CI/CD pipeline for building and releasing seed images
- `.github/actions/qemu-build-and-test/` - Reusable action for QEMU VM testing

### Core Components

**VM Setup Script** (`alpine-qemu-setup.sh`):
- Downloads Alpine cloud images from official sources
- Configures QEMU with UEFI firmware support
- Handles cross-architecture compatibility (x86_64, aarch64, i686)
- Uses cloud-init for automated VM provisioning

**Cloud-init Configuration**:
- `user-data` - VM user configuration, packages, SSH setup
- `meta-data` - Instance metadata (hostname, instance-id)
- Packaged into ISO seed image for cloud-init consumption

**Task Automation** (`Taskfile.yml`):
- `alpine-qemu-setup` - Complete VM setup with cleanup
- `github-actions` - Local CI testing with act

### CI/CD Pipeline
The workflow builds seed images and tests VM creation for each supported OS. Artifacts are published as GitHub releases on version tags.

## Development Workflow

1. Modify cloud-init files (`user-data`, `meta-data`) for VM configuration changes
2. Update setup scripts for new features or OS support
3. Test locally with `task alpine-qemu-setup` 
4. Validate CI pipeline with `task github-actions`
5. Version releases trigger automatic builds and artifact publishing

## Configuration

**Environment Variables**:
- `VM_NAME` - VM instance name (default: alpine-vm)
- `DISK_SIZE` - Virtual disk size (default: 20G)
- `MEMORY` - RAM allocation in MB (default: 2048)
- `CPUS` - CPU core count (default: 2)
- `ARCH` - Target architecture (default: host architecture)
- `ALPINE_VERSION` - Alpine version to use (default: 3.21)

**Dependencies**:
- QEMU system emulation
- genisoimage/mkisofs for ISO creation
- curl for downloading images
- act for local GitHub Actions testing