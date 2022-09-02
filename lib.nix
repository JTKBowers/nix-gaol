rec {
  deps = nixpkgs: pkg: nixpkgs.lib.strings.splitString "\n" (nixpkgs.lib.strings.fileContents (nixpkgs.writeReferencesToFile pkg));

  generateBindArgs = paths: builtins.toString (map (dir: "--ro-bind ${dir} ${dir}") paths);
  generateWrapperScript = pkgs: {pkg, name, logGeneratedCommand, roBindDirs}: pkgs.writeShellScriptBin "bwrapped-${name}" ''set -e${if logGeneratedCommand then "x" else ""}
${pkgs.bubblewrap}/bin/bwrap --unshare-all ${generateBindArgs roBindDirs} ${pkg}/bin/${name} "$@"
'';
  wrapPackage = nixpkgs: {pkg, name ? pkg.pname, logGeneratedCommand ? false}: let
    pkgDeps = deps nixpkgs pkg;
    roBindDirs = pkgDeps;
  in generateWrapperScript nixpkgs {pkg = pkg; name = name; logGeneratedCommand = logGeneratedCommand; roBindDirs = roBindDirs;};
}
