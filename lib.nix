rec {
  deps = nixpkgs: pkg: nixpkgs.lib.strings.splitString "\n" (nixpkgs.lib.strings.fileContents (nixpkgs.writeReferencesToFile pkg));

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
  generateWrapperScript = pkgs: {
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
  in
    pkgs.stdenvNoCC.mkDerivation {
      inherit name;

      phases = "installPhase";

      installPhase = ''
        mkdir -p "$out/bin"
        echo "#! ${pkgs.stdenv.shell}" >> "$out/bin/${name}"
        echo "set -e" >> "$out/bin/${name}"
        echo 'exec ${bwrapCommand}' >> "$out/bin/${name}"
        chmod 0755 "$out/bin/${name}"

        if [ -d "${pkg}/share" ]; then
          cp -r "${pkg}/share" "$out/share"
          ! grep "${pkg}/bin" -r "$out/share/"
          exit $?
        fi
      '';
    };
  wrapPackage = nixpkgs: {
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
  }: let
    # Some scoped helper functions
    getDeps = deps nixpkgs;
    getBinDir = pkg: "${pkg}/bin";

    runtimeStorePaths' =
      runtimeStorePaths
      ++ (
        if builtins.elem "graphics" presets
        then ["/run/opengl-driver"]
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
    pkgDeps =
      (getDeps pkg)
      ++ (builtins.concatMap getDeps extraDepPkgs)
      ++ (
        if strace
        then getDeps nixpkgs.strace
        else []
      )
      ++ (
        if builtins.elem "ssl" presets
        then getDeps nixpkgs.cacert
        else []
      );
    bindPaths = nixpkgs.lib.lists.unique (
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
          # See https://github.com/NixOS/nixpkgs/blob/af11c51c47abb23e6730b34790fd47dc077b9eda/nixos/modules/security/ca.nix#L80
          {
            srcPath = "${nixpkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            dstPath = "/etc/ssl/certs/ca-certificates.crt";
          }
          {
            srcPath = "${nixpkgs.cacert.p11kit}/etc/ssl/trust-source";
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
      );
  in
    generateWrapperScript nixpkgs {
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
    };
}
