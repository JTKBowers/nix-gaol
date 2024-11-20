{
  stdenv,
  callPackage,
}:
if stdenv.isDarwin
then builtins.abort "Darwin support is unimplemented"
else (callPackage ./lib-linux.nix {})
