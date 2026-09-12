#!/usr/bin/env bash
set -Eeuo pipefail

: "${APP:="Windows"}"
: "${PLATFORM:="x64"}"
: "${BOOT_MODE:="windows"}"
: "${SUPPORT:="https://github.com/dockur/windows"}"

cd /run

. start.sh      # Startup hook
. utils.sh      # Load functions
. init.sh       # Initialize system
. memory.sh     # Check memory
. server.sh     # Start webserver
. download.sh   # Load functions
. define.sh     # Define versions
. mido.sh       # Download Windows
. answer.sh     # Modern unattended
. batch.sh      # Win9x unattended
. sif.sh        # NT5 unattended
. legacy.sh     # Legacy installs
. image.sh      # Detect image files
. install.sh    # Run installation
. disk.sh       # Initialize disks
. display.sh    # Initialize graphics
. audio.sh      # Initialize audio
. network.sh    # Initialize network
. samba.sh      # Configure samba
. boot.sh       # Configure boot
. proc.sh       # Initialize processor
. power.sh      # Configure shutdown
. balloon.sh    # Initialize ballooning
. config.sh     # Configure arguments
. finish.sh     # Finish initialization

trap - ERR

SANDBOX_DISK=""

cleanupSandbox() {

  [ -z "$SANDBOX_DISK" ] && return 0

  rm -f -- "$SANDBOX_DISK"
  SANDBOX_DISK=""
}

setupSandbox() {

  disabled "${SANDBOX:-N}" && return 0

  if ! hasBootMarker; then
    error "SANDBOX requires an existing Windows installation!"
    exit 68
  fi

  local base format

  for base in "$STORAGE/data.img" "$STORAGE/data.raw" "$STORAGE/data.qcow2"; do
    [ -f "$base" ] && break
  done

  if [ ! -f "$base" ]; then
    error "Could not find the Windows disk for SANDBOX mode!"
    exit 68
  fi

  case "${base##*.}" in
    qcow2) format="qcow2" ;;
    *) format="raw" ;;
  esac

  SANDBOX_DISK="$TMP/sandbox.qcow2"
  rm -f -- "$SANDBOX_DISK"

  if ! qemu-img create -f qcow2 -F "$format" -b "$base" "$SANDBOX_DISK" >/dev/null; then
    SANDBOX_DISK=""
    error "Could not create the SANDBOX disk overlay!"
    exit 68
  fi

  ARGS="${ARGS//$base/$SANDBOX_DISK}"
  trap cleanupSandbox EXIT
}

setupSandbox

cmd=(qemu-system-x86_64)
version=$("${cmd[@]}" --version | awk 'NR==1 { print $4 }')
info "Booting ${APP}${BOOT_DESC} using QEMU v$version..." && echo

pipe="$QEMU_DIR/qemu.pipe"
rm -f "$pipe" && mkfifo "$pipe"

tee "$QEMU_PTY" <"$pipe" |
sed -u \
  -e 's/\x1B\[[=0-9;]*[a-z]//gi' \
  -e 's/\x1B\x63//g' \
  -e 's/\x1B\[[=?]7l//g' \
  -e '/^$/d' \
  -e 's/\x44\x53\x73//g' \
  -e 's/failed to load Boot/skipped Boot/g' \
  -e 's/0): Not Found/0)/g' &

output=$!

if ! enabled "$SHUTDOWN"; then
  exec "${cmd[@]}" ${ARGS:+ $ARGS} >"$pipe" 2>&1
fi

if ! interactive; then
  "${cmd[@]}" ${ARGS:+ $ARGS} >"$pipe" 2>&1 &
else
  startConsole "$pipe"
  startQemu "${cmd[@]}" ${ARGS:+ $ARGS} >"$pipe" 2>&1
fi

pid=$!
waitForBoot "$pid" 30 &

rc=0
wait "$pid" || rc=$?
interactive && stopConsole
wait "$output" || :

[ -f "$QEMU_END" ] && exit "$rc"

sleep 1 & wait $!
finish "$rc"
