# steam-frame-nixos

Runs NixOS with Valve's VR session (SteamVR, Steam, gamescope) on the Steam Frame from internal slot A, booted by Valve's U-Boot. It never writes the bootloader, firmware, U-Boot environment, battery or controller-radio firmware, or SteamOS on slot B.

This is a spike, verified on one Frame on 2026-09-28.

- **Works:** unattended boot, Wi-Fi through NetworkManager with the MAC from the EEPROM (as on SteamOS), SSH, charging, fan, LEDs, inside-out tracking, controllers, SteamVR direct mode, the SteamVR dashboard, and Steam login in the headset.
- **Not yet verified:** games, suspend.
- **Not verified yet:** Steam's Wi-Fi toggle and network settings.
- **Muted:** the speakers, until Valve's speaker calibration is wired in.

## Not in this repo

`valve/` holds files taken from a Frame and is gitignored:

- `valve/kernel.config`: `zcat /proc/config.gz` on the Frame's SteamOS.
- `valve/esp/` and `valve/efi-A/`: the `esp` and `efi-A` partitions of Valve's recovery image. Only the USB image needs these.

`authorized_keys` (also gitignored) holds the SSH public keys allowed to log in as root and `steamos`.

Everything else comes from Valve's public package repo, pinned by hash. The builds use `path:` flake refs so that these git-ignored files are visible.

## Use

Building aarch64 on x86_64 needs qemu binfmt: `sudo tools/binfmt.sh`.

- `tools/deploy.sh` builds, copies and switches a running Frame at `FRAME_HOST`, then prints the system path.
- `tools/stage-slotA.sh <nm-connection>` builds the image and injects Wi-Fi.
- `tools/write-slotA.sh` then writes slot A over SSH from SteamOS. It refuses unless SteamOS booted from slot B, and it needs passwordless sudo for `steamos` there.

To boot NixOS, hold Power until the LED goes off, then power on while holding AUX and choose "Previous". A normal power-on still boots SteamOS.

## License

[LICENSE](LICENSE) lets anyone use, copy, modify and distribute this with credit, except in or for one named project. It is not an open-source license. [NOTICE](NOTICE) lists the third-party parts it does not cover.
