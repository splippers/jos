# JOS — Jonathan's OS

**A Secure Boot imaging runtime for FOG.**

JOS is the client side of the JOG appliance. It boots over PXE, runs the FOG imaging workflow, and
then either images the machine or hands it back to the local disk. It is not a FOG fork: the default
build runs the stock FOS userland under the Canonical-signed Ubuntu kernel, so Secure Boot works
without enrolling a per-site key.

```text
firmware PXE → shimx64.efi → grubnetx64 → signed vmlinuz → JOS initrd → FOS userland → FOG task
```

## The three repos

| Repo | Role | Runs on |
|---|---|---|
| **[jos](https://github.com/splippers/jos)** (this repo) | The client runtime: initrd build, GRUB menu, local-boot fallback, Secure Boot chain staging | the machine being imaged (client) |
| [jog](https://github.com/splippers/jog) | The imaging laptop: Ubuntu autoinstall, FOG install, isolated DHCP/TFTP, kiosk, driver share, provisioning payload | the laptop (server) |
| [jog-jos](https://github.com/splippers/jog-jos) | Integration: pins `jog` and `jos` at known-good commits, combined docs, end-to-end tests | n/a |

Everything in this repo runs on, or builds for, the **client**. Nothing here installs or configures a
server.

## Why it exists

- **Secure Boot without a site key.** The kernel is Canonical-signed; the matching signed modules ship
  as a second initrd. Firmware does not need to trust a custom key.
- **FOG-native.** The stock FOS scripts speak the FOG protocol (`web=` + `boottype=usb`, then
  `hostgetkey.php` / `hostinfo.php`). No API tokens are embedded in the image.
- **Predictable by default.** The default entry auto-joins a multicast session that is still waiting,
  images when the server has a task for the host, and otherwise boots the local disk. A technician does
  not have to rescue a machine from an empty task.
- **One menu, same choices.** Deploy/capture, registration, inventory, debug, Capone, multicast join,
  and the diagnostic tools are available without iPXE.

## Quick start

Build the initrd from the pinned FOS userland:

```bash
./build/build-from-fos.sh          # -> build/out/initrd.img
```

Stage the boot chain into a TFTP root (run as root on the JOG server):

```bash
sudo ./scripts/jos-stage-boot.sh   # -> /tftpboot/{grub,jos,ubuntu-signed}
```

Test the staged chain under Secure Boot:

```bash
sudo ./scripts/test-secureboot-vm.sh /tftpboot
```

The stage script reads the version from `VERSION` and renders the GRUB menu with `JOS | ...` labels.
The initrd prints the same banner before the FOS userland starts.

## Boot menu

| Entry | What it does |
|---|---|
| `JOS \| 0. Boot from local disk` | Repairs/creates the local UEFI boot entry, then reboots into it |
| `JOS \| 1. JOS Image Deploy/Capture` | Default: joins a waiting multicast session, images when the server has a task, otherwise local boot |
| `JOS \| 2-6. Registration / inventory / Capone / debug` | The stock FOS `mode=` actions |
| `JOS \| 7-9. Deploy / multicast join / product key` | Console versions of FOG's iPXE actions |
| `JOS \| 10. Advanced / Diagnostics` | badblocks, checkdisk, PhotoRec, chntpw, wipe, key enrolment |
| `JOS \| 11. JOS Debug` | Verbose logging (`loglevel=7 isdebug=yes`) |
| `JOS \| 12. Memtest86+` | Unsigned; needs Secure Boot off |

The default is entry 1 with a 5-second timeout. Set `JOS_GRUB_TIMEOUT=-1` to wait indefinitely.

## Repository layout

| Path | Purpose |
|---|---|
| `build/build-from-fos.sh` | Builds the initrd from the pinned FOS userland (`build/out/initrd.img`) |
| `build/jos-banner.sh` | The ASCII banner printed by `/init` inside the initrd |
| `build/jos-branding.sh` | Prints the brand block from the repo (developer helper) |
| `build/jos-localboot.sh` | Local-disk fallback: creates UEFI boot entries from local ESPs, then reboots |
| `build/jos-taskcheck.sh` | Gate for the default entry: auto-join a waiting multicast session, image if a task exists, otherwise local boot |
| `build/jos-fogmenu.sh` | Console versions of the FOG iPXE actions |
| `scripts/jos-stage-boot.sh` | Stages shim, GRUB, signed kernel, initrd, modules, and the menu |
| `scripts/test-secureboot-vm.sh` | Boots the staged chain in a Secure Boot VM |
| `branding/jos-logo.txt` | ASCII logo (no font or Unicode dependency) |
| `VERSION` | Date-based release, e.g. `2026.11` |
| `initrd/` | Retired shell client, kept for reference |

## Branding

The name is **JOS**; the tagline is **Jonathan's OS**. The boot chain is ASCII-only: no Unicode box
drawing, no custom fonts, no colour assumptions beyond the GRUB palette. See
[`docs/branding.md`](docs/branding.md) for the logo, palette, voice, and usage rules.

```text
     ###   #####   #####
      #   #     #  #
      #   #     #  #####
#     #   #     #      #
 #####    #####   #####

  JOS - Jonathan's OS  2026.11
  Secure Boot imaging runtime for FOG
```

## Documentation

| Doc | Contents |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | Boot flow, initrd design, FOS parity |
| [`docs/branding.md`](docs/branding.md) | Name, logo, palette, voice, versioning |
| [`docs/fos-fog-parity-checklist.md`](docs/fos-fog-parity-checklist.md) | What JOS must keep from FOS |
| [`docs/fos-fork-refactor-plan.md`](docs/fos-fork-refactor-plan.md) | Refactor history and open work |
| [`jog-jos/docs/CORPORATE-PROVISIONING.md`](https://github.com/splippers/jog-jos/blob/main/docs/CORPORATE-PROVISIONING.md) | The post-imaging corporate pipeline |
| [`jog-jos/docs/MULTICAST-100.md`](https://github.com/splippers/jog-jos/blob/main/docs/MULTICAST-100.md) | 100-client multicast imaging |

## Status

Active development. The default path is the FOS-based initrd; the `initrd/` shell client is legacy
and retained for reference. The boot chain is tested with `scripts/test-secureboot-vm.sh` before it is
staged for hardware.

## License

See [LICENSE](LICENSE). The FOS userland bundled into the initrd is GPL-3 code; the built image is
gitignored and never committed.
