# Board scripts

Helpers for working on a C100 that runs this system, used from the host.
They talk to the board over SSH, where every command is an Elixir expression
evaluated in the running IEx. Settings come from the environment:

| Variable | Default | Meaning |
| --- | --- | --- |
| `C100_BOARD` | `192.168.0.31` | Board address |
| `C100_APP_DIR` | `../../hello_c100` relative to this repository | Nerves application built against this system |
| `C100_SYSTEM_ARTIFACT` | this repository's `.nerves/artifacts/nerves_system_okdo_c100-portable-0.1.0` | Buildroot output of this system |
| `C100_BOOT_LOG_DIR` | `/tmp/c100-boots` | Where boot traces and register dumps are written |
| `C100_L4T_KNOWN_HOSTS` | `/tmp/c100-l4t-known-hosts` | Host-key file for the board's L4T installation |

Firmware cycle: `build-app.sh` builds the application firmware,
`upload-app.sh` writes it to the inactive slot and reboots, `confirm-fw.sh`
waits and prints the active slot and its validation. Always confirm before
rebooting again, otherwise U-Boot falls back to the previous slot.

Boot testing: `trace-native-boots.sh N label FIRMWARE_UUID` reboots N times
and checks each boot for a validated slot, the expected firmware, normal power
management and a working first GPU channel (`observe-native-boot.sh` does one
observation); it stops at the first failure. `trace-boots.sh N` and
`trace-boots-low.sh N` are the simpler loops that only save the nouveau log,
the latter after dropping the EMC and GPU clocks. `run-series.sh N` rebuilds,
uploads, confirms and traces in one go.

`rebuild-dtb.sh` rebuilds the kernel and the system after a change in
`linux/`, then the application firmware. `regdump.sh label` builds `regread.c`
with the system toolchain and dumps GPU and SoC registers through `/dev/mem`.
`l4t-ssh.sh` runs a command on the board's L4T installation when the user has
booted it; the password comes from `SSHPASS`.
