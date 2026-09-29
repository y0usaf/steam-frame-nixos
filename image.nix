{
  runCommand,
  closureInfo,
  btrfs-progs,
  dosfstools,
  mtools,
  e2fsprogs,
  util-linux,
  ubootTools,
  zstd,
  nixos,
  bootUuid,
}:
let
  inherit (nixos.config.system.build) toplevel initialRamdisk;
  kernel = nixos.config.boot.kernelPackages.kernel;
  closure = closureInfo { rootPaths = [ toplevel ]; };
in
runCommand "frame-nixos-usb"
  {
    nativeBuildInputs = [
      btrfs-progs
      dosfstools
      mtools
      e2fsprogs
      util-linux
      ubootTools
      zstd
    ];
  }
  ''
    root=$PWD/root
    mkdir -p $root/nix/store $root/nix/var/nix/profiles $root/sbin $root/boot/dtbqcom $root/etc
    for d in dev proc sys run tmp var home root mnt; do mkdir -p $root/$d; done
    xargs -a ${closure}/store-paths cp -a -t $root/nix/store/
    ln -s ${toplevel} $root/nix/var/nix/profiles/system-1-link
    ln -s system-1-link $root/nix/var/nix/profiles/system
    ln -s /nix/var/nix/profiles/system/init $root/sbin/init
    touch $root/etc/NIXOS
    cp ${kernel}/Image $root/boot/Image
    cp ${kernel}/dtbs/qcom/sm8650-*.dtb $root/boot/dtbqcom/
    cp ${kernel}/dtbs/qcom/sm8650-mp.dtb $root/boot/maindtb.dtb
    mkimage -A arm64 -O linux -T ramdisk -C none -a 0 -e 0 -n "" -d ${initialRamdisk}/initrd $root/boot/initrd.uImage

    rootBytes=$((10485760 * 512))
    truncate -s $rootBytes rootfs.img
    unshare --map-root-user mkfs.btrfs -q -f -M -n 4096 -O ^block-group-tree -L rootfs-A -U ${bootUuid} --shrink --rootdir $root rootfs.img
    test "$(stat -c %s rootfs.img)" -le $rootBytes
    test "$(btrfs inspect-internal dump-super rootfs.img | awk '$1 == "total_bytes" { print $2 }')" -le $rootBytes

    mkfs.vfat -C -F 32 -s 1 -n esp -i 64b64be9 esp.img $((524288 / 2)) >/dev/null
    mcopy -s -i esp.img ${./valve/esp}/* ::/
    mkfs.vfat -C -F 32 -s 1 -n efi -i 3c6a1f07 efi.img $((131072 / 2)) >/dev/null
    mcopy -s -i efi.img ${./valve/efi-A}/* ::/
    truncate -s 256M var.img
    mkfs.ext4 -q -F -L var var.img
    truncate -s 100M home.img
    mkfs.ext4 -q -F -L home home.img

    truncate -s $((14680064 * 512)) disk.img
    sfdisk -q --no-reread --no-tell-kernel disk.img <<EOF
    label: gpt
    label-id: EEBC5599-EDBA-435F-A6DE-53B158BDFEE5
    first-lba: 34
    unit: sectors

    start=34, size=524288, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, uuid=E45D21C1-3EBC-47ED-8132-64D137AB159C, name="esp"
    start=524322, size=131072, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=CDD35965-5B53-46DD-83F3-B144513E8A88, name="efi-A"
    start=655394, size=10485760, type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709, uuid=0EE15513-80CF-4627-813F-D05477340F0B, name="rootfs-A"
    start=11141154, size=524288, type=4D21B016-B534-45C2-A9FB-5C16E091FD2D, uuid=9178C784-190A-41BC-92C9-A3A7C8F875DB, name="var-A"
    start=11665442, size=204800, type=933AC7E1-2EB4-4F13-B844-0E14E2AEF915, uuid=9A9925C0-DF38-4D64-9031-F06C92D21538, name="home"
    EOF
    dd if=esp.img of=disk.img bs=512 seek=34 conv=notrunc,sparse status=none
    dd if=efi.img of=disk.img bs=512 seek=524322 conv=notrunc,sparse status=none
    dd if=rootfs.img of=disk.img bs=512 seek=655394 conv=notrunc,sparse status=none
    dd if=var.img of=disk.img bs=512 seek=11141154 conv=notrunc,sparse status=none
    dd if=home.img of=disk.img bs=512 seek=11665442 conv=notrunc,sparse status=none

    mkdir -p $out
    sfdisk -d disk.img > $out/partitions.txt
    zstd -q -T0 -9 disk.img -o $out/frame-nixos-usb.img.zst
  ''
