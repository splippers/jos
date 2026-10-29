# JOS Architecture

> **Superseded in part.** The default JOS is now the stock FOS userland on the Canonical-signed kernel
> (`build/build-from-fos.sh`); see `docs/JOG-JOS-RESEARCH.md` §3. Everything below describing the
> `initrd/scripts/jos-*.sh` REST client is the legacy implementation. The Secure Boot chain and the
> `modules.img` section still apply to both.

JOS is a Secure Boot–compatible PXE micro‑OS (initramfs-centric “appliance”, typically entirely from RAM).

## Boot flow (canonical)

`firmware PXE → shimx64.efi → grubnetx64 (as grubx64.efi) → signed Ubuntu kernel → JOS initramfs → /init → JOS runtime`

Immutable for Secure Boot: **shim**, **GRUB**, **signed kernel**. Only the **initramfs** is project-built.

iPXE cannot be the first stage with Secure Boot on (unsigned). `config/ipxe/jos.ipxe.example` is for Secure Boot-off machines only. Staging: `scripts/jog-stage-jos-boot.sh`; check: `scripts/jog-doctor.sh`; VM test with enforcing Secure Boot: `scripts/test-secureboot-vm.sh`.

**Second initrd.** GRUB loads `jos/initrd.img` (unsigned, project-built) plus `jos/modules.img` (signed modules from the same kernel package as `vmlinuz`). Under lockdown the kernel rejects unsigned modules, so the JOS build must never ship its own. `jos-modules.sh` loads them at boot.

## Core components (initramfs)

| Stage | Script | Role |
|-------|--------|------|
| Network | `jos-net.sh`, `udhcpc-jos.sh` | BusyBox `udhcpc`; capture DHCP **NEXT SERVER** (`siaddr`) → `/tmp/jos-next-server` |
| Identity | `jos-serial.sh` | Service tag / serial — **`dmidecode -s system-serial-number`** when present, sysfs DMI fallback |
| Registration | `jos-register.sh` | `GET …/host/search` then `POST …/host/create` (API tokens from `$FOG_CONFIG_FILE`) |
| Inventory | `jos-inventory.sh`, `jos-disk.sh` | FOG **Inventory** fields (`sysserial`, `mem`, `hdmodel`, …) + sysfs / **`lsblk -J`** sizing |
| FOG tasks | `jos-fog-task-runner.sh` | Poll `GET …/host/{id}` (jq), dispatch **deploy/capture** by `taskTypeID` (FOG Route::task) |
| Unicast imaging | `jos-imaging-unicast.sh`, `jos-nfs.sh` | NFS mount `${FOG_SERVER}:/images` + **`partclone`** restore of `d1p*.img` (gated by **`JOS_IMAGING_ALLOW_DISK_WRITE`**) |
| Multicast | `jos-multicast.sh`, `jos-udpcast-receiver.sh` | FOG API queue + **`udp-receiver`** with suicide-clause watchdog |

## DHCP NEXT SERVER as FOG target

- `udhcpc` runs with `-s /scripts/udhcpc-jos.sh`
- On `bound` / `renew`, the handler writes `/tmp/jos-next-server` (BOOTP `siaddr`), `/tmp/jos-active-iface`, optional DNS/bootfile metadata.
- `jos_load_fog_config` defaults `FOG_SERVER` from `/tmp/jos-next-server` when unset in `$FOG_CONFIG_FILE`.

## FOG Server REST alignment

JOS targets the upstream FOG Project router semantics (`packages/web/lib/router/route.class.php`):

| Operation | Route pattern (under `/fog`) |
|-----------|-------------------------------|
| Find host by service-tag hostname | `GET /host/search/<term>` → read first **numeric** `host id` |
| Create host | `POST /host/create` (fallback `/host/new`, `/host`) with `name`, `macs`, optional `modules` |
| Inventory | `POST /inventory/create` or `PUT /inventory/<invid>/edit` using **Inventory** schema fields (`sysserial`, `sysman`, `mem`, …) |
| Deploy task | `POST /host/<hostid>/task` with JSON `taskTypeID` (FOG `Route::task`) |
| Multicast session | `POST /multicastsession/create` (+ association route as above) |

HTTPS: `jos_fog_base_url` honors `FOG_USE_SSL`; static `/tools/curl` accepts `FOG_SSL_INSECURE` / `FOG_CA_BUNDLE`.

### Dynamic FOG server version handling

After `jos_load_fog_config`, **`jos_fog_ensure_profile`** runs (unless `JOS_FOG_SKIP_VERSION_PROBE=1`):

1. **Prefer** `FOG_VERSION_OVERRIDE` from `jos.conf` if set (air‑gapped / scripted installs).
2. Else **fetch** `${FOG_BASE}/management/index.php` (same host as the API) and extract the first semver associated with **FOG**/**Version** text in the login page markup.
3. Convert to **sort key** \(major×10⁶ + minor×10³ + patch\) for comparisons.
4. **Pick API path ordering** (FOG AltoRouter: `…/create` vs bare class root) — typically **modern** order for **FOG 1.5.x and newer**, **legacy-first** order when the sort key indicates **FOG before 1.5.0** and the probe succeeded. **Unknown** version uses the same order as the modern default; **`JOS_FOG_API_STYLE`** can force **modern** or **legacy**.
5. Cache results in **`/tmp/jos-fog-profile.env`** so inventory/multicast reuse the same profile in one boot.

Default **client module list** for registration shrinks on detected legacy servers (sort key below 1.5.0) unless **`JOS_MODULES_JSON`** is set explicitly.

## Secure Boot posture

This repository **never ships or rebuilds** shim, GRUB, or the signed kernel — only the **unsigned initramfs** built under `build/`. Secure Boot stays valid when your PXE/GRUB chain loads vendor-signed binaries unchanged and passes the custom initramfs via normal kernel parameters.

## Related paths

- Authoritative constraints: `.cursor/rules/jos-unified.mdc`
- Build output: `build/out/initrd.img` (generated; not committed)
