rec {
  deps = nixpkgs: pkg: nixpkgs.lib.strings.splitString "\n" (nixpkgs.lib.strings.fileContents (nixpkgs.writeReferencesToFile pkg));

  bindDirectory = path: "--bind ${path} ${path}";
  roBindDirectory = path: "--ro-bind ${path} ${path}";
  generateBindArgs = paths: builtins.toString (map bindDirectory paths);
  generateRoBindArgs = paths: builtins.toString (map roBindDirectory paths);

  setEnv = name: value: "--setenv ${name} ${value}";
  generateEnvArgs = pkgs: envs: builtins.toString (pkgs.lib.attrsets.mapAttrsToList setEnv envs);
  generateWrapperScript = pkgs: {pkg, name, logGeneratedCommand, bindDirs, roBindDirs, envs}: pkgs.writeShellScriptBin "bwrapped-${name}" ''set -e${if logGeneratedCommand then "x" else ""}
${pkgs.bubblewrap}/bin/bwrap --unshare-all --clearenv ${generateEnvArgs pkgs envs} ${generateBindArgs bindDirs} ${generateRoBindArgs roBindDirs} ${pkg}/bin/${name} "$@"
'';
  wrapPackage = nixpkgs: {pkg, name ? pkg.pname, logGeneratedCommand ? false, extraBindDirs ? [], extraRoBindDirs? [], bindCwd ? false, envs ? {}, extraDepPkgs ? []}: let
    pkgDeps = (deps nixpkgs pkg) ++ (builtins.concatMap (pkg: deps nixpkgs pkg) extraDepPkgs);
    bindDirs = extraBindDirs ++ (if bindCwd == true then ["$(pwd)"] else []);
    roBindDirs = nixpkgs.lib.lists.unique (pkgDeps ++ extraRoBindDirs ++ (if bindCwd == "ro" then ["$(pwd)"] else []));
    mergedEnvs = {PATH = "$PATH:${nixpkgs.lib.strings.concatMapStringsSep ":" (dep: "${dep}/bin") extraDepPkgs}"; } // envs;
  in generateWrapperScript nixpkgs {pkg = pkg; name = name; logGeneratedCommand = logGeneratedCommand; bindDirs = bindDirs; roBindDirs = roBindDirs; envs = mergedEnvs;};
}
