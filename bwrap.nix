{lib}: let
  # Argument generators
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
  setEnv = name: value: "--setenv ${name} ${value}";
  generateEnvArgs = envs: builtins.map (name: (setEnv name (builtins.getAttr name envs))) (builtins.attrNames envs);

  buildCommand = entries: builtins.concatStringsSep " " entries;
in
  {
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
  }: (buildCommand (lib.lists.flatten [
    (lib.getExe' bwrapPkg "bwrap")
    (lib.lists.optional (!shareUser) "--unshare-user")
    (lib.lists.optional (!shareIpc) "--unshare-ipc")
    (lib.lists.optional (!sharePid) "--unshare-pid")
    (lib.lists.optional (!shareNet) "--unshare-net")
    (lib.lists.optional (!shareUts) "--unshare-uts")
    (lib.lists.optional (!shareCgroup) "--unshare-cgroup")
    (lib.lists.optional clearEnv "--clearenv")
    (generateEnvArgs envs)
    (map bindPath bindPaths)
    (lib.lists.optional (builtins.length runtimeStorePaths > 0) "$(nix-store --query --requisites ${builtins.concatStringsSep " " runtimeStorePaths} | sed \"s/\\(.*\\)/--ro-bind \\1 \\1/\")")
    (builtins.toString extraArgs)
    execPath
    "\"$@\""
  ]))
