# Booting the C100 from a Nerves microSD card

This is the normal way to run Nerves on the OKdo Nano C100: the firmware
lives on a microSD card and nothing on the eMMC is modified. For installing
on the eMMC instead, see the README.

## What you need

* An OKdo Nano C100 with its factory boot firmware, or one flashed with
  [c100-bootupd](https://github.com/LetsOKdo/c100-bootupd). Both put OKdo's
  U-Boot on the eMMC, and that U-Boot knows the carrier's microSD slot and
  boots from it first. A board whose eMMC was reflashed with another image
  (a plain Jetson Nano L4T image, Android or LineageOS) will not find the
  card: restore it with `c100-bootupd` first.
* A microSD card of at least 4 GB (the Nerves layout uses about 2.1 GB for
  the boot and two root partitions; the rest becomes application data) and
  a card reader on your computer.
* Recommended: a 3.3 V USB serial adapter on the debug UART (`ttyS0`,
  115200 8N1) to watch the boot. Without it you work over the network.
* On the computer: the Nerves toolchain (`mix nerves.new` works, see the
  [Nerves installation guide](https://hexdocs.pm/nerves/installation.html)),
  and `fwup` 1.16 or later.

## 1. Build a firmware

In a Nerves application whose `mix.exs` lists this system for the
`:okdo_c100` target (`~/Projects/hello_c100` is such an application and is
used for board testing):

```sh
export MIX_TARGET=okdo_c100
mix deps.get
mix firmware
```

The first build also builds this system (about an hour) unless a prebuilt
system artifact is available. The result is
`_build/okdo_c100_dev/nerves/images/<app>.fw`.

## 2. Write the card

Insert the card in the reader and run:

```sh
mix burn
```

`fwup` lists the removable devices and asks which one to write. If it does not
detect the card, name it: `mix burn -d /dev/sdX` (Linux) or
`mix burn -d /dev/rdiskN` (macOS). This erases the card and writes the
partition table, U-Boot's environment, the boot partition with `boot.scr` and
this system's `u-boot.bin`, root filesystem A with the firmware, and an empty
application data partition. Root filesystem B stays empty until the first
update.

## 3. Boot

1. Power the C100 off, insert the card in the carrier's microSD slot and
   power it on.
2. On the serial console you see, in order: NVIDIA's boot firmware, OKdo's
   U-Boot (its banner names the Tegra210 and mentions `mmc1`), the line
   `Found U-Boot script /boot.scr` followed by this system's U-Boot
   (`U-Boot 2026.07`), then the Linux kernel and the Nerves boot messages.
   After roughly 20 seconds the IEx prompt appears on the console.
3. If the application uses `nerves_pack` with the default configuration, the
   board requests an address over DHCP on `eth0` and advertises itself with
   mDNS as `nerves-xxxx.local`, where `xxxx` are the last four characters of
   the Jetson module's serial number. The USB device port also provides
   gadget Ethernet (`usb0`, `172.31.x.x`).
4. Log in over SSH with the key configured in the application
   (`ssh nerves-xxxx.local`, or the DHCP address). The shell is IEx; every
   command is an Elixir expression.

The first boot of a freshly written card is considered valid automatically
(`nerves_fw_autovalidate=1` in the environment written by `fwup`). Check:

```elixir
Nerves.Runtime.KV.get_all() |> Map.take(["nerves_fw_active", "nerves_fw_validated"])
```

returns `%{"nerves_fw_active" => "a", "nerves_fw_validated" => "1"}`.

## 4. Update over the network

After the first boot, new firmware goes over the network instead of the card
reader:

```sh
mix firmware
mix upload nerves-xxxx.local
```

`mix upload` writes the inactive root filesystem (B after the first install),
switches to it and reboots. Validation is automatic by default; with
`nerves_fw_autovalidate=0` the application must call
`Nerves.Runtime.validate_firmware/0`, otherwise the next reboot returns to the
previous slot. Do not reboot a board between an upload and its validation, or
you will be testing the old firmware. U-Boot itself is only rewritten by
`mix burn`.

## How the card boots

NVIDIA's boot firmware on the module (BCT, nvtboot, TOS, cboot) always starts
the U-Boot stored in the eMMC `LNX` partition. With a Nerves card inserted,
that U-Boot's distro boot finds the card's boot partition (marked bootable),
runs its `boot.scr`, which chain-loads this system's U-Boot from the same
partition. This system's U-Boot then reads the Nerves environment from the
card and boots the active root filesystem with the Nerves A/B logic. A Nerves
card therefore takes precedence over whatever is installed on the eMMC;
remove the card to boot the eMMC again. The partition layout and the eMMC
installation are described in the README.

## If it does not boot

* **The board boots the eMMC system (L4T) with the card inserted.** The eMMC
  U-Boot is not OKdo's, or the card was written with another layout. Reflash
  the boot firmware with `c100-bootupd` and rewrite the card with `mix burn`.
* **OKdo's U-Boot stops at its prompt.** Press nothing during boot; a key
  press on the serial console interrupts distro boot. Type `boot` to continue
  or `reset`.
* **`Found U-Boot script` appears but Linux never starts.** The boot partition
  is readable but the root filesystem is not: rewrite the card.
* **Linux starts, no IEx prompt.** Watch the serial console for `erlinit`
  errors; the console is `ttyS0`. Check that the application was built for
  `MIX_TARGET=okdo_c100`.
* **No network.** `eth0` needs a link and a DHCP server; `nerves_pack` can be
  configured for a static address. The gadget Ethernet on the USB device port
  works without any of that.
* **After an update the old firmware runs again.** The new slot was not
  validated before a reboot; upload again and let it validate.
* **GPU errors in `dmesg`.** nouveau builds the GPU's golden context when the
  first application opens a channel; see `docs/nouveau-gm20b.md` if that
  logs a timeout or a trap.

Recovering a board whose NVIDIA boot firmware is damaged requires USB recovery
mode and `c100-bootupd`; this system provides no tools for that.
