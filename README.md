# JOS — Jonathan’s Operating System

## Where JOS fits (JOG vs JOS)

| Repo | What it is |
|---|---|
| **[jos](https://github.com/splippers/jos)** (this repo) | The **client runtime**: the Secure Boot-compatible replacement for FOG's FOS that runs on the machine being imaged. Initrd build, GRUB menu generator, local-boot fallback, parity checklist. Works with any FOG server. |
| [jog](https://github.com/splippers/jog) | The **imaging laptop**: Ubuntu autoinstall, FOG install, isolated DHCP/TFTP, kiosk. It serves JOS to clients. |
| [jog-jos](https://github.com/splippers/jog-jos) | The **integration repo**: pins `jog` and `jos` together at known-good commits, with the combined docs and end-to-end tests. |

Everything in this repo runs on, or builds for, the *client*. Nothing here installs or configures a server.

| Path | Purpose |
|---|---|
| `build/build-from-fos.sh` | Builds the initrd from the pinned FOS userland (`build/out/initrd.img`). |
| `build/jos-localboot.sh` | "Boot from local disk" fallback: creates UEFI boot entries from local ESPs, then reboots. |
| `build/jos-fogmenu.sh` | Console versions of the FOG menu actions that stock FOG draws in iPXE: Deploy Image (login, choose image), Join Multicast Session, Update Product Key. Calls the same `boot.php` endpoint. |
| `scripts/jos-stage-boot.sh` | Stages shim, GRUB, signed kernel, initrd, modules and the GRUB menu into a TFTP root. Run as root on the server. |
| `scripts/test-secureboot-vm.sh` | Boots the staged chain in a Secure Boot VM. |
| `initrd/` | Retired shell client, kept for reference. |
A Secure-Boot-Compatible Imaging Runtime for FOG

Type: Infrastructure  
Intent: Pillar (credibility / real-world systems)  
Audience: Sysadmins / IT Operations

--------------------------------------------------

OVERVIEW

> **Current design (2026-10-25):** JOS is the unmodified FOS userland running under the Canonical-signed
> kernel, built by `build/build-from-fos.sh`. FOS's own scripts speak the FOG protocol (`web=` +
> `boottype=usb`, then `hostgetkey.php` / `hostinfo.php`), so no FOG API tokens or custom client code are
> involved. The shell implementation described below (`initrd/`, REST API based) is **legacy** and kept only
> for reference until the FOS-based path is proven on hardware.

JOS is a modern, Ubuntu-based replacement for FOG’s legacy FOS imaging environment, designed specifically for contemporary UEFI and Secure Boot deployments.

It provides a zero-touch, API-driven imaging runtime that integrates cleanly with existing FOG infrastructure while addressing long-standing pain points in PXE booting, automation, and operational safety.

--------------------------------------------------

WHY JOS EXISTS

FOG’s FOS environment remains functional, but struggles with:

- Secure Boot requirements
- Modern UEFI hardware
- Version-fragile scripts
- Accidental destructive operations by technicians

JOS exists to solve these problems without replacing FOG itself.

--------------------------------------------------

CORE PRINCIPLES

- FOG-native: uses the FOG REST API rather than brittle screen-scraping
- Zero-touch: no technician interaction required after PXE selection
- Safe by default: destructive disk writes must be explicitly enabled
- Modern boot chain: Ubuntu-based userspace compatible with Secure Boot
- Operationally boring: predictable, auditable, repeatable behaviour

--------------------------------------------------

KEY CAPABILITIES

SECURE BOOT COMPATIBLE RUNTIME
- Ubuntu-based initrd and userspace
- Designed for modern UEFI systems
- Coexists with existing PXE and iPXE flows

DHCP NEXT-SERVER AUTO-DISCOVERY
- Automatically discovers the FOG server via DHCP siaddr
- Removes manual server selection
- Reduces technician error and deployment friction

REST-DRIVEN TASK EXECUTION
- Registers and inventories hosts via the FOG API
- Polls and executes deploy or capture tasks
- Adapts automatically to FOG API version differences

EXPLICIT DESTRUCTIVE-ACTION GATING
- Disk writes are disabled by default
- Imaging requires an explicit allow flag
- Prevents accidental wipes and unsafe execution

--------------------------------------------------

IMAGING MODES

UNICAST IMAGING
- FOS-style deployment workflow
- Uses partclone and sfdisk
- Explicitly gated destructive actions

MULTICAST IMAGING
- Automatic task creation and session joining
- Built-in watchdog for stalled transfers
- Safe reboot on repeated low-throughput detection

--------------------------------------------------

TECHNICIAN WORKFLOW

1. Power on target system
2. Press F12
3. Select Boot from IPv4
4. Walk away

JOS will:
- Acquire DHCP configuration
- Discover the FOG server automatically
- Register or update the host
- Upload inventory
- Wait for a queued task
- Execute imaging without further interaction

--------------------------------------------------

REPOSITORY STRUCTURE

build/     - build scripts for initrd and runtime tooling  
initrd/    - runtime filesystem and boot logic  
config/    - reference PXE and iPXE configuration fragments  
docs/      - architecture, boot flow, and operational notes  

Generated binaries are produced during build and are not committed.

--------------------------------------------------

STATUS

Active development.

This project is functional, evolving, and intended for real-world deployment in controlled environments. Contributions, issues, and discussion are welcome.

==================================================

PROJECT TAGGING SYSTEM (APPLY TO ALL REPOSITORIES)

Each repository should declare three tags near the top of its README.

TAG AXIS 1: TYPE  
What kind of thing the project fundamentally is.

Allowed values:
- Simulation
- Infrastructure
- Game
- Tool
- Meta-System
- Learning
- Satire
- Experiment
- Archive

TAG AXIS 2: INTENT  
Why this project exists from the creator’s perspective.

Allowed values:
- Engine (funds or enables other projects)
- Pillar (credibility, seriousness, trust)
- Playground (experimentation and fun)
- Teaching Tool
- Portfolio Signal
- Legacy Idea

TAG AXIS 3: AUDIENCE  
Who the project is primarily for.

Allowed values:
- Self
- Developers
- Sysadmins
- Learners
- Founders
- Households
- Institutions
- General Public

--------------------------------------------------

EXAMPLE FAMILY GROUPINGS

Infrastructure / Ops Family
- JOS
  Type: Infrastructure | Intent: Pillar | Audience: Sysadmins
- PypeLyne
  Type: Infrastructure | Intent: Support | Audience: Developers

Simulation / Learning Family
- VNA
  Type: Simulation | Intent: Engine | Audience: Learners
- CEO-Simulator
  Type: Simulation | Intent: Legacy Idea | Audience: Founders

Domestic Gamification Family
- BoreDOOM
  Type: Game | Intent: Engine | Audience: Households
- ChoreWars
  Type: Meta-System | Intent: Engine | Audience: General Public
