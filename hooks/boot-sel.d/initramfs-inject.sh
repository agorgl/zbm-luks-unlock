#!/bin/bash

## This boot-sel hook attempts to inject keyfiles for LUKS volumes in the
## initramfs, reducing the number of password requests made to the user.
##
## A temporary in-memory location is created where the kernel and initramfs
## from the selected boot environment are copied to. After that, the fresh
## initramfs copy is resized to align to a 4-byte boundary. This allows appending
## additional initramfs segments, that are overlayed on top of the original
## initramfs. A cpio archive with the keyfiles is then created and appended to
## the initramfs copy.
##
## In order to use the new initramfs, the old boot environment is unmounted
## and an empty in-memory filesystem is created in its place mirroring the boot
## environment's filesystem structure for the kernel and the initramfs.
## The kernel and initramfs are copied back into their original locations
## in the new filesystem, and the boot process continues normally, while
## ZFSBootMenu loads the new initramfs in place, containing the keyfiles.
##
## Usage of the keyfiles depends on the kernel parameters passed and the
## functionality contained in the initramfs.

sources=(
  /lib/zfsbootmenu-core.sh
  /lib/kmsg-log-lib.sh
)

for src in "${sources[@]}"; do
  # shellcheck disable=SC1090
  if ! source "${src}" > /dev/null 2>&1; then
    echo -e "\033[0;31mWARNING: ${src} was not sourced; unable to proceed\033[0m"
    exit 1
  fi
done

unset src sources

# Make sure key environment variables are defined
[ -n "${ZBM_SELECTED_BE}" ] || exit 0
[ -n "${ZBM_SELECTED_KERNEL}" ] || exit 0
[ -n "${ZBM_SELECTED_INITRAMFS}" ] || exit 0
[ -n "${ZBM_SELECTED_MOUNTPOINT}" ] || exit 0

keydir="/tmp/keydir"

initramfs_append() {
  local initramfs="$1"
  local newdir="$2"

  # To append an additional initramfs segment,
  # the new archive must aligned to a 4-byte boundary:
  # https://unix.stackexchange.com/a/737219
  local initramfs_size=$(stat -c '%s' "${initramfs}")
  initramfs_size=$(((initramfs_size + 3) / 4 * 4))
  truncate -s "${initramfs_size}" "${initramfs}"

  # Create and append cpio archive to initramfs
  pushd "${newdir}"
  find . -mindepth 1 -print0 | cpio -0o -H newc --quiet >> "${initramfs}"
  popd
}

inject_keydir() {
  # Find kernel and initramfs to be loaded
  local mnt="${ZBM_SELECTED_MOUNTPOINT}"
  local kernel="${mnt}${ZBM_SELECTED_KERNEL}"
  local initramfs="${mnt}${ZBM_SELECTED_INITRAMFS}"

  # Make temp in-memory location
  local temp="/tmp/krn/"
  mkdir -p "${temp}"
  mount -t tmpfs tmpfs "${temp}"

  # Copy kernel and initramfs in temp
  local temp_kernel="${temp}${kernel##*/}"
  local temp_initramfs="${temp}${initramfs##*/}"
  cp "${kernel}" "${temp_kernel}"
  cp "${initramfs}" "${temp_initramfs}"

  # Append keydir to initramfs copy
  initramfs_append "${temp_initramfs}" "${keydir}" &> /dev/null

  # Replace mnt with new in-memory location
  umount "${mnt}"
  mkdir -p "${mnt}"
  mount -t tmpfs tmpfs "${mnt}"

  # Copy the updated kernel/initramfs in their original place
  mkdir -p "${kernel%/*}"
  mkdir -p "${initramfs%/*}"
  cp "${temp_kernel}" "${kernel}"
  cp "${temp_initramfs}" "${initramfs}"

  # Cleanup temp location
  umount "${temp}"
  rm -rf "${temp}"
}

if [ -d "${keydir}" ]; then
  inject_keydir
fi
