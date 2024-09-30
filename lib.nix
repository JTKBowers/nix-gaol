{pkgs, ...}: rec {
  getDeps = pkg: pkgs.lib.strings.splitString "\n" (pkgs.lib.strings.fileContents (pkgs.writeReferencesToFile pkg));
  getDepsMulti = packages: pkgs.lib.lists.unique (builtins.concatMap getDeps packages);

  bindPath' = {
    srcPath,
    dstPath,
    mode,
  }:
    if mode == "rw"
    then "--bind ${srcPath} ${dstPath}"
    else "--ro-bind ${srcPath} ${dstPath}";

  bindPath = path:
    if (builtins.isPath path || builtins.isString path)
    then
      bindPath' {
        mode = "ro";
        srcPath = path;
        dstPath = path;
      }
    else
      bindPath' {
        mode = path.mode or "ro";
        srcPath = path.srcPath or path.path;
        dstPath = path.dstPath or path.path;
      };

  buildCommand = entries: builtins.concatStringsSep " " entries;

  buildOptionalArg = cond: value:
    if cond
    then value
    else [];
  buildBwrapCommand = flatten: {
    bwrapPkg,
    execPath,
    bindPaths,
    runtimeStorePaths,
    envs,
    extraArgs,
    shareUser,
    shareIpc,
    sharePid,
    shareNet,
    shareUts,
    shareCgroup,
    clearEnv,
  }: (buildCommand (flatten [
    "${bwrapPkg}/bin/bwrap"
    (buildOptionalArg (!shareUser) "--unshare-user")
    (buildOptionalArg (!shareIpc) "--unshare-ipc")
    (buildOptionalArg (!sharePid) "--unshare-pid")
    (buildOptionalArg (!shareNet) "--unshare-net")
    (buildOptionalArg (!shareUts) "--unshare-uts")
    (buildOptionalArg (!shareCgroup) "--unshare-cgroup")
    (buildOptionalArg clearEnv "--clearenv")
    (generateEnvArgs envs)
    (map bindPath bindPaths)
    (buildOptionalArg (builtins.length runtimeStorePaths > 0) "$(nix-store --query --requisites ${builtins.concatStringsSep " " runtimeStorePaths} | sed \"s/\\(.*\\)/--ro-bind \\1 \\1/\")")
    (builtins.toString extraArgs)
    execPath
    "\"$@\""
  ]));

  setEnv = name: value: "--setenv ${name} ${value}";
  generateEnvArgs = envs: builtins.map (name: (setEnv name (builtins.getAttr name envs))) (builtins.attrNames envs);
  generateWrapperScript = {
    pkg,
    name,
    bindPaths,
    envs,
    strace,
    extraArgs,
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
    bwrapCommand = buildBwrapCommand pkgs.lib.lists.flatten {
      bwrapPkg = pkgs.bubblewrap;
      execPath =
        (
          if strace
          then "${pkgs.strace}/bin/strace -f"
          else ""
        )
        + "${pkg}/bin/${name}";
      bindPaths = bindPaths;
      envs = envs;
      extraArgs = extraArgs;
      shareUser = shareUser;
      shareIpc = shareIpc;
      sharePid = sharePid;
      shareUts = shareUts;
      shareNet = shareNet;
      shareCgroup = shareCgroup;
      clearEnv = clearEnv;
      runtimeStorePaths = runtimeStorePaths;
    };
    busPath = "$(dirname ${dbus.proxyBusPath})";
    dbusProxy = wrapPackage {
      pkg = pkgs.xdg-dbus-proxy;
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
    dbusProxyRunner = pkgs.lib.strings.optionalString dbus.enable ''
      echo 'mkdir -p ${busPath}' >> "$out/bin/${name}"
      echo '${dbusProxy}/bin/xdg-dbus-proxy unix:path=${dbus.parentBusPath} ${dbus.proxyBusPath} --filter &' >> "$out/bin/${name}"
      echo 'bg_pid=$!' >> "$out/bin/${name}"
      echo "trap \"trap - SIGTERM && kill \$bg_pid\" SIGINT SIGTERM EXIT" >> "$out/bin/${name}"
      # Wait for the bus to exist before proceeding
      echo 'for _ in {1..10000}; do if [[ -e "${dbus.proxyBusPath}" ]]; then break; fi; done' >> "$out/bin/${name}"
    '';
  in
    pkgs.stdenvNoCC.mkDerivation {
      inherit name;

      phases = "installPhase";

      installPhase = ''
        mkdir -p "$out/bin"
        echo "#! ${pkgs.stdenv.shell}" >> "$out/bin/${name}"
        echo "set -e" >> "$out/bin/${name}"
        ${dbusProxyRunner}
        echo '${bwrapCommand}' >> "$out/bin/${name}"
        chmod 0755 "$out/bin/${name}"

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
  wrapPackage = {
    pkg,
    name ? pkg.pname,
    extraBindPaths ? [],
    runtimeStorePaths ? [],
    bindCwd ? false,
    envs ? {},
    extraDepPkgs ? [],
    strace ? false,
    extraArgs ? [],
    shareUser ? false,
    shareIpc ? false,
    sharePid ? false,
    shareNet ? false,
    shareUts ? false,
    shareCgroup ? false,
    clearEnv ? true,
    presets ? [],
    dbus ? {
      enable = false;
    },
  }: let
    # Some scoped helper functions
    getBinDir = pkg: "${pkg}/bin";

    dbus' = {
      enable = dbus.enable or false;

      parentBusPath = dbus.parentBusPath or "$XDG_RUNTIME_DIR/bus";
      proxyBusPath = dbus.proxyBusPath or "$XDG_RUNTIME_DIR/dbus-proxy/bus";
    };

    runtimeStorePaths' =
      runtimeStorePaths
      ++ (
        if builtins.elem "graphics" presets
        then ["/run/opengl-driver"]
        else []
      )
      ++ (
        if builtins.elem "cursor" presets
        then ["/run/current-system/sw/share/icons/Adwaita"]
        else []
      );

    extraArgs' =
      (
        if builtins.elem "graphics" presets
        then ["--dev /dev" "--dev-bind /dev/dri /dev/dri"]
        else []
      )
      ++ extraArgs;

    # Build the nix-specific things into generic bwrap args
    pkgDeps = getDepsMulti (
      [pkg]
      ++ extraDepPkgs
      ++ pkgs.lib.lists.optional strace pkgs.strace
      ++ pkgs.lib.lists.optional (builtins.elem "ssl" presets) pkgs.cacert
    );
    bindPaths = pkgs.lib.lists.unique (
      pkgDeps
      ++ extraBindPaths
      ++ runtimeStorePaths'
      ++ (
        if bindCwd == true
        then [
          {
            mode = "rw";
            path = "$(pwd)";
          }
        ]
        else []
      )
      ++ (
        if bindCwd == "ro"
        then [
          {
            mode = "ro";
            path = "$(pwd)";
          }
        ]
        else []
      )
      ++ (
        if builtins.elem "ssl" presets
        then [
          # See https://github.com/NixOS/pkgs/blob/af11c51c47abb23e6730b34790fd47dc077b9eda/nixos/modules/security/ca.nix#L80
          {
            srcPath = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            dstPath = "/etc/ssl/certs/ca-certificates.crt";
          }
          {
            srcPath = "${pkgs.cacert.p11kit}/etc/ssl/trust-source";
            dstPath = "/etc/ssl/trust-source";
          }
          "/etc/resolv.conf"
        ]
        else []
      )
      ++ (
        if builtins.elem "wayland" presets
        then ["$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"]
        else []
      )
      ++ (
        if dbus'.enable
        then [dbus'.proxyBusPath]
        else []
      )
    );
    mergedEnvs =
      {
        PATH = builtins.concatStringsSep ":" (["$PATH" (getBinDir pkg)] ++ (builtins.map getBinDir extraDepPkgs));
      }
      // envs
      // (
        if builtins.elem "wayland" presets
        then {
          XDG_RUNTIME_DIR = "$XDG_RUNTIME_DIR";
          WAYLAND_DISPLAY = "$WAYLAND_DISPLAY";
        }
        else {}
      )
      // (
        if builtins.elem "cursor" presets
        then {
          XCURSOR_PATH = "/run/current-system/sw/share/icons";
        }
        else {}
      )
      // (
        if dbus'.enable
        then {DBUS_SESSION_BUS_ADDRESS = "unix:path=${dbus'.proxyBusPath}";}
        else {}
      );
  in
    generateWrapperScript {
      pkg = pkg;
      name = name;
      bindPaths = bindPaths;
      envs = mergedEnvs;
      strace = strace;
      extraArgs = extraArgs';
      shareUser = shareUser;
      shareIpc = shareIpc;
      sharePid = sharePid;
      shareUts = shareUts;
      shareNet = shareNet;
      shareCgroup = shareCgroup;
      clearEnv = clearEnv;
      runtimeStorePaths = runtimeStorePaths';
      dbus = dbus';
    };
}
