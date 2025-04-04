{ pkgs, treefmt-nix, ... }:
let
  inherit (pkgs) lib;

  join = lib.concatStringsSep;

  toConfig =
    name:
    treefmt-nix.mkConfigFile pkgs {
      programs.${name}.enable = true;
    };

  # Add formatters that don't work fully here.
  broken-formatters =
    [
      # See https://github.com/numtide/treefmt-nix/pull/201
      "swift-format"
      # See https://github.com/NixOS/nixpkgs/pull/370124
      "formatjson5"
    ]
    # Broken on macOS
    ++ (lib.optionals pkgs.stdenv.isDarwin [
      "fantomas"
      "gdformat"
      "muon"
      # See https://github.com/NixOS/nixpkgs/issues/370084
      "elm-format"
    ]);

  programConfigs =
    let
      attrs = lib.listToAttrs (
        map (name: {
          name = "formatter-${name}";
          value = toConfig name;
        }) treefmt-nix.programs.names
      );
    in
    builtins.removeAttrs attrs (map (f: "formatter-${f}") broken-formatters);

  examples =
    let
      configs =
        lib.mapAttrs
          (name: value: ''
            {
              echo "# Example generated by ../examples.sh"
              sed -n '/^$/q;p' ${value} | sed 's|\(command = "\).*/\([^"]\+"\)|\1\2|' | sed 's|/nix/store/.*-||'
            } > "$out/${name}.toml"
          '')
          (
            lib.filterAttrs (
              n: _:
              # just example contains store paths
              n != "formatter-just"
              &&
                # mypy example contains store paths
                n != "formatter-mypy"
              &&
                # muon is broken on macOS
                n != "formatter-muon"
              &&
                # fantomas is broken on macOS
                n != "formatter-fantomas"
              &&
                # gdformat is bloken on macOS
                n != "formatter-gdformat"
              &&
                # elm-format is bloken on macOS
                n != "formatter-elm-format"
            ) programConfigs
          );
    in
    pkgs.runCommand "examples" { } ''
      mkdir $out

      ${join "\n" (lib.attrValues configs)}
    '';

  treefmtEval = treefmt-nix.evalModule pkgs ../treefmt.nix;

  treefmtDocEval = treefmt-nix.evalModule stubPkgs ../treefmt.nix;

  stubPkgs =
    lib.mapAttrs (
      k: _:
      throw "The module documentation must not depend on pkgs attributes such as ${lib.strings.escapeNixIdentifier k}"
    ) pkgs
    // {
      _type = "pkgs";
      inherit lib;
      # Formats is ok and supported upstream too
      inherit (pkgs) formats;
    };

  self = {
    empty-config = treefmt-nix.mkConfigFile pkgs { };

    simple-wrapper = treefmt-nix.mkWrapper pkgs {
      projectRootFile = "flake.nix";
    };

    # Check if the examples folder needs to be updated
    examples =
      pkgs.runCommand "test-examples"
        {
          passthru.examples = examples;
        }
        ''
          if ! diff -r ${../examples} ${examples}; then
            echo "The generated ./examples folder is out of sync"
            echo "Run ./examples.sh to fix the issue"
            exit 1
          fi
          touch $out
        '';

    # Check that the repo is formatted
    self-formatting = treefmtEval.config.build.check ../.;

    # Expose the current wrapper
    self-wrapper = treefmtEval.config.build.wrapper;

    # Check that the docs render properly
    module-docs = (pkgs.nixosOptionsDoc { options = treefmtDocEval.options; }).optionsCommonMark;
  } // programConfigs;
in
self
