# steam-frame-nixos

NixOS modules that run Valve's VR stack (SteamVR, Steam, gamescope) on the Steam Frame.

It boots from internal slot A through Valve's own U-Boot and never writes the bootloader, firmware, U-Boot environment or SteamOS on slot B. The one boot-state write marks slot A good after each boot, as SteamOS does for its slot.

Works: boot, Wi-Fi, SSH, charging, fan, tracking, controllers, speakers, SteamVR and Steam login. Not verified: games, suspend.

## Use

```sh
nix flake init -t github:y0usaf/steam-frame-nixos
```

This gives you a flake with `nixosConfigurations.frame`. Add your SSH key in `configuration.nix` and build with this flake's `inputs.nixpkgs`, the pin Valve's sources are built against.

Options under `frame.`:

- `authorizedKeys`: SSH keys for root and `steamos`; required.
- `storage.poolUuid`: put root, `/nix`, `/home`, `/games` and `/var` on a Btrfs pool on the old SteamOS home partition (subvolumes `@root`, `@nix`, `@home`, `@games`, `@var`, `@steamos-data`). Null keeps root on slot A.
- `session.fhsPackages`: extra apps in Steam's + menu.
- `wivrn.enable`, `framecorder.enable`, `framecolor.enable`: optional apps, off by default.

`nixosModules.recovery` is a minimal system with no VR session. A pool system falls back to it when the pool won't mount or after four boots that never came up.

## Install

1. `sudo tools/binfmt.sh` once, to build aarch64 on x86_64.
2. Put your public keys in `authorized_keys` (gitignored) and the `esp` and `efi-A` partitions of Valve's recovery image in `valve/`.
3. `tools/stage-slotA.sh <nm-connection>` builds the slot-A image with your Wi-Fi.
4. From SteamOS booted on slot B: `tools/write-slotA.sh`.
5. To boot NixOS, hold Power until the LED is off, then power on holding AUX and pick "Previous".

After that, `tools/deploy.sh FLAKE#nixosConfigurations.NAME` builds and switches the Frame at `FRAME_HOST` without interrupting a running game.

## Depends on

Valve's SteamOS 0.5.x sources (kernel 6.18, Mesa fork, steamos-manager, powerbuttond) and Valve binaries with no published source (SteamVR, Steam, FPGA image, hardware tools), all fetched and pinned by hash.

## License

[LICENSE](LICENSE) allows use with credit, except in or for one named project; it is not open source. [NOTICE](NOTICE) lists third-party parts.
