# steam-frame-nixos

NixOS modules that run Valve's VR session (SteamVR, Steam, gamescope) on the Steam Frame, booted from internal slot A by Valve's U-Boot. It never writes the bootloader, firmware, U-Boot environment, battery or controller-radio firmware, or SteamOS on slot B. Its only write to boot state marks slot A good after each boot, as SteamOS does for its own slot.

This is a spike. The original slot-A layout was verified on one Frame on 2026-09-28; booting the shared-pool layout was verified on the same Frame on 2026-09-29.

- **Works:** unattended boot, Wi-Fi through NetworkManager with the MAC from the EEPROM (as on SteamOS), SSH, charging, fan, LEDs, inside-out tracking, controllers, the speakers with Valve's calibration and EQ, SteamVR direct mode, the SteamVR dashboard, and Steam login in the headset.
- **Not yet verified:** games, suspend.
- **Not verified yet:** Steam's Wi-Fi toggle and network settings.

## Use as a module

`nixosModules.default` makes a NixOS system a Frame: Valve's kernel, Mesa and firmware, the hardware services, the slot-A boot hook, the VR session, steamos-manager and powerbuttond. Build the system with this flake's nixpkgs (`inputs.nixpkgs`), the pin Valve's sources are built and verified against. Options:

- `frame.authorizedKeys`: SSH public keys for root and `steamos`. The build fails while it is empty.
- `frame.storage.poolUuid`: the shared Btrfs pool below; null keeps root on slot A.
- `frame.storage.slotAUuid`: slot A's filesystem, which the images format with the default.
- `frame.buildSystem`: the system that cross-compiles the kernel, `x86_64-linux` by default.
- `frame.session.fhsPackages`: packages added to `frame-fhs`, the FHS environment Steam runs in; their desktop entries appear in Steam's + menu. A module that runs something in the session takes the `frameSession` module argument: `inFhs` wraps a command in `frame-fhs`, and `valveMesaEnv` and `mesavars` give it Valve's Mesa.
- `frame.wivrn.enable`, `frame.framecorder.enable` and `frame.framecolor.enable`: the optional apps described below, off by default.

`modules/` holds the modules and `pkgs/` Valve's packages. `nixosConfigurations.frame-slotA` and `frame-recovery` are the bring-up systems the images carry, with nothing optional enabled.

## Not in this repo

`valve/` holds files taken from a Frame and is gitignored:

- `valve/esp/` and `valve/efi-A/`: the `esp` and `efi-A` partitions of Valve's recovery image. Only the USB image needs these.

`authorized_keys` (also gitignored) holds the SSH public keys the bring-up systems let log in as root and `steamos`. A system built from `nixosModules.default` sets `frame.authorizedKeys` itself and builds from a plain git checkout.

Everything else is fetched and pinned by hash. The image builds use `path:` flake refs so that these git-ignored files are visible.

## Sources

The system is built from the sources Valve published for SteamOS 0.5.x: the `.src.tar.gz` bundles on holo-packages, each holding the package's git repo at the shipped commit, or Valve's `evlaV` mirrors on GitHub, which carry the same commits. Valve's own GitLab, which the PKGBUILDs name, is private.

- **Kernel:** `pkgs/kernel.nix` builds Linux 6.18 at `733a4be` (stock `linux-618-deckard` 6.18.0+g733a4be78129-4) from `evlaV/deckard-linux` with `gabe_defconfig`, Valve's config file from that tree, so the release is `6.18.0-g733a4be78129` as on stock. It cross-compiles on `frame.buildSystem` (default `x86_64-linux`), since a native build under qemu would take hours. v4l2loopback is Valve's fork at `20251112.1`.
- **Graphics:** Mesa is Valve's fork at `e07916b4` (26.3.0-devel) with Valve's build options. Perfetto builds from the v56.1 SDK zip that Mesa's wrap names. The Turnip build ID `75d098cb…` comes from Valve's stock driver, because Valve sets it in a file they didn't publish; with it the Frame reports the same `pipelineCacheUUID` as Valve's stock Turnip. On the Frame on 2026-10-28, 206 Vulkan CTS cases (api.smoke, compute.pipeline.basic, glsl.builtin.function.common, glsl.loops) gave the same results on both drivers and wrote byte-identical shader caches. gamescope 3.16.30, SPIRV-Tools and SPIRV-Headers 1.4.363.0 and the Vulkan loader 1.4.309.0 (Valve holds the loader back on purpose) are upstream tags built with nixpkgs' recipes.
- **Also from source:** steamos-manager and steamos-powerbuttond (below), the VR session scripts (`deckard-steamvr-session` 1.7.0-4), the Steam bootstrap (1.0.0.85-5), the Steam cursors, fan control, the audio configuration, `splctl` and the firmware.
- **Valve binaries,** because no source is published: SteamVR, the Steam client, Valve's Vulkan layers (Fossilize, FDM injection, RPO), the FPGA image and the eeprom, hw-support, charger, LED and power-monitor tools.
- **Prebuilt for FEX:** the x86_64 guest root Valve ships at `/usr/share/guestos/fex-mesa`. `pkgs/valve.nix`'s `fexGuestRoot` unpacks Valve's three packages into one tree: glibc with the other libraries x86 games need, 32-bit ones included (`deckard-mesa-linux-deps-x86_64` 20260820-4), Mesa at the same `e07916b4` for both x86 arches with its `graphics_provider.json` (`deckard-mesa-linux-x86_64` 26.3.0-5), and the gamescope WSI layer (`deckard-gamescope-layer-x86_64` 3.16.30-4). `frame-fhs` mounts it read-only at that path.
- **Verified:** on the Frame on 2026-10-25, it boots `6.18.0-g733a4be78129` with v4l2loopback loaded, no unit fails, Steam logs on, and SteamVR and mado run. gamescope 3.16.30 and `vrcompositor` map this Mesa and loader 1.4.309.0; PipeWire, from nixpkgs, also brings its own loader 1.4.357.0 into gamescope.

## Storage

A system that sets `frame.storage.poolUuid` uses one Btrfs pool on the former SteamOS home partition (`/dev/sda8`), the pool with that UUID. Formatting the pool must retain the UUID the system names. The pool and these subvolumes must exist before boot:

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

- `tools/deploy.sh FLAKE#nixosConfigurations.NAME` builds that system, copies and switches a running shared-pool Frame at `FRAME_HOST`, then prints the system path. The switch doesn't restart Steam, SteamVR, gamescope or the FPGA, DSP and Wi-Fi MAC units, so it doesn't interrupt a game; they pick up changes at the next session start or boot. Initial migration must register the pool's system profile separately from the slot-A recovery profile.
- To update the recovery system, build `nixosConfigurations.frame-recovery`, copy it into slot A's store with `nix copy --to "ssh-ng://root@$FRAME_HOST?remote-store=local%3Froot%3D%2Fmnt%2Fframe-boot"`, then run `nix-env --store /mnt/frame-boot -p /mnt/frame-boot/nix/var/nix/profiles/<profile> --set <path>` on the Frame for `frame-recovery` and `system`. `/boot/recovery` needs new files only if the recovery kernel or initrd changed.
- `tools/stage-slotA.sh <nm-connection>` builds the image and injects Wi-Fi.
- `tools/write-slotA.sh` then writes slot A over SSH from SteamOS. It refuses unless SteamOS booted from slot B, and it needs passwordless sudo for `steamos` there.

Deployment uses `boot.loader.external` to update slot A's `Image`, DTBs and `initrd.uImage` through `/boot`. The hook checks the boot filesystem UUID and stages the files on that filesystem before replacing the active paths.

Valve's loader counts `BOOT_COUNT_A` down on every normal boot and treats slot A as bad at zero. Once `sshd` is up, `frame-slot-good.service` runs Valve's `splctl set-state A good`, the call SteamOS's `steamos-boot.service` makes for its own slot, and logs the remaining count. That sets `BOOT_STATE_A=1`, and the next boot resets the count to 8 before taking one attempt: on 2026-09-29 a reboot took it from 5 to 7. Only the `bootenv` and `bootenvb` partitions are made writable, and only for that call.

To boot NixOS, hold Power until the LED goes off, then power on while holding AUX and choose "Previous". A normal power-on selects SteamOS on slot B, subject to its home mount configuration described above.

## WiVRn

`frame.wivrn.enable` adds the WiVRn client, built from nixpkgs' WiVRn source, so it matches the server in `packages.x86_64-linux.wivrn-server`: WiVRn 26.9 at the current nixpkgs pin. A client refuses any server with a different protocol, and the protocol changes between WiVRn releases.

- Steam's + menu lists it as WiVRn, and `systemctl --user start wivrn-client` starts it over SSH.
- On the PC, run `nix run path:.#wivrn-server -- --no-publish-service` and accept TCP and UDP 9757. The flag skips avahi, so add the PC in the headset's WiVRn lobby with "Add server", its IP and port 9757.
- The first connection asks for the PIN the server prints at startup.
- **Verified:** on the Frame, Steam's FHS has the WiVRn entry and the 26.9 client with no missing libraries, and the PC's port 9757 is reachable from the Frame.
- **Not verified:** pairing, a connection and streaming.

## framecorder

`frame.framecorder.enable` adds [framecorder](https://github.com/coah80/framecorder) 0.1.1 from its release tag. It records what the panels show, with a tab in the SteamVR dashboard and Wi-Fi sync to framecorder's apps. Nix replaces framecorder's installer and updater, so `framecorder-setup` is not installed.

- `framecorder-ui`, the tab, starts and stops with SteamVR. It runs in the FHS environment, where `/opt/steamvr` and Valve's Mesa are, and starts the recorder. Steam's + menu lists it as framecorder.
- Reading the panels needs `CAP_SYS_ADMIN`. Bubblewrap sets no_new_privs, so a helper with a file capability gets nothing inside the FHS environment. Instead, `framecorder-grab.socket` listens on `/run/framecorder-grab.sock`, and each connection starts `framecorder-grab@.service` outside the FHS environment, as `steamos`, with only that capability and only `/dev/dri/card0`. `modules/framecorder/grab-socket.patch` makes the recorder connect there when the socket exists, instead of starting the helper itself.
- `framecorder-sync` runs as a user service of `steamos` and listens on TCP 38619, which the firewall opens.
- The update check in framecorder's apps fails, since `framecorder-setup` is not installed.
- **Verified:** on the Frame on 2026-10-03. The tab registers with SteamVR, and `framecorder --duration 6` read the panels through `framecorder-grab@.service` and saved 1920x1080 HEVC at 72 fps with no dropped frames, 1.26 ms of GPU per frame, and a game-audio track. A second recording, with the headset in use, shows the passthrough view. `framecorder-sync` listens on 38619.
- **Not verified:** the tab's controls in the headset, the mic and pairing a sync device.

## framecolor-sharp

`frame.framecolor.enable` adds [framecolor-sharp](https://github.com/guix8/framecolor-sharp) at `bb6ac2e`: a vkBasalt layer in vrcompositor that corrects colour with a LUT and sharpens with CAS, and a SteamVR dashboard overlay that tunes both. Nix replaces its installer, which puts everything in the home directory.

- `framecolorctl enable` turns it on: it copies the layer's manifest to `~/.local/share/framecolor/layer/`, enables `framecolor.service` (the overlay) and restarts SteamVR. `framecolorctl disable` turns both off and restarts SteamVR. Run it before switching the option off, or `~/.config/systemd/user/steamvr.service.wants/` keeps a link to the removed unit.
- `steamvr.service` gets the layer's environment and upstream's startup guard: if SteamVR fails within 10 s of starting with the layer on, the guard moves the manifest aside. `framecolorctl guard 3` allows three failures first.
- The layer rereads `~/.config/framecolor/current.txt`, which the overlay writes, every 50 ms, so changes show without a restart.
- The overlay and `framecolorctl` run in `frame-fhs`, since both load SteamVR's client library from `/opt/steamvr`. `framecolorctl bench` and `bench --compare A B` measure vrcompositor's GPU time.
- Only the Regular and Bold Noto CJK fonts the overlay draws with are copied into the package.
- **Not verified:** anything on the Frame.

## SteamOS Manager and the power button

`steamos-manager.nix` builds Valve's [steamos-manager](https://gitlab.steamos.cloud/holo/steamos-manager) 26.4.1 at `304a0816`, and `powerbuttond.nix` builds [steamos-powerbuttond](https://gitlab.steamos.cloud/holo/powerbuttond) at `4403691c` (3.2+git4403691c), the commits stock 0.5.x ships. Neither commit is in the public repos, so both come from Valve's source bundles.

- steamos-manager runs as the stock Frame runs it: a root daemon (`steamos-manager -r`, `steamos-manager.service`) and a user daemon that starts with the graphical session. The package carries the D-Bus activation files and the bus policy (only root owns the system name), and `steamosctl` is on `PATH`. The hardcoded `/usr/share/steamos-manager` is patched to the package.
- It installs Valve's `steam-frame.toml` and `platform.toml`. `steam-frame.toml` drives the GPU through devfreq (`3d00000.gpu`) and has custom CPU profiles (Performance, Balanced, Powersave) that cap each cpufreq policy's `scaling_max_freq`, Powersave also capping the GPU at 629 MHz. The helper scripts `platform.toml` names (factory reset, BIOS and dock updates, trim and format) are not installed; the stock Frame has only a BIOS-update stub that exits 0, so Steam sees those features as unsupported, as on stock.
- The root daemon opens a tracefs instance at `/sys/kernel/tracing/instances/steamos-log-submitter` at start and exits without it. `gabe_defconfig` has `FTRACE`.
- powerbuttond is a user service wanted by and requiring `steamvr.service`, as on stock, and logind ignores the power key (`HandlePowerKey=ignore`) so a press reaches only Steam. upower's critical-battery action stays at the NixOS default: that shutdown is the only low-battery guard here, since the Frame has no vpower service and nothing shows Steam shutting down the machine itself. Upstream's udev rule and hwdb are installed; the hwdb tags `pmic_pwrkey` as the power button. On aarch64 it calls the Steam client at `~/.steam/steam/steamrtarm64/steam`. That client is a dynamically linked Valve binary NixOS can't exec directly, so the unit runs powerbuttond inside `frame-fhs`, the same environment Steam runs in, and the client it spawns on each press starts there.
- **Differs from stock:** the stock powerbuttond unit skips the daemon on the single-button EV1 dev kit (`vrdevice_path model != EV1`); that check is left out. There is no steamos-log-submitter, no `remotes.d` entry and no polkit rule (the stock manager package ships none), and the stock package's sddm drop-in, `orca.service`, `steamos-configure-cecd.service` and `steamos-manager-session-cleanup.service` are not installed. Without SDDM's `holo.conf` the user daemon never exports `SessionManagement1`, so the cleanup oneshot could only fail, and there are no SDDM temporary logins for it to clean.
- **Verified:** on the Frame on 2026-10-25, both daemons run, the root one with the real tracefs instance, and `steamosctl get-all-properties` answers. powerbuttond finds `pmic_pwrkey` at `/dev/input/event0`, which udev tags `STEAMOS_POWER_BUTTON=1`.
- **Device match:** stock `steam-frame.toml` requires `/proc/device-tree/board-info/board_revision`, and the Frame's device tree has no `board-info` node under this kernel's dtbs or Valve's binary ones; neither dtbs nor U-Boot's partitions contain the string, so something on the stock boot path must add it. The build requires `/proc/device-tree/fpga` instead, which the Frame's tree has, next to the unchanged `qcom,sm8650` compatible. Without a match `DeviceModel` is `unknown` and the GPU performance and CPU profile interfaces are missing.
- **Not verified:** Steam's Power and Controller settings talking to it, and a power-button press reaching Steam.

## License

[LICENSE](LICENSE) lets anyone use, copy, modify and distribute this with credit, except in or for one named project. It is not an open-source license. [NOTICE](NOTICE) lists the third-party parts it does not cover.
