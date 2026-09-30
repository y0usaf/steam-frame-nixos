# steam-frame-nixos

Runs NixOS with Valve's VR session (SteamVR, Steam, gamescope) on the Steam Frame, booted from internal slot A by Valve's U-Boot. It never writes the bootloader, firmware, U-Boot environment, battery or controller-radio firmware, or SteamOS on slot B. Its only write to boot state marks slot A good after each boot, as SteamOS does for its own slot.

This is a spike. The original slot-A layout was verified on one Frame on 2026-09-28; booting the shared-pool layout was verified on the same Frame on 2026-09-29.

- **Works:** unattended boot, Wi-Fi through NetworkManager with the MAC from the EEPROM (as on SteamOS), SSH, charging, fan, LEDs, inside-out tracking, controllers, the speakers with Valve's calibration and EQ, SteamVR direct mode, the SteamVR dashboard, and Steam login in the headset.
- **Not yet verified:** games, suspend.
- **Not verified yet:** Steam's Wi-Fi toggle and network settings.

## Not in this repo

`valve/` holds files taken from a Frame and is gitignored:

- `valve/kernel.config`: `zcat /proc/config.gz` on the Frame's SteamOS.
- `valve/esp/` and `valve/efi-A/`: the `esp` and `efi-A` partitions of Valve's recovery image. Only the USB image needs these.

`authorized_keys` (also gitignored) holds the SSH public keys allowed to log in as root and `steamos`.

Everything else comes from Valve's public package repo, pinned by hash. The builds use `path:` flake refs so that these git-ignored files are visible.

## Storage

`nixosConfigurations.frame` uses one Btrfs pool on the former SteamOS home partition (`/dev/sda8`). `frame.storage.poolUuid` selects the pool; the current configuration targets `4bac5c02-4a89-4377-8388-ce55ef171552`, the previous home filesystem's UUID. Formatting the pool must retain that UUID. The pool and these subvolumes must exist before boot:

| Mount | Subvolume |
| --- | --- |
| `/` | `@root` |
| `/nix` | `@nix` |
| `/home` | `@home` |
| `/games` | `@games` |
| `/var` | `@var` |
| `/mnt/steamos-data` | `@steamos-data` |

These share the pool's free space and use `compress=zstd:3,noatime`. Steam's `/home/steamos/.local/share/Steam/steamapps` is a bind mount of `/games`. `@steamos-data` holds the preserved SteamOS home data separately from NixOS's home.

The live migration restored the original root and home archives, verified the Nix store contents and compared all restored home data against its archive before rebooting. Root, Nix store, home, games and var mounted from the pool after reboot; Steam, SteamVR and gamescope were active with no failed system or user units. Game launch and suspend remain unverified.

Slot A remains the boot carrier. Its top-level filesystem mounts at `/mnt/frame-boot`, and `/boot` binds `/mnt/frame-boot/boot`, keeping Valve's kernel, DTB and initrd paths available. Calibration stays on the separate read-only `/persist` mount.

- `nixosConfigurations.frame-slotA` retains the original layout: root on slot A, with the NixOS user home bound from `nixos-home/steamos` on the ext4 SteamOS home partition.
- `nixosConfigurations.frame-recovery` is a minimal slot-A system with Wi-Fi, root SSH and migration tools. Its root and home are local to slot A, so it can start while the shared pool is unavailable.
- `packages.x86_64-linux.image` contains `frame-slotA`; `packages.x86_64-linux.recovery-image` contains `frame-recovery`. Both format their root image with the fixed slot-A UUID, independently of the pool UUID.

The slot-A recovery system profile and the pool's system profile must remain separate. Recovery assets and the independent slot-A system profile must be installed before attempting the pool boot.

The pool initrd falls back to recovery in two cases: when it reaches `emergency.target`, for example because the pool will not mount, and on the fourth consecutive pool boot that `frame-slot-good.service` has not marked good. `frame-boot-swap recovery` saves the active boot files to `/boot/pool` and installs `/boot/recovery`, then the initrd reboots; the emergency path reboots even if the swap fails. From recovery, `frame-boot-swap pool && systemctl reboot` restores the pool's files. Both triggers and the way back were verified on the Frame on 2026-09-29.

The fallback cannot help when the kernel or initrd fails before the initrd runs, or when recovery itself fails; Valve's loader then falls back to slot B once its counter runs out. Boot-file replacement updates each file individually; an interrupted update that changes the kernel can leave an incompatible kernel and initrd.

Stock SteamOS on slot B still specifies an ext4 home filesystem in its fstab. That configuration has not been patched for Btrfs, so converting `/dev/sda8` requires updating SteamOS's mount configuration before its normal home mount can work.

## Use

Building aarch64 on x86_64 needs qemu binfmt: `sudo tools/binfmt.sh`.

- `tools/deploy.sh` builds `frame`, copies and switches a running shared-pool Frame at `FRAME_HOST`, then prints the system path. Initial migration must register the pool's system profile separately from the slot-A recovery profile.
- To update the recovery system, build `nixosConfigurations.frame-recovery`, copy it into slot A's store with `nix copy --to "ssh-ng://root@$FRAME_HOST?remote-store=local%3Froot%3D%2Fmnt%2Fframe-boot"`, then run `nix-env --store /mnt/frame-boot -p /mnt/frame-boot/nix/var/nix/profiles/<profile> --set <path>` on the Frame for `frame-recovery` and `system`. `/boot/recovery` needs new files only if the recovery kernel or initrd changed.
- `tools/stage-slotA.sh <nm-connection>` builds the image and injects Wi-Fi.
- `tools/write-slotA.sh` then writes slot A over SSH from SteamOS. It refuses unless SteamOS booted from slot B, and it needs passwordless sudo for `steamos` there.

Deployment uses `boot.loader.external` to update slot A's `Image`, DTBs and `initrd.uImage` through `/boot`. The hook checks the boot filesystem UUID and stages the files on that filesystem before replacing the active paths.

Valve's loader counts `BOOT_COUNT_A` down on every normal boot and treats slot A as bad at zero. Once `sshd` is up, `frame-slot-good.service` runs Valve's `splctl set-state A good`, the call SteamOS's `steamos-boot.service` makes for its own slot, and logs the remaining count. That sets `BOOT_STATE_A=1`, and the next boot resets the count to 8 before taking one attempt: on 2026-09-29 a reboot took it from 5 to 7. Only the `bootenv` and `bootenvb` partitions are made writable, and only for that call.

To boot NixOS, hold Power until the LED goes off, then power on while holding AUX and choose "Previous". A normal power-on selects SteamOS on slot B, subject to its home mount configuration described above.

## License

[LICENSE](LICENSE) lets anyone use, copy, modify and distribute this with credit, except in or for one named project. It is not an open-source license. [NOTICE](NOTICE) lists the third-party parts it does not cover.
