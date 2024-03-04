{
  description = "Ergonomic, composable, efficient read/write streams";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      perSystem = { config, self', inputs', pkgs, system, ... }:
        let
          inherit (pkgs) ocamlPackages mkShell;
          inherit (ocamlPackages) buildDunePackage;
          name = "rio";
          version = "0.0.2";
        in
          {
            devShells = {
              default = mkShell {
                buildInputs = [ ocamlPackages.utop ];
                inputsFrom = [ self'.packages.default ];
              };
            };

            packages = {
              default =  buildDunePackage {
                inherit version;
                pname = "rio";
                propagatedBuildInputs = with ocamlPackages; [ cstruct ];
                src = ./.;
              };
            };
          };
    };
}
