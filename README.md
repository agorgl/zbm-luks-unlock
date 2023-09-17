# zbm-luks-unlock

A custom build of [ZFSBootMenu](https://zfsbootmenu.org) to allow unlocking and using zfs pools residing in luks volumes.

## Usage

1. Make sure either podman or docker is installed.

2. Clone the current repository

3. Fetch the latest zbm-builder.sh script from ZFSBootMenu repository

    ```
    curl -O https://raw.githubusercontent.com/zbm-dev/zfsbootmenu/master/zbm-builder.sh
    ```

4. Build a custom ZFSBootMenu image by using current repository as a build directory

    ```
    cd zbm-luks-unlock
    ./zbm-builder.sh -H
    ```

5. The newly built ZFSBootMenu image will reside in the `build` directory

## How it works

The hooks mechanism of ZFSBootMenu is used to inject two hooks into the boot process.

First is the `luks-unlock.sh` early-setup hook that prompts the user for the passphrase that unlocks the luks volumes.
This allows ZFSBootMenu to discover zfs pools residing in luks volumes. The passphrase is also stored a relevant keyfile
in memory to be used by the later hooks.

Second is the `initramfs-inject.sh` boot-sel hook that with a clever trick, injects the keyfile created by the previous hook
to the initramfs of the selected boot environment. This allows a properly configured system (either using kernel params or
a relevant /etc/crypttab file) to use this keyfile to automatically unlock the luks volumes to be used, without asking
again the user for the passphrase.

## License

This project is licensed under the same MIT license as ZFSBootMenu. Please see [`LICENSE`](./LICENSE) for details.
