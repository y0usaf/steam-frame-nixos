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

- `tools/deploy.sh` builds `frame`, copies and switches a running shared-pool Frame at `FRAME_HOST`, then prints the system path. The switch doesn't restart Steam, SteamVR, gamescope or the FPGA, DSP and Wi-Fi MAC units, so it doesn't interrupt a game; they pick up changes at the next session start or boot. Initial migration must register the pool's system profile separately from the slot-A recovery profile.
- To update the recovery system, build `nixosConfigurations.frame-recovery`, copy it into slot A's store with `nix copy --to "ssh-ng://root@$FRAME_HOST?remote-store=local%3Froot%3D%2Fmnt%2Fframe-boot"`, then run `nix-env --store /mnt/frame-boot -p /mnt/frame-boot/nix/var/nix/profiles/<profile> --set <path>` on the Frame for `frame-recovery` and `system`. `/boot/recovery` needs new files only if the recovery kernel or initrd changed.
- `tools/stage-slotA.sh <nm-connection>` builds the image and injects Wi-Fi.
- `tools/write-slotA.sh` then writes slot A over SSH from SteamOS. It refuses unless SteamOS booted from slot B, and it needs passwordless sudo for `steamos` there.

Deployment uses `boot.loader.external` to update slot A's `Image`, DTBs and `initrd.uImage` through `/boot`. The hook checks the boot filesystem UUID and stages the files on that filesystem before replacing the active paths.

Valve's loader counts `BOOT_COUNT_A` down on every normal boot and treats slot A as bad at zero. Once `sshd` is up, `frame-slot-good.service` runs Valve's `splctl set-state A good`, the call SteamOS's `steamos-boot.service` makes for its own slot, and logs the remaining count. That sets `BOOT_STATE_A=1`, and the next boot resets the count to 8 before taking one attempt: on 2026-09-29 a reboot took it from 5 to 7. Only the `bootenv` and `bootenvb` partitions are made writable, and only for that call.

To boot NixOS, hold Power until the LED goes off, then power on while holding AUX and choose "Previous". A normal power-on selects SteamOS on slot B, subject to its home mount configuration described above.

## Omarchy

`omarchy.nix` runs the desktop layer of [Omarchy](https://github.com/basecamp/omarchy) 4.0.4 (Hyprland and its QuickShell shell) as a window over SteamVR. It is not the Arch ISO, and it is not part of the default session: nothing starts it at boot and the VR session runs without it.

- `systemctl --user start omarchy` and `systemctl --user stop omarchy`, over SSH. It is a SteamVR overlay, so it is not in the library list. It stops whenever SteamVR restarts and stays stopped until started again.
- A nested Hyprland runs as a client of a second gamescope (`--backend openvr --expose-wayland`). Aquamarine needs the three fixes in `omarchy/aquamarine-gamescope.patch`.
- `ExecStopPost` removes what Hyprland and Quickshell leave in `$XDG_RUNTIME_DIR`. Omarchy's own state stays in the real home (`~/.config/omarchy`, `~/.local/state/omarchy`, `~/.cache`).
- Omarchy's menu actions for power, audio, Wi-Fi and Bluetooth act on the host's services, not on the overlay.
- The bar reads Wi-Fi from NetworkManager over D-Bus. Quickshell 0.3.1 ignores a saved profile without `mode=infrastructure`, so `tools/wifi-from-nm.py` writes it.
- **Verified:** on the Frame, Hyprland nested in gamescope draws the bar, wallpaper, menu and a foot terminal on the GPU (screenshots taken inside Hyprland). As an overlay on the live SteamVR session it starts, the bar shows the Wi-Fi state, and one 15-minute run had no crash or error.
- **Not verified:** how it looks in the headset, shortcut keys (headset input is a pointer and a virtual keyboard), theme switching, audio, Bluetooth and power actions, and a clean stop of the deployed unit.
- **Unavailable:** screen recording (`gpu-screen-recorder` is not installed and `~/Videos` does not exist), the screensaver (`ttfx` is not installed) and the lock screen (`/etc/pam.d/omarchy-lock-password` does not exist, so it refuses to lock). The idle timers for the last two do nothing.

## WiVRn

`wivrn.nix` builds the WiVRn client from nixpkgs' WiVRn source, so it matches the server in `packages.x86_64-linux.wivrn-server`: WiVRn 26.9 at the current nixpkgs pin. A client refuses any server with a different protocol, and the protocol changes between WiVRn releases.

- Steam's + menu lists it as WiVRn, and `systemctl --user start wivrn-client` starts it over SSH.
- On the PC, run `nix run path:.#wivrn-server -- --no-publish-service` and accept TCP and UDP 9757. The flag skips avahi, so add the PC in the headset's WiVRn lobby with "Add server", its IP and port 9757.
- The first connection asks for the PIN the server prints at startup.
- **Verified:** on the Frame, Steam's FHS has the WiVRn entry and the 26.9 client with no missing libraries, and the PC's port 9757 is reachable from the Frame.
- **Not verified:** pairing, a connection and streaming.

## framecorder

`framecorder.nix` builds [framecorder](https://github.com/coah80/framecorder) 0.1.1 from its release tag. It records what the panels show, with a tab in the SteamVR dashboard and Wi-Fi sync to framecorder's apps. Nix replaces framecorder's installer and updater, so `framecorder-setup` is not installed.

- `framecorder-ui`, the tab, starts and stops with SteamVR. It runs in the FHS environment, where `/opt/steamvr` and Valve's Mesa are, and starts the recorder. Steam's + menu lists it as framecorder.
- Reading the panels needs `CAP_SYS_ADMIN`. Bubblewrap sets no_new_privs, so a helper with a file capability gets nothing inside the FHS environment. Instead, `framecorder-grab.socket` listens on `/run/framecorder-grab.sock`, and each connection starts `framecorder-grab@.service` outside the FHS environment, as `steamos`, with only that capability and only `/dev/dri/card0`. `framecorder/grab-socket.patch` makes the recorder connect there when the socket exists, instead of starting the helper itself.
- `framecorder-sync` runs as a user service of `steamos` and listens on TCP 38619, which the firewall opens.
- The update check in framecorder's apps fails, since `framecorder-setup` is not installed.
- **Verified:** on the Frame on 2026-10-03. The tab registers with SteamVR, and `framecorder --duration 6` read the panels through `framecorder-grab@.service` and saved 1920x1080 HEVC at 72 fps with no dropped frames, 1.26 ms of GPU per frame, and a game-audio track. A second recording, with the headset in use, shows the passthrough view. `framecorder-sync` listens on 38619.
- **Not verified:** the tab's controls in the headset, the mic and pairing a sync device.

## Beat Saber mods

`beat-saber.nix` installs [BeatMods](https://beatmods.com) mods into Beat Saber by name. `frame.beatSaber.mods` in `flake.nix` lists them; BSIPA, the mod loader, and each mod's dependencies come along. `beat-saber/beatmods.json` pins every verified mod for one game version, with hashes, and `tools/beatmods-lock.sh <game version>` regenerates it. A name that isn't in it fails the build.

- BeatMods has mods for 1.44.1 and none for 1.45, so Beat Saber needs Steam's `1.44.1_legacy` branch (Properties, Game Versions & Betas).
- Beat Saber's launch options must be `/run/current-system/sw/bin/beat-saber-mods %command%`. At each launch it copies the declared set into the game folder, deletes files of the previous set that are no longer declared, and starts the game with `WINEDLLOVERRIDES=winhttp=n,b`, so that Proton loads BSIPA's `winhttp.dll`, and with `--no-yeet`, so that BSIPA doesn't move the mods aside after a version change. The set includes `IPA.exe`: BSIPA skips every mod when a file its manifest lists is missing, and it only runs `IPA.exe` when that is newer than itself.
- BSIPA patches `Beat Saber_Data/Managed/UnityEngine.CoreModule.dll` at its first start. `.nix-mods/` in the game folder holds an unpatched copy and the list of installed files. With an empty list, or a game version the mods aren't for, the next launch removes the mods, restores that file and starts the game without them. It also removes empty folders that weren't there before the first install. `UserData`, `Logs` and files you added yourself stay.
- To remove the module, empty the list and launch once, then clear the launch options.
- The wrapper logs problems to Steam's journal: `journalctl --user -u steam | grep beat-saber-mods`.
- **Verified:** on the Frame on 2026-10-03, Beat Saber 1.44.1 under Proton 11.0 (ARM64) loads BSIPA 4.3.7, SongCore, BeatSaverDownloader and their dependencies, 11 plugins in all, and BeatSaverDownloader downloads songs from the menu. Removing the mods restored the unpatched file and left `UserData`, `Logs` and the downloaded songs.
- **Broken:** with those mods, starting any song fails under Proton 11.0 (ARM64). An InvalidCastException in Zenject injection and in MonoMod's struct-return glue (`AbiFixup` for `ColorManager.ColorForSaberType`) leaves the level frozen with NullReferenceExceptions every frame. `flake.nix` lists no mods until that's fixed.
- **Not verified:** whether the game without mods plays the downloaded songs in `CustomLevels`.

## License

[LICENSE](LICENSE) lets anyone use, copy, modify and distribute this with credit, except in or for one named project. It is not an open-source license. [NOTICE](NOTICE) lists the third-party parts it does not cover.
