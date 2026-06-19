#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap_script="$repo_root/scripts/windows-integration-test/run-quick-blue-test.ps1"
common_script="$repo_root/scripts/windows-integration-test/windows-integration-common.ps1"
work_dir="${QUICK_BLUE_WINDOWS_WORK_DIR:-"$repo_root/.dart_tool/dockur_windows"}"
oem_dir="$work_dir/oem"
storage_dir="$work_dir/storage"
logs_dir="$work_dir/logs"
runner_marker="$logs_dir/runner-installed.txt"
container_name="${QUICK_BLUE_WINDOWS_CONTAINER:-quick-blue-windows-test}"
image="${QUICK_BLUE_WINDOWS_IMAGE:-dockurr/windows:latest}"
version="${QUICK_BLUE_WINDOWS_VERSION:-11}"
memory="${QUICK_BLUE_WINDOWS_MEMORY:-8G}"
cpu_cores="${QUICK_BLUE_WINDOWS_CPU_CORES:-4}"
disk_size="${QUICK_BLUE_WINDOWS_DISK_SIZE:-128G}"
web_port="${QUICK_BLUE_WINDOWS_WEB_PORT:-8006}"
rdp_port="${QUICK_BLUE_WINDOWS_RDP_PORT:-3389}"
flutter_channel="${QUICK_BLUE_WINDOWS_FLUTTER_CHANNEL:-stable}"
test_target="${QUICK_BLUE_WINDOWS_TEST_TARGET:-integration_test/ble_smoke_test.dart}"
timeout_seconds="${QUICK_BLUE_WINDOWS_TIMEOUT_SECONDS:-14400}"
status_file="$logs_dir/status.txt"
container_id=""
usb_device_path=""
usb_qemu_arguments=""

usage() {
  cat <<'USAGE'
Usage: scripts/windows-integration-test.sh

Starts a Dockur Windows VM and runs the quick_blue example BLE integration test.
The first install registers a Windows logon task; later runs reuse the VM and
execute the latest shared test script.

Common environment variables:
  QUICK_BLUE_WINDOWS_USB_VENDOR_ID=0x0a12       USB Bluetooth vendor ID to pass through
  QUICK_BLUE_WINDOWS_USB_PRODUCT_ID=0x0001      USB Bluetooth product ID to pass through
  QUICK_BLUE_WINDOWS_USB_BUS=001                Optional USB bus override
  QUICK_BLUE_WINDOWS_USB_DEVICE=014             Optional USB device override
  QUICK_BLUE_SMOKE_NAME_PATTERN='sensor|heart'  Passed as --dart-define
  QUICK_BLUE_SMOKE_DEVICE_ID='...'              Passed as --dart-define
  QUICK_BLUE_WINDOWS_FLUTTER_CHANNEL=stable     Flutter channel to clone in Windows
  QUICK_BLUE_WINDOWS_WORK_DIR=.dart_tool/...    Persistent Dockur state directory
  QUICK_BLUE_WINDOWS_KEEP_VM=1                  Leave the VM running after pass/fail
  QUICK_BLUE_WINDOWS_CLEAN_WORKTREE=1           Recreate the guest NTFS checkout
  QUICK_BLUE_WINDOWS_RUN_DOCTOR=1               Run flutter doctor on every test
  QUICK_BLUE_WINDOWS_RESET=1                    Delete the Windows disk and rebuild

The Windows guest log is written to:
  .dart_tool/dockur_windows/logs/windows-integration-test.log

RDP:  localhost:3389
Web:  http://localhost:8006
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

cleanup() {
  if [[ -n "$container_id" && "${QUICK_BLUE_WINDOWS_KEEP_VM:-0}" != "1" ]]; then
    docker stop "$container_id" >/dev/null 2>&1 || true
  fi
}

ps_quote() {
  local value="${1//\'/\'\'}"
  printf "'%s'" "$value"
}

hex_id() {
  local value="${1#0x}"
  value="${value#0X}"
  printf '%04x' "$((16#$value))"
}

decimal_id() {
  printf '%d' "$((10#$1))"
}

resolve_usb_passthrough() {
  if [[ -z "${QUICK_BLUE_WINDOWS_USB_VENDOR_ID:-}" && -z "${QUICK_BLUE_WINDOWS_USB_PRODUCT_ID:-}" ]]; then
    return
  fi
  if [[ -z "${QUICK_BLUE_WINDOWS_USB_VENDOR_ID:-}" || -z "${QUICK_BLUE_WINDOWS_USB_PRODUCT_ID:-}" ]]; then
    echo "Set both QUICK_BLUE_WINDOWS_USB_VENDOR_ID and QUICK_BLUE_WINDOWS_USB_PRODUCT_ID for USB passthrough." >&2
    exit 1
  fi

  local vendor_id product_id bus device
  vendor_id="$(hex_id "$QUICK_BLUE_WINDOWS_USB_VENDOR_ID")"
  product_id="$(hex_id "$QUICK_BLUE_WINDOWS_USB_PRODUCT_ID")"
  bus="${QUICK_BLUE_WINDOWS_USB_BUS:-}"
  device="${QUICK_BLUE_WINDOWS_USB_DEVICE:-}"

  if [[ -z "$bus" || -z "$device" ]]; then
    require_command lsusb
    local match
    match="$(lsusb -d "$vendor_id:$product_id" | head -n 1 || true)"
    if [[ ! "$match" =~ Bus[[:space:]]+([0-9]+)[[:space:]]+Device[[:space:]]+([0-9]+): ]]; then
      echo "Could not find USB device $vendor_id:$product_id with lsusb." >&2
      exit 1
    fi
    bus="${BASH_REMATCH[1]}"
    device="${BASH_REMATCH[2]}"
  fi

  usb_device_path="/dev/bus/usb/$bus/$device"
  if [[ ! -e "$usb_device_path" ]]; then
    echo "USB device node does not exist: $usb_device_path" >&2
    exit 1
  fi

  if [[ "${QUICK_BLUE_WINDOWS_SKIP_USB_PERMISSION_CHECK:-0}" != "1" && ! -w "$usb_device_path" ]]; then
    cat >&2 <<EOF
USB device $vendor_id:$product_id is present at $usb_device_path, but this
user cannot open it read-write. QEMU usb-host passthrough needs write access to
claim the adapter; otherwise Linux keeps the btusb driver bound and Windows
never sees VID_$vendor_id/PID_$product_id.

Current permissions:
  $(ls -l "$usb_device_path")

Use rootful Docker/sudo, or grant this user temporary access before running:
  sudo setfacl -m u:$(id -un):rw "$usb_device_path"

If you intentionally handled permissions another way, set
QUICK_BLUE_WINDOWS_SKIP_USB_PERMISSION_CHECK=1.
EOF
    exit 1
  fi

  usb_qemu_arguments="-device usb-host,hostbus=$(decimal_id "$bus"),hostaddr=$(decimal_id "$device")"
}

write_oem_files() {
  mkdir -p "$oem_dir" "$storage_dir" "$logs_dir"
  : >"$status_file"
  cp "$bootstrap_script" "$oem_dir/run-quick-blue-test.ps1"
  cp "$common_script" "$oem_dir/windows-integration-common.ps1"
  cp \
    "$repo_root/scripts/windows-integration-test/install-persistent-runner.ps1" \
    "$oem_dir/install-persistent-runner.ps1"

  cat >"$oem_dir/install.bat" <<'BAT'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\OEM\install-persistent-runner.ps1 -RunNow
BAT

  {
    echo "\$Env:QUICK_BLUE_HIDE_TEST_WINDOW = '1'"
    echo "\$Env:QUICK_BLUE_WINDOWS_FLUTTER_CHANNEL = $(ps_quote "$flutter_channel")"
    echo "\$Env:QUICK_BLUE_WINDOWS_CLEAN_WORKTREE = $(ps_quote "${QUICK_BLUE_WINDOWS_CLEAN_WORKTREE:-0}")"
    echo "\$Env:QUICK_BLUE_WINDOWS_RUN_DOCTOR = $(ps_quote "${QUICK_BLUE_WINDOWS_RUN_DOCTOR:-0}")"
    echo "\$QuickBlueTestTarget = $(ps_quote "$test_target")"
    echo "\$QuickBlueDartDefines = @("
    while IFS='=' read -r name value; do
      case "$name" in
        QUICK_BLUE_SMOKE_*)
          printf "  '--dart-define=%s=%s'\n" "$name" "${value//\'/\'\'}"
          ;;
      esac
    done < <(env | LC_ALL=C sort)
    echo ")"
  } >"$oem_dir/quick-blue-env.ps1"
}

require_command docker
resolve_usb_passthrough

if [[ ! -f "$bootstrap_script" ]]; then
  echo "Missing Windows bootstrap script: $bootstrap_script" >&2
  exit 1
fi

if [[ "${QUICK_BLUE_WINDOWS_RESET:-0}" == "1" ]]; then
  echo "Resetting Dockur Windows storage at $storage_dir"
  rm -rf "$storage_dir"
fi

if [[ ! -e /dev/kvm && "${QUICK_BLUE_WINDOWS_REQUIRE_KVM:-1}" != "0" ]]; then
  cat >&2 <<'EOF'
/dev/kvm is not available. Dockur Windows needs KVM for practical test runs.
Set QUICK_BLUE_WINDOWS_REQUIRE_KVM=0 to try without this preflight check.
EOF
  exit 1
fi

if docker ps -a --format '{{.Names}}' | grep -Fxq "$container_name"; then
  echo "Container '$container_name' already exists." >&2
  echo "Stop/remove it first, or set QUICK_BLUE_WINDOWS_CONTAINER to another name." >&2
  exit 1
fi

write_oem_files

if [[ -f "$storage_dir/data.img" && ! -f "$runner_marker" && "${QUICK_BLUE_WINDOWS_ALLOW_LEGACY_BOOT:-0}" != "1" ]]; then
  cat >&2 <<EOF
Existing Dockur Windows disk was created before the reusable quick_blue
runner was installed, so /oem/install.bat will not run again automatically.

To repair this disk without reinstalling Windows:
  1. Start the VM once with:
       QUICK_BLUE_WINDOWS_ALLOW_LEGACY_BOOT=1 QUICK_BLUE_WINDOWS_KEEP_VM=1 scripts/windows-integration-test.sh
  2. RDP to localhost:$rdp_port as Docker / admin.
  3. Run this in Windows PowerShell:
       powershell -NoProfile -ExecutionPolicy Bypass -File "\$env:USERPROFILE\\Desktop\\Shared\\.dart_tool\\dockur_windows\\oem\\install-persistent-runner.ps1" -RunNow

After that marker file appears:
  $runner_marker

Future runs will start the existing VM and the scheduled launcher will run the
latest generated test script automatically. To rebuild instead, set
QUICK_BLUE_WINDOWS_RESET=1.
EOF
  exit 1
fi

docker_args=(
  run
  --name "$container_name"
  --rm
  -d
  -p "$web_port:8006"
  -p "$rdp_port:3389/tcp"
  -p "$rdp_port:3389/udp"
  -v "$storage_dir:/storage"
  -v "$oem_dir:/oem"
  -v "$repo_root:/shared"
  -e "VERSION=$version"
  -e "RAM_SIZE=$memory"
  -e "CPU_CORES=$cpu_cores"
  -e "DISK_SIZE=$disk_size"
)

if [[ -e /dev/kvm ]]; then
  docker_args+=(--device /dev/kvm)
fi

if [[ -n "$usb_device_path" ]]; then
  docker_args+=(
    --device "$usb_device_path:$usb_device_path"
    -e "ARGUMENTS=$usb_qemu_arguments"
  )
fi

echo "Starting $image as $container_name."
echo "Windows web console: http://localhost:$web_port"
echo "Windows RDP: localhost:$rdp_port"
echo "Guest log: $logs_dir/windows-integration-test.log"
echo
echo "First run installs Windows and the toolchain; later runs reuse the VM."

container_id="$(docker "${docker_args[@]}" "$image")"
trap cleanup EXIT

deadline=$((SECONDS + timeout_seconds))
last_status=""
while (( SECONDS < deadline )); do
  if [[ -s "$status_file" ]]; then
    status="$(tr -d '\r\n' <"$status_file")"
    if [[ "$status" != "$last_status" ]]; then
      echo "Windows integration status: $status"
      last_status="$status"
    fi
    case "$status" in
      passed)
        echo "Windows integration test passed."
        exit 0
        ;;
      failed)
        echo "Windows integration test failed. Recent guest log:" >&2
        if [[ -f "$logs_dir/windows-integration-test.log" ]]; then
          tail -n 80 "$logs_dir/windows-integration-test.log" >&2
        fi
        exit 1
        ;;
    esac
  fi

  if ! docker ps --no-trunc --format '{{.ID}}' | grep -Fxq "$container_id"; then
    echo "Dockur container exited before the Windows test completed. Recent container log:" >&2
    docker logs --tail 120 "$container_id" >&2 || true
    exit 1
  fi

  sleep 15
done

echo "Timed out waiting for Windows integration test after ${timeout_seconds}s." >&2
echo "Web console remains available only if QUICK_BLUE_WINDOWS_KEEP_VM=1 was set." >&2
exit 1
