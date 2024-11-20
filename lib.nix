{
  stdenv,
  callPackage,
}:
if stdenv.isDarwin
then (callPackage ./lib-darwin.nix {})
else (callPackage ./lib-linux.nix {})
