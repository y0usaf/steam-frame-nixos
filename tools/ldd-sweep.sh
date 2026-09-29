find /opt/steamvr /usr/lib/libEGL_mesa.so.0 /usr/lib/libGLX_mesa.so.0 /usr/lib/libgallium-*.so /usr/lib/libvulkan_freedreno.so /usr/lib/gbm /usr/lib/dri/zink_dri.so /usr/lib/dri/msm_dri.so /usr/bin/gamescope /usr/lib/libVkLayer_* "$HOME/.local/share/Steam/steamrtarm64" "$HOME/.local/share/Steam/linuxarm64" -type f 2>/dev/null |
while read -r f; do
  [ "$(head -c 4 "$f" 2>/dev/null | tail -c 3)" = ELF ] || continue
  ldd "$f" 2>/dev/null | awk -v f="$f" '/not found/ { print $1 "\t" f }'
done | sort -u
