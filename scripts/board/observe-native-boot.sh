#!/usr/bin/env bash
set -euo pipefail
board=${C100_BOARD:-192.168.0.31}
old_boot=${1:?previous boot ID required}
output=${2:?output file required}
marker=${3:?expected firmware marker required}
deadline=$((SECONDS + 360))
while (( SECONDS < deadline )); do
  if timeout 12 ssh -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=5 "$board" '
    IO.puts("BOOT_ID=" <> String.trim(File.read!("/proc/sys/kernel/random/boot_id")))
    kv = Nerves.Runtime.KV.get_all()
    IO.puts("SLOT=" <> kv["nerves_fw_active"] <> " VALIDATED=" <> kv["nerves_fw_validated"])
    IO.puts("FIRMWARE_UUID=" <> kv[kv["nerves_fw_active"] <> ".nerves_fw_uuid"])
    IO.puts("CMDLINE=" <> String.trim(File.read!("/proc/cmdline")))
    case File.read("/sys/module/nouveau/parameters/config") do {:ok, v} -> IO.puts("NOUVEAU_CONFIG=" <> String.trim(v)); _ -> :ok end
    case File.read("/etc/c100-gpu-test-id") do {:ok, id} -> IO.puts("TEST_ID=" <> String.trim(id)); _ -> :ok end
    for {key, path} <- [{"GOVERNOR", "/sys/class/devfreq/57000000.gpu/governor"}, {"GPU_MAX", "/sys/class/devfreq/57000000.gpu/max_freq"}, {"GPU_FREQ", "/sys/class/devfreq/57000000.gpu/cur_freq"}] do
      case File.read(path) do {:ok, v} -> IO.puts(key <> "=" <> String.trim(v)); _ -> :ok end
    end
    for r <- Path.wildcard("/sys/class/regulator/regulator.*"), File.read(Path.join(r, "name")) == {:ok, "VDD_GPU\n"}, do: IO.puts("VDD_GPU=" <> String.trim(File.read!(Path.join(r, "microvolts"))))
    IO.puts("CPU_MAX=" <> String.trim(File.read!("/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq")))
    unless File.exists?("/sys/kernel/debug/clk"), do: System.cmd("mount", ["-t", "debugfs", "debugfs", "/sys/kernel/debug"])
    case File.read("/sys/kernel/debug/clk/emc/clk_rate") do {:ok, v} -> IO.puts("EMC_RATE=" <> String.trim(v)); _ -> :ok end
    # nouveau is a module; once its render node exists, open the first channel
    if Path.wildcard("/sys/devices/platform/57000000.gpu/drm/renderD*") != [] do
      {_, rc} = System.cmd("vulkaninfo", ["--summary"], env: [{"NVK_I_WANT_A_BROKEN_VULKAN_DRIVER", "1"}], stderr_to_stdout: true)
      IO.puts("FIRST_CHANNEL=" <> if(rc == 0, do: "ok", else: "failed"))
    end
    {d, rc} = System.cmd("dmesg", [])
    if rc != 0, do: raise("dmesg failed")
    IO.puts(d)
    :ok' > "$output.pending" 2>&1; then
    boot=$(sed -n 's/^BOOT_ID=//p' "$output.pending" | tr -d '\r')
    if [[ -n "$boot" && "$boot" != "$old_boot" ]] && grep -q 'VALIDATED=1' "$output.pending"; then
      if grep -q '^FIRST_CHANNEL=' "$output.pending"; then
        mv "$output.pending" "$output"
        if ! grep -q "$marker" "$output"; then
          printf 'Wrong firmware: expected %s\n' "$marker"
          exit 3
        fi
        if [[ "$marker" == c100-native-v2 || "$marker" == FIRMWARE_UUID=* ]]; then
          voltage=$(sed -n 's/^VDD_GPU=//p' "$output" | tr -d '\r')
          if ! grep -q '^GOVERNOR=simple_ondemand' "$output" ||
             ! grep -q '^GPU_MAX=921600000' "$output" ||
             ! grep -q '^CPU_MAX=1479000' "$output" ||
             ! grep -q '^EMC_RATE=1600000000' "$output" ||
             [[ ! "$voltage" =~ ^[0-9]+$ ]] || (( voltage < 818750 || voltage > 1200000 )); then
            printf 'FAIL power management state: %s\n' "$output"
            exit 1
          fi
        fi
        if [[ "$marker" == FIRMWARE_UUID=* ]] &&
           { grep -q '^CMDLINE=.*nouveau.debug=' "$output" ||
             ! grep -Eq $'^NOUVEAU_CONFIG=(\\(null\\))?\r*$' "$output"; }; then
          printf 'FAIL unexpected nouveau override: %s\n' "$output"
          exit 1
        fi
        if grep -q '^FIRST_CHANNEL=ok' "$output" && ! grep -Ei -q 'nouveau.*(timeout|timed out|failed|TRAP|FAULT)' "$output"; then
          printf 'PASS %s %s\n' "$boot" "$output"
          exit 0
        fi
        printf 'FAIL %s %s\n' "$boot" "$output"
        exit 1
      fi
    fi
  fi
  sleep 5
done
mv "$output.pending" "$output"
printf 'Board did not reach a validated new boot with a GPU outcome: %s\n' "$output"
exit 2
