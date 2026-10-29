# Fork/refactor plan: FOS-behavior-compatible JOS (Secure Boot + FOG)

This document captures the “next steps” to reach a **Secure Boot–compatible** PXE micro‑OS that behaves like **FOS** where it matters and integrates cleanly with **FOG**.

**Principle:** match **FOG contracts and task semantics**, not FOS implementation details.

---

## 1) Preserve the Secure Boot chain (non-negotiable)

The boot chain must stay vendor-signed up to the kernel:

`firmware PXE → shimx64.efi → grubnetx64 (as grubx64.efi) → Canonical-signed kernel → JOS initramfs → /init`

- **Do not rebuild or replace** shim, GRUB, or the signed kernel.
- Put all customization in the **initramfs** (unsigned is fine).

This keeps Secure Boot valid while allowing rapid iteration.

---

## 2) Establish the compatibility target (“FOS parity”)

Define parity as a checklist (see `docs/fos-fog-parity-checklist.md`) with staged phases:

- Boot + logging
- Deterministic networking + identity
- Host registration + inventory
- Task semantics
- Unicast imaging
- Multicast receive with the required watchdog

Success is observable via:

- FOG UI state transitions
- REST API responses
- `/tmp/jos_error.log` on the client

---

## 3) Refactor boundaries (so the project stays maintainable)

Even if the implementation remains shell-first, keep responsibilities separated:

- **Platform** (boot/mount/logging, deterministic net bring-up, NIC choice)
- **Identity** (serial/service tag)
- **FOG API** (tokens, TLS handling, JSON helpers, version probe)
- **FOG tasks** (dispatcher + handlers)
- **Imaging** (partclone/NFS helpers, progress, cleanup)
- **Multicast** (udpcast wrapper with “suicide clause”)

In today’s repo these are already represented by `initrd/scripts/jos-*.sh`. The “refactor” step is to:

- keep `/init` as a short orchestrator
- keep large logic in scripts with clean interfaces
- add testable helpers in `jos-common.sh` (already in progress)

---

## 4) Forking FOS: what to take vs what to avoid

Use the FOS repo as:

- a reference for **task behavior**, edge cases, and operator expectations
- a list of “must not regress” behaviors

Avoid:

- attempting to keep FOS’s original boot mechanisms intact (they’re not Secure Boot friendly)
- copying monolithic init logic without modular boundaries

Treat FOS as a behavioral specification.

---

## 5) Next concrete work items (implementation order)

### A. Add a “compatibility harness” (repo-local)

Create a lightweight script set that can validate:

- FOG endpoints reachable and version probe works
- registration creates a host when absent
- inventory creates/updates a record
- task queue + multicast session association APIs behave as expected

The harness should run in the initramfs **and** on a dev machine (where possible).

### B. Unicast imaging MVP

Implement one safe, narrow imaging flow first (deploy only or capture only), then expand.

Minimum acceptable:

- disk selection: largest non-removable device
- partition table awareness (GPT/MBR)
- hard failure → log + reboot or shell (configurable)

### C. Multicast receive safety clause

