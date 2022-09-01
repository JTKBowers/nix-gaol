{
  description = "A flake describing functions to wrap packages using bubblewrap";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nixpkgs, flake-utils }: let
    # These are all the platforms that contain a bubblewrap package
    # As this flake only provides wrappers for calling bubblewrap, we can only support the platforms that bubblewrap supports
    supportedPlatforms = builtins.filter (x: (builtins.getAttr x nixpkgs.legacyPackages) ? busybox) (builtins.attrNames nixpkgs.legacyPackages);
  in
    flake-utils.lib.eachSystem supportedPlatforms (system: {
      packages = let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        hello-bwrapped = (import ./lib.nix).generateWrapperScript pkgs {pkg=pkgs.hello;};
        hello-wayland-bwrapped = pkgs.writeShellScriptBin "hello-wayland-bwrapped" ''set -eux
${pkgs.bubblewrap}/bin/bwrap --unshare-all \
${let deps = nixpkgs.lib.strings.splitString "\n" "${nixpkgs.lib.strings.fileContents (pkgs.writeReferencesToFile pkgs.hello-wayland)}"; in builtins.toString (map (x: "--ro-bind ${x} ${x}") deps)} \
--ro-bind $XDG_RUNTIME_DIR/wayland-0 $XDG_RUNTIME_DIR/wayland-0 \
    --setenv XDG_RUNTIME_DIR $XDG_RUNTIME_DIR \
    --setenv WAYLAND_DISPLAY $WAYLAND_DISPLAY \
    --dev /dev \
    --dev-bind /dev/dri /dev/dri \
    --proc /proc \
    --ro-bind /sys/devices/ /sys/devices/ \
    --ro-bind /sys/dev/char /sys/dev/char \
    --ro-bind /run/opengl-driver /run/opengl-driver \
    --ro-bind /etc/fonts /etc/fonts \
    --setenv FONTCONFIG_PATH /etc/fonts/ \
    --setenv FONTCONFIG_FILE /etc/fonts/fonts.conf \
    --setenv LIBGL_DEBUG verbose \
    ${pkgs.hello-wayland}/bin/hello-wayland "$@"
'';
      };
    });
}
