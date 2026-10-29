# FOS → JOS parity checklist (FOG-compatible, Secure Boot chain)

This is the working, measurable definition of “FOS replacement” for **JOS**.

JOS is intentionally **not** a general-purpose distro. It is an initramfs-centric appliance that preserves the Secure Boot chain:

`firmware PXE → shimx64.efi → grubnetx64 (as grubx64.efi) → Canonical-signed kernel → JOS initramfs → /init → JOS runtime`

Only the **initramfs** changes.

---

## Scope: what parity means

Parity is defined as:

- **FOG server compatibility**: JOS must use the same REST API contracts / task semantics FOS relies on.
- **Operational equivalence**: a technician can PXE boot and walk away; behavior matches FOS where it matters.
- **Deterministic and safe**: bounded retries, clear logs (`/tmp/jos_error.log`), corporate LAN safety preserved by design.

Non-goals (explicitly):

- Rebuilding or replacing shim/GRUB/kernel (breaks Secure Boot posture)
- Full desktop Linux experience
- “Everything FOS ever did” on day one (parity is staged)

---

## Phase 0 — Boot + observability (must have)

- [ ] Boot chain preserved end-to-end (shim→GRUB→signed kernel→initramfs)
- [ ] `/tmp/jos_error.log` contains actionable errors for any failure
- [ ] Shell escape hatch exists (drop to `/bin/sh`) when unrecoverable
- [ ] Build is reproducible (tool fetch scripts, pinned inputs where feasible)

---

## Phase 1 — Identity + networking (must have)

- [ ] Deterministic DHCP with bounded retries/backoff
- [ ] Capture DHCP **NEXT SERVER** (`siaddr`) → `/tmp/jos-next-server`
- [ ] Prefer USB3 Ethernet NIC for imaging traffic (deployment policy)
- [ ] Stable primary identity:
  - [ ] `dmidecode -s system-serial-number` when available
  - [ ] sysfs DMI fallback

---

## Phase 2 — FOG registration + inventory (must have)

- [ ] Host lookup by service-tag hostname: `GET /fog/host/search/<term>`
- [ ] Host create using version-aware path ordering (`/host/create` vs legacy)
- [ ] Inventory upload/create/update (version-aware)
- [ ] Inventory payload fields remain compatible with FOG UI expectations
- [ ] Never hardcode tokens; load from `$FOG_CONFIG_FILE`

Acceptance:

- A booting machine appears in FOG hosts automatically with correct MAC + serial name
- Inventory fields populate without manual intervention

---

## Phase 3 — Task semantics (must have)

- [ ] Poll / fetch host task assignments (FOG semantics)
- [ ] Correct task start/finish status updates
- [ ] Failures are visible in FOG (and in `/tmp/jos_error.log`)
- [ ] Deterministic reboot/shutdown behavior matches task type expectation

---

## Phase 4 — Unicast imaging (FOS core)

Directional goal: match FOS’s common capture/deploy flows using **partclone** + a FOG-compatible transport.

- [ ] Target disk selection (largest non-removable device; handle NVMe + VMD)
- [ ] Partition table handling compatible with FOG images
- [ ] Deploy image (unicast) with progress + error handling
- [ ] Capture image (unicast) with progress + error handling
- [ ] Clean up mounts and temp files on failure

---

## Phase 5 — Multicast receive (mandatory safety clause)

If JOS runs `udp-receiver`, it must enforce the multicast “weak-link kill-switch”:

- [ ] Inspect receiver output every 10 seconds
- [ ] If average throughput < 30MB/s for 3 consecutive checks → kill receiver → reboot

Acceptance:

- One slow client cannot throttle a large multicast session indefinitely

---

## Phase 6 — “Nice to have” parity

- [ ] Snapins / post-deploy tasks (only after imaging is stable)
- [ ] UI improvements (progress, simple TUI) without increasing fragility
- [ ] Additional hardware inventory fields (dmidecode/lshw enhancements)

---

## Mapping: where this lives in the repo

- Boot orchestration: `initrd/init`
- Networking: `initrd/scripts/jos-net.sh`, `initrd/scripts/udhcpc-jos.sh`
- Identity: `initrd/scripts/jos-serial.sh`
- FOG API helpers: `initrd/scripts/jos-common.sh`
- Registration: `initrd/scripts/jos-register.sh`
- Inventory: `initrd/scripts/jos-inventory.sh`, `initrd/scripts/jos-disk.sh`
- Multicast: `initrd/scripts/jos-multicast.sh`, `initrd/scripts/jos-udpcast-receiver.sh`

