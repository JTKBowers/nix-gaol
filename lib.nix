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
    pkgs.writeShellScriptBin name ''
      set -e
      ${buildBwrapCommand pkgs.lib.lists.flatten {
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
      }}
    '';
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
    pkgDeps =
      (deps nixpkgs pkg)
      ++ (builtins.concatMap (pkg: deps nixpkgs pkg) extraDepPkgs)
      ++ (
        if strace
        then deps nixpkgs nixpkgs.strace
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
        PATH = builtins.concatStringsSep ":" (["$PATH" "${pkg}/bin"] ++ (builtins.map (dep: "${dep}/bin") extraDepPkgs));
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
