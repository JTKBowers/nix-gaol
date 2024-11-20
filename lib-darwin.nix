{
  lib,
  writeShellScriptBin,
  writeText,
  ...
}: let
  callSandboxExec = {
    name,
    pkg,
    policy,
  }:
    writeShellScriptBin name ''
      sandbox-exec -f ${policy} -D cwd=$(pwd) -D tmpdir="$TMPDIR" -D path_arg="$1" -D homedir="$HOME" ${pkg}/bin/${name} $@
    '';
  resolveDarwinOptions = {
    sandboxPolicies ? [], # A list of paths to extra sandbox policies. They will overwrite any earlier policies.
  }: {inherit sandboxPolicies;};
in {
  monitor-sandbox = writeShellScriptBin "monitor-sandbox" ''
    log stream --style compact --predicate 'sender=="Sandbox"'
  '';
  sandboxPackage = {
    pkg,
    name ? pkg.pname,
    extraBindPaths ? [],
    runtimeStorePaths ? [],
    bindCwd ? false,
    extraDepPkgs ? [],
    shareNet ? false,
    presets ? [],
    linuxOptions ? {},
    darwinOptions ? {},
  }: let
    darwinOptions' = resolveDarwinOptions darwinOptions;
    policyDocuments =
      []
      ++ lib.lists.optional (bindCwd == true) ./macos-policies/cwd-rw.sb
      ++ lib.lists.optional (bindCwd == "ro") ./macos-policies/cwd-ro.sb
      ++ lib.lists.optional shareNet ./macos-policies/network.sb
      ++ darwinOptions'.sandboxPolicies;
    policyImports = (
      builtins.map
      (policyPath: "(import \"${policyPath}\")")
      policyDocuments
    );
    policy = writeText "${name}-policy" (lib.strings.concatLines (
      [
        "(version 1)"
        "(deny default)"
        "(import \"/System/Library/Sandbox/Profiles/bsd.sb\")"

        ''
          (allow file-read*
            (subpath "/nix/store") ; TODO: Scope to package closure
          )
        ''
        ''
          (allow process-exec
            (subpath "${pkg}")
          )
        ''
      ]
      ++ policyImports
    ));
  in
    callSandboxExec {inherit name pkg policy;};
}
