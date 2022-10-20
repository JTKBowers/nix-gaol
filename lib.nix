rec {
  deps = nixpkgs: pkg: nixpkgs.lib.strings.splitString "\n" (nixpkgs.lib.strings.fileContents (nixpkgs.writeReferencesToFile pkg));

  bindDirectory = path: "--bind ${path} ${path}";
  roBindDirectory = path: "--ro-bind ${path} ${path}";
  buildCommand = entries: builtins.concatStringsSep " " entries;

  buildUnshareUserArg = shareUser: if shareUser then [ ] else "--unshare-user";

  setEnv = name: value: "--setenv ${name} ${value}";
  generateEnvArgs = pkgs: envs: pkgs.lib.attrsets.mapAttrsToList setEnv envs;
  generateWrapperScript = pkgs: { pkg
                                , name
                                , logGeneratedCommand
                                , bindDirs
                                , roBindDirs
                                , envs
                                , strace
                                , extraArgs
                                , shareUser
                                }:
    pkgs.writeShellScriptBin name ''set -e${if logGeneratedCommand then "x" else ""}
${buildCommand (pkgs.lib.lists.flatten [
  "${pkgs.bubblewrap}/bin/bwrap"
  (buildUnshareUserArg shareUser)
  "--unshare-ipc"
  "--unshare-pid"
  "--unshare-net"
  "--unshare-uts"
  "--unshare-cgroup"
  "--clearenv"
  (generateEnvArgs pkgs envs)
  (map bindDirectory bindDirs)
  (map roBindDirectory roBindDirs)
  (builtins.toString extraArgs)
  (if strace then "${pkgs.strace}/bin/strace -f" else "")
  "${pkg}/bin/${name}"
  "$@"
])}
'';
  wrapPackage = nixpkgs: { pkg
                         , name ? pkg.pname
                         , logGeneratedCommand ? false
                         , extraBindDirs ? [ ]
                         , extraRoBindDirs ? [ ]
                         , bindCwd ? false
                         , envs ? { }
                         , extraDepPkgs ? [ ]
                         , strace ? false
                         , extraArgs ? [ ]
                         , shareUser ? false
                         }:
    let
      pkgDeps = (deps nixpkgs pkg) ++ (builtins.concatMap (pkg: deps nixpkgs pkg) extraDepPkgs) ++ (if strace then deps nixpkgs nixpkgs.strace else [ ]);
      bindDirs = extraBindDirs ++ (if bindCwd == true then [ "$(pwd)" ] else [ ]);
      roBindDirs = nixpkgs.lib.lists.unique (pkgDeps ++ extraRoBindDirs ++ (if bindCwd == "ro" then [ "$(pwd)" ] else [ ]));
      mergedEnvs = { PATH = "$PATH:${nixpkgs.lib.strings.concatMapStringsSep ":" (dep: "${dep}/bin") extraDepPkgs}"; } // envs;
    in
    generateWrapperScript nixpkgs {
      pkg = pkg;
      name = name;
      logGeneratedCommand = logGeneratedCommand;
      bindDirs = bindDirs;
      roBindDirs = roBindDirs;
      envs = mergedEnvs;
      strace = strace;
      extraArgs = extraArgs;
      shareUser = shareUser;
    };
}
