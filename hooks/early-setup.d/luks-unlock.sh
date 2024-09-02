#!/bin/bash

## This early-setup hook finds all LUKS volumes by looking for partitions with
## fstype "crypto_LUKS". (Partition fstypes can be queried on GPT by supplying
## lsblk with the "--fs" option; see lsblk(8) for details.)
##
## If LUKS partitions are found, the hook attempts to unlock each encrypted volume.
## If successful, this will allow ZFSBootMenu to automatically find any zfs pools
## residing in these encrypted volumes.
##
## If no LUKS partitions are found, the hook will terminate and allow ZFSBootMenu
## to proceed with its ordinary startup process. A passphrase is asked once and stored
## in memory; this passphrase is subsequently used to unlock all the volumes.
## For each LUKS volume, sanity checks are performed in order to verify that the volume
## is both a valid block device and luks volume and is not already mapped before trying
## to unlock it. After every failed unlock cycle, an emergency shell will be invoked
## to allow manual intervention; type `exit` in the shell to continue the next unlock
## iteration.
##
## The passphrase for each volume is also stored in a keyfile in the ZFSBootMenu
## in-memory filesystem. This allows for special handling by other hooks that may
## try to re-use the passphrase in other parts of the boot process. An example would
## be injecting it to the initramfs of the target boot environment in order to avoid
## asking the user again to unlock a luks volume that has already been unlocked.
##
## Because this script is intended to unlock volumes *before* ZFSBootMenu
## imports ZFS pools, it should be run as an early hook.

sources=(
  /lib/profiling-lib.sh
  /etc/zfsbootmenu.conf
  /lib/zfsbootmenu-core.sh
  /lib/kmsg-log-lib.sh
  /etc/profile
)

for src in "${sources[@]}"; do
  # shellcheck disable=SC1090
  if ! source "${src}" > /dev/null 2>&1; then
    echo -e "\033[0;31mWARNING: ${src} was not sourced; unable to proceed\033[0m"
    exit 1
  fi
done

unset src sources

keydir="/tmp/keydir/etc/cryptsetup-keys.d"

luks_unlock() {
  local partition="$1"
  local mapping="$2"
  local passwd="$3"

  if [ ! -b "${partition}" ]; then
    zinfo "device ${partition} does not exist"
    return 1
  fi

  if ! cryptsetup isLuks ${partition} >/dev/null 2>&1; then
    zwarn "device ${partition} missing LUKS partition header"
    return 1
  fi

  if cryptsetup status "${mapping}" >/dev/null 2>&1; then
    zinfo "${mapping} already active, not continuing"
    return 1
  fi

  echo "${passwd}" | cryptsetup luksOpen "${partition}" "${mapping}" -
  local ret=$?

  if [ "${ret}" -eq 0 ]; then
    zdebug "$(
      cryptsetup status "${mapping}"
      mount | grep "${mapping}"
    )"
    return 0
  elif [ "${ret}" -eq 2 ]; then
    emergency_shell "unable to unlock LUKS partition"
    return 1
  fi
}

unlock_partitions() {
  local partitions=($(lsblk -lpnf -o NAME,UUID,FSTYPE | awk '/crypto_LUKS/{print $1 "=luks-" $2}'))
  if [ ${#partitions[@]} -eq 0 ]; then
    zinfo "no encrypted luks partitions found, skipping unlock"
    return 1
  fi

  read -r -s -p "Enter passphrase for encrypted partitions: " passphrase
  echo -e "\nUnlocking..."

  for p in "${partitions[@]}"; do
    IFS='=' read -r partition mapping <<< "$p"

    zinfo "unlocking device ${partition} to mapping ${mapping}"
    luks_unlock "${partition}" "${mapping}" "${passphrase}"

    local keyfile="${keydir}/${mapping}.key"
    mkdir -p "${keydir}"
    echo -n "${passphrase}" > "${keyfile}"
    chmod 0600 "${keyfile}"
    unset partition mapping
  done
}

unlock_partitions
