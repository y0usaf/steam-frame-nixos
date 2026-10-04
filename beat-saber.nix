{
  config,
  lib,
  pkgs,
  ...
}:
let
  lock = lib.importJSON ./beat-saber/beatmods.json;
  wanted = config.frame.beatSaber.mods;

  closure = map (m: m.key) (
    builtins.genericClosure {
      startSet = map (key: { inherit key; }) ([ "BSIPA" ] ++ wanted);
      operator = m: map (key: { inherit key; }) lock.mods.${m.key}.depends;
    }
  );

  zip =
    name:
    pkgs.fetchurl {
      name = "${lib.strings.sanitizeDerivationName name}-${lock.mods.${name}.version}.zip";
      inherit (lock.mods.${name}) url hash;
    };

  tree =
    pkgs.runCommand "beat-saber-mods-${lock.gameVersion}"
      {
        nativeBuildInputs = [ pkgs.unzip ];
        zips = map zip closure;
      }
      ''
        mkdir $out
        for z in $zips; do
          rm -rf x
          unzip -q "$z" -d x
          (cd x && find . -type f -printf '%P\n') | while IFS= read -r f; do
            if [ ! -e "$out/$f" ]; then
              install -D -m444 "x/$f" "$out/$f"
            elif ! cmp -s "x/$f" "$out/$f"; then
              echo "$z ships a different $f than another mod" >&2
              exit 1
            fi
          done
        done
        mkdir -p "$out/Beat Saber_Data" $out/Libs
        cp -r $out/IPA/Data/. "$out/Beat Saber_Data"
        cp -r $out/IPA/Libs/. $out/Libs
        mv $out/IPA/winhttp.dll $out
        rm -r $out/IPA
        dups=$(cd $out && find . | tr '[:upper:]' '[:lower:]' | sort | uniq -d)
        if [ -n "$dups" ]; then
          echo "paths that differ only in case: $dups" >&2
          exit 1
        fi
      '';

  sync = pkgs.writeShellApplication {
    name = "beat-saber-mods-sync";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnugrep
      gnused
    ];
    text = ''
      export LC_ALL=C
      game=$(realpath -- "$2")
      tree=${lib.optionalString (wanted != [ ]) "${tree}"}
      state=$game/.nix-mods
      core="$game/Beat Saber_Data/Managed/UnityEngine.CoreModule.dll"
      vanilla=$state/UnityEngine.CoreModule.dll

      case $1 in
        mount)
          [ -n "$tree" ] || exit 1
          have=$(grep -a -o -E '[0-9]+\.[0-9]+\.[0-9]+_[0-9]+' "$game/Beat Saber_Data/globalgamemanagers" | sed -n '1{s/_.*//;p}')
          if [ "$have" != ${lock.gameVersion} ]; then
            echo "beat-saber-mods: Beat Saber is ''${have:-of unknown version}, the mods are for ${lock.gameVersion}; starting without them" >&2
            exit 1
          fi
          mkdir -p "$state"
          touch "$state/files"
          [ -f "$state/dirs" ] || (cd "$game" && find . -mindepth 1 -type d -printf '%P\n' | sort) > "$state/dirs"
          if ! grep -q -a -F IPA.Injector "$core"; then
            cp "$core" "$vanilla.new"
            mv "$vanilla.new" "$vanilla"
          fi
          (cd "$tree" && find . -type f -printf '%P\n') | sort > "$state/want"
          comm -23 "$state/files" "$state/want" | (cd "$game" && xargs -r -d '\n' rm -f --)
          mv "$state/want" "$state/files"
          cp -r --no-preserve=mode -T "$tree" "$game"
          ;;
        unmount)
          [ -f "$state/files" ] || exit 0
          if grep -q -a -F IPA.Injector "$core"; then
            if [ ! -f "$vanilla" ]; then
              echo "beat-saber-mods: no unpatched UnityEngine.CoreModule.dll saved; verify Beat Saber's files in Steam" >&2
              exit 1
            fi
            cp "$vanilla" "$core"
          fi
          (cd "$game" && xargs -r -d '\n' rm -f -- < "$state/files")
          rm -rf "$game/IPA/Backups" "$game/Plugins/.cache"
          if [ -f "$state/dirs" ]; then
            while gone=$(cd "$game" && find . -mindepth 1 -type d -empty -printf '%P\n' | sort | comm -23 - "$state/dirs") && [ -n "$gone" ]; do
              (cd "$game" && xargs -d '\n' rmdir -- <<<"$gone")
            done
          fi
          rm -rf "$state"
          ;;
        *)
          echo "usage: beat-saber-mods-sync mount|unmount GAME_DIR" >&2
          exit 2
          ;;
      esac
    '';
  };

  wrapper = pkgs.writeShellApplication {
    name = "beat-saber-mods";
    text = ''
      if [ $# -eq 0 ]; then
        echo "usage: beat-saber-mods %command%, as Beat Saber's Steam launch options" >&2
        exit 2
      fi
      game=''${STEAM_COMPAT_INSTALL_PATH:-$PWD}
      if ${lib.getExe sync} mount "$game"; then
        export WINEDLLOVERRIDES="winhttp=n,b''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}" FEX_MONOHACKS=0
        set -- "$@" --no-yeet
      else
        ${lib.getExe sync} unmount "$game" || true
      fi
      exec "$@"
    '';
  };
in
{
  options.frame.beatSaber.mods = lib.mkOption {
    type = lib.types.listOf (lib.types.enum (lib.attrNames lock.mods));
    default = [ ];
    description = "BeatMods mods for Beat Saber ${lock.gameVersion}, by name. BSIPA and dependencies come along. Empty removes them on the next launch.";
  };

  config.environment.systemPackages = [ wrapper ];
}
