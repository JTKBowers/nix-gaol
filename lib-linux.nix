{
  lib,
  writeShellScriptBin,
  writeClosure,
  callPackage,
  stdenvNoCC,
  bubblewrap,
  xdg-dbus-proxy,
  cacert,
  strace,
  ...
}: rec {
  getDeps = pkg: lib.strings.splitString "\n" (lib.strings.fileContents (writeClosure pkg));
  getDepsMulti = packages: lib.lists.unique (builtins.concatMap getDeps packages);

  buildBwrapCommand = callPackage ./bwrap.nix {};
  generateWrapperScript = {
    pkg,
    name,
    bindPaths,
    envs,
    useStrace,
    extraBwrapArgs,
    shareUser,
    shareIpc,
    sharePid,
    shareNet,
    shareUts,
    shareCgroup,
    clearEnv,
    runtimeStorePaths,
    dbus,
  }: let
    bwrapCommand = buildBwrapCommand {
      bwrapPkg = bubblewrap;
      execPath = (lib.strings.optionalString useStrace "${lib.getExe strace} -f ") + (lib.getExe' pkg name);
      inherit
        bindPaths
        envs
        extraBwrapArgs
        shareUser
        shareIpc
        sharePid
        shareUts
        shareNet
        shareCgroup
        clearEnv
        runtimeStorePaths
        ;
    };
    busPath = "$(dirname ${dbus.proxyBusPath})";
    dbusProxy = sandboxPackage {
      pkg = xdg-dbus-proxy;
      name = "xdg-dbus-proxy";
      envs = {
        XDG_RUNTIME_DIR = "$XDG_RUNTIME_DIR";
      };
      extraBindPaths = [
        dbus.parentBusPath
        {
          mode = "rw";
          path = busPath;
        }
      ];
    };
    dbusProxyRunner = writeShellScriptBin "dbus-proxy-runner" ''
      mkdir -p ${busPath}
      ${lib.getExe' dbusProxy "xdg-dbus-proxy"} unix:path=${dbus.parentBusPath} ${dbus.proxyBusPath} --filter &
      bg_pid=$!
      trap \"trap - SIGTERM && kill \$bg_pid\" SIGINT SIGTERM EXIT
      # Wait for the bus to exist before proceeding
      for _ in {1..10000}; do
        if [[ -e "${dbus.proxyBusPath}" ]]; then break; fi;
      done
    '';
    wrappedCommand = writeShellScriptBin "wrapped-${name}" ''
      set -e
      ${lib.strings.optionalString dbus.enable (lib.getExe' dbusProxyRunner "dbus-proxy-runner")}
      ${bwrapCommand}
    '';
  in
    stdenvNoCC.mkDerivation {
      inherit name;

      phases = "installPhase";

      installPhase = ''
        mkdir -p $out
        mkdir -p $out/bin
        cp ${wrappedCommand}/bin/wrapped-${name} $out/bin/${name}
        if [ -d "${pkg}/share" ]; then
          cp -a "${pkg}/share" "$out/share"

          # Replace any direct references to the binary
          find "$out/share" -type f | while read file;
          do
            if grep -q "${pkg}/bin" "$file"
            then
              substituteInPlace "$file" \
                --replace "${pkg}/bin/${name}" "$out/bin/${name}";
            fi
          done


          ! grep -q "${pkg}/bin" -r "$out/share/"
          hasDirectReference=$?
          if [[ $hasDirectReference -ne 0 ]]; then
            echo "Found direct reference to unsandboxed binary in desktop item"
            exit 1
          fi
        fi
      '';
    };
  resolveDbusOptions = {
    enable ? false,
    parentBusPath ? "$XDG_RUNTIME_DIR/bus",
    proxyBusPath ? "$XDG_RUNTIME_DIR/dbus-proxy/bus",
  }: {
    inherit enable parentBusPath proxyBusPath;
  };
  resolveLinuxOptions = {
    envs ? {},
    strace ? false,
    shareUser ? false,
    shareIpc ? false,
    sharePid ? false,
    shareUts ? false,
    shareCgroup ? false,
    clearEnv ? true,
    dbus ? {
      enable = false;
    },
    extraBwrapArgs ? [],
    presets ? [],
  }: {
    inherit
      envs
      strace
      shareUser
      shareIpc
      sharePid
      shareUts
      shareCgroup
      clearEnv
      dbus
      extraBwrapArgs
      presets
      ;
  };

  sandboxPackage = {
    pkg,
    name ? pkg.pname,
    extraBindPaths ? [],
    runtimeStorePaths ? [],
    bindCwd ? false,
    extraDepPkgs ? [],
    shareNet ? false,
    linuxOptions ? {},
    darwinOptions ? {},
  }: let
    linuxOptions' = resolveLinuxOptions linuxOptions;
    dbus = resolveDbusOptions linuxOptions'.dbus;
    presets = linuxOptions'.presets;

    runtimeStorePaths' =
      runtimeStorePaths
      ++ lib.lists.optional (builtins.elem "graphics" presets) "/run/opengl-driver"
      ++ lib.lists.optional (builtins.elem "cursor" presets) "/run/current-system/sw/share/icons/Adwaita";

    extraBwrapArgs' =
      lib.lists.optionals (builtins.elem "graphics" presets) ["--dev /dev" "--dev-bind /dev/dri /dev/dri"]
      ++ linuxOptions'.extraBwrapArgs;

    # Build the nix-specific things into generic bwrap args
    pkgDeps = getDepsMulti (
      [pkg]
      ++ extraDepPkgs
      ++ lib.lists.optional linuxOptions'.strace strace
      ++ lib.lists.optional (builtins.elem "ssl" presets) cacert
    );
    bindPaths = lib.lists.unique (
      pkgDeps
      ++ extraBindPaths
      ++ runtimeStorePaths'
      ++ lib.lists.optional (bindCwd == true) {
        mode = "rw";
        path = "$(pwd)";
      }
      ++ lib.lists.optional (bindCwd == "ro") {
        mode = "ro";
        path = "$(pwd)";
      }
      ++ lib.lists.optionals (builtins.elem "ssl" presets) [
        # See https://github.com/NixOS/pkgs/blob/af11c51c47abb23e6730b34790fd47dc077b9eda/nixos/modules/security/ca.nix#L80
        {
          srcPath = "${cacert}/etc/ssl/certs/ca-bundle.crt";
          dstPath = "/etc/ssl/certs/ca-certificates.crt";
        }
        {
          srcPath = "${cacert.p11kit}/etc/ssl/trust-source";
          dstPath = "/etc/ssl/trust-source";
        }
        "/etc/resolv.conf"
      ]
      ++ lib.lists.optional (builtins.elem "wayland" presets) ["$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"]
      ++ lib.lists.optional dbus.enable dbus.proxyBusPath
    );
    mergedEnvs =
      {
        PATH = "$PATH:${lib.strings.makeBinPath ([pkg] ++ extraDepPkgs)}";
      }
      // linuxOptions'.envs
      // lib.attrsets.optionalAttrs (builtins.elem "wayland" presets) {
        XDG_RUNTIME_DIR = "$XDG_RUNTIME_DIR";
        WAYLAND_DISPLAY = "$WAYLAND_DISPLAY";
      }
      // lib.attrsets.optionalAttrs (builtins.elem "cursor" presets) {
        XCURSOR_PATH = "/run/current-system/sw/share/icons";
      }
      // lib.attrsets.optionalAttrs dbus.enable {
        DBUS_SESSION_BUS_ADDRESS = "unix:path=${dbus.proxyBusPath}";
      };
  in
    generateWrapperScript {
      inherit
        pkg
        name
        bindPaths
        shareNet
        dbus
        ;
      envs = mergedEnvs;
      useStrace = linuxOptions'.strace;
      extraBwrapArgs = extraBwrapArgs';
      shareUser = linuxOptions'.shareUser;
      shareIpc = linuxOptions'.shareIpc;
      sharePid = linuxOptions'.sharePid;
      shareUts = linuxOptions'.shareUts;
      shareCgroup = linuxOptions'.shareCgroup;
      clearEnv = linuxOptions'.clearEnv;
      runtimeStorePaths = runtimeStorePaths';
    };
}
