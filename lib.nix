rec {
  deps = nixpkgs: pkg: nixpkgs.lib.strings.splitString "\n" (nixpkgs.lib.strings.fileContents (nixpkgs.writeReferencesToFile pkg));

  generateBindArgs = paths: builtins.toString (map (dir: "--ro-bind ${dir} ${dir}") paths);
  generateWrapperScript = pkgs: {pkg, name ? pkg.pname, logGeneratedCommand ? false}: pkgs.writeShellScriptBin "bwrapped-${name}" ''set -e${if logGeneratedCommand then "x" else ""}
${pkgs.bubblewrap}/bin/bwrap --unshare-all ${generateBindArgs (deps pkgs pkg)} ${pkg}/bin/${name} "$@"
''; 
}
