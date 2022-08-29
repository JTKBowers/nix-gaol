rec {
  deps = nixpkgs: pkg: nixpkgs.lib.strings.splitString "\n" (nixpkgs.lib.strings.fileContents (nixpkgs.writeReferencesToFile pkg));

  generateWrapperScript = pkgs: {pkg, name}: pkgs.writeShellScriptBin "bwrapped-${name}" ''
${pkgs.bubblewrap}/bin/bwrap --unshare-all ${builtins.toString (map (x: "--ro-bind ${x} ${x}") (deps pkgs pkg))} ${pkg}/bin/${name} "$@"
''; 
}
