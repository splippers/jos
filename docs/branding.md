# JOS branding

**JOS** is the client runtime. **Jonathan's OS** is the tagline. The appliance is **JOG**.

```text
JOG + JOS — Corporate reimaging, without the licence bill.
```

That line belongs to the product family (the `jog-jos` integration repo). Keep it out of the boot
chain; the boot chain gets the name and the tagline only.

## Logo

ASCII only. It has to render in GRUB, on a serial console, on a laptop panel, and in a terminal with
no font or Unicode assumptions.

```text
     ###   #####   #####
      #   #     #  #
      #   #     #  #####
#     #   #     #      #
 #####    #####   #####
```

The canonical copy is [`branding/jos-logo.txt`](../branding/jos-logo.txt). `build/jos-banner.sh`
installs it into the initrd as `/etc/jos-logo.txt`; `scripts/jos-stage-boot.sh` uses the same name in
the GRUB banner.

Do not replace it with a Unicode box-drawing logo, an image, or a font-dependent glyph. If a future
logo needs more detail, keep the ASCII mark as the boot-chain mark and use the richer artwork only in
web/docs.

## Palette

| Role | Colour | Hex | Use |
|---|---|---|---|
| Primary | Cyan | `#00B8D4` | Links, highlights, the `JOS` mark on light backgrounds |
| Base | Graphite | `#1F2933` | Dark backgrounds, terminal chrome |
| Text on dark | Mist | `#E6EDF3` | Body text on graphite |
| Attention | Amber | `#F5A623` | Warnings only; never a primary brand colour |

GRUB is limited to its named palette. The staged menu uses:

```text
set color_normal=light-gray/black
set color_highlight=cyan/black
```

That is the boot-chain translation of Mist on Graphite with a Cyan highlight. Do not add escape
sequences or assume 24-bit colour in GRUB.

## Voice

- Direct, technical, calm. No hype, no "revolutionary", no exclamation marks.
- Say what happens, then how to verify it. Prefer a command and its expected output over a promise.
- Use **JOS** in uppercase. Use **Jonathan's OS** with the apostrophe. Do not expand it to
  "Jonathan's Operating System" in new material.
- Console lines use the `[JOS]` tag (`[JOS][12:34:56] ...`). Menu entries use the `JOS | ` prefix.
- Scope performance claims. The five-minute figure is the multicast imaging phase only; drivers,
  domain join, hybrid join, and BitLocker are a separate provisioning phase.

## Versioning

`VERSION` holds a date-based release, e.g. `2026.11`. Bump it deliberately when the boot chain or the
initrd changes in a way a technician would notice. The stage script reads it and prints it in the GRUB
banner; the initrd reads `/etc/jos-version` and prints it in the boot banner.

Do not put a Git SHA in the banner. The SHA belongs in build logs and release notes, not on a console a
technician reads at 2 a.m.

## Where the brand appears

| Surface | File | What it shows |
|---|---|---|
| GRUB banner | `scripts/jos-stage-boot.sh` | `JOS - Jonathan's OS  <version>` |
| GRUB entries | `scripts/jos-stage-boot.sh` | `JOS \| 0. ...`, `JOS \| 10. ...` |
| GRUB palette | `scripts/jos-stage-boot.sh` | `light-gray/black`, `cyan/black` |
| Initrd banner | `build/jos-banner.sh` | ASCII logo, tagline, version, one-line purpose |
| README | `README.md` | Name, tagline, architecture, quick start |
| iPXE example | `config/ipxe/jos.ipxe.example` | `JOS - Jonathan's OS` in the chain message |

## Do not

- Rename the Secure Boot chain (`shimx64.efi` → `grubx64.efi` → signed kernel). Branding is text and
  colour, not a new bootloader.
- Add a custom font to the initrd for the banner.
- Use the old "Jonathan's Operating System" expansion in new docs.
- Put a marketing claim in the boot path. The boot path says what it is and what it is doing.
