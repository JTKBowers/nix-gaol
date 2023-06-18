rec {
  deps = nixpkgs: pkg: nixpkgs.lib.strings.splitString "\n" (nixpkgs.lib.strings.fileContents (nixpkgs.writeReferencesToFile pkg));

  bindDirectory = path: "--bind ${path} ${path}";
  roBindDirectory = path: "--ro-bind ${path} ${path}";
  buildCommand = entries: builtins.concatStringsSep " " entries;

  buildOptionalArg = cond: value:
    if cond
    then value
    else [];
  buildBwrapCommand = flatten: {
    bwrapPkg,
    execPath,
    bindDirs,
    roBindDirs,
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
    (map bindDirectory bindDirs)
    (map roBindDirectory roBindDirs)
    (builtins.toString extraArgs)
    execPath
    "\"$@\""
  ]));

  setEnv = name: value: "--setenv ${name} ${value}";
  generateEnvArgs = envs: builtins.map (name: (setEnv name (builtins.getAttr name envs))) (builtins.attrNames envs);
  generateWrapperScript = pkgs: {
    pkg,
    name,
    bindDirs,
    roBindDirs,
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
  }:
    pkgs.stdenvNoCC.mkDerivation {
      inherit name;

      phases = "installPhase";

      installPhase = ''
        mkdir -p "$out/bin"
        echo "#! ${pkgs.stdenv.shell}" >> "$out/bin/${name}"
        echo "set -e" >> "$out/bin/${name}"
        echo 'exec ${buildBwrapCommand pkgs.lib.lists.flatten {
          bwrapPkg = pkgs.bubblewrap;
          execPath =
            (
              if strace
              then "${pkgs.strace}/bin/strace -f"
              else ""
            )
            + "${pkg}/bin/${name}";
          bindDirs = bindDirs;
          roBindDirs = roBindDirs;
          envs = envs;
          extraArgs = extraArgs;
          shareUser = shareUser;
          shareIpc = shareIpc;
          sharePid = sharePid;
          shareUts = shareUts;
          shareNet = shareNet;
          shareCgroup = shareCgroup;
          clearEnv = clearEnv;
        }}' >> "$out/bin/${name}"
        chmod 0755 "$out/bin/${name}"
      '';
    };
  wrapPackage = nixpkgs: {
    pkg,
    name ? pkg.pname,
    extraBindDirs ? [],
    extraRoBindDirs ? [],
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
  }: let
    # Some scoped helper functions
    getDeps = deps nixpkgs;
    getBinDir = pkg: "${pkg}/bin";

    # Build the nix-specific things into generic bwrap args
    pkgDeps =
      (getDeps pkg)
      ++ (builtins.concatMap getDeps extraDepPkgs)
      ++ (
        if strace
        then getDeps nixpkgs.strace
        else []
      );
    bindDirs =
      extraBindDirs
      ++ (
        if bindCwd == true
        then ["$(pwd)"]
        else []
      );
    roBindDirs = nixpkgs.lib.lists.unique (pkgDeps
      ++ extraRoBindDirs
      ++ (
        if bindCwd == "ro"
        then ["$(pwd)"]
        else []
      ));
    mergedEnvs =
      {
        PATH = builtins.concatStringsSep ":" (["$PATH" (getBinDir pkg)] ++ (builtins.map getBinDir extraDepPkgs));
      }
      // envs;
  in
    generateWrapperScript nixpkgs {
      pkg = pkg;
      name = name;
      bindDirs = bindDirs;
      roBindDirs = roBindDirs;
      envs = mergedEnvs;
      strace = strace;
      extraArgs = extraArgs;
      shareUser = shareUser;
      shareIpc = shareIpc;
      sharePid = sharePid;
      shareUts = shareUts;
      shareNet = shareNet;
      shareCgroup = shareCgroup;
      clearEnv = clearEnv;
    };
}
