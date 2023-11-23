{
  inputs.nixpkgs.url = github:NixOS/nixpkgs/release-23.05;
  inputs.devenv.url = github:cachix/devenv;
  inputs.graphile-migrate-flake.url = github:zarybnicky/graphile-migrate-flake;

  outputs = { self, nixpkgs, devenv, graphile-migrate-flake, ... } @ inputs: let
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [
        graphile-migrate-flake.overlays.default
      ];
    };
  in {
    devenv-up = self.devShells.x86_64-linux.default.config.procfileScript;
    devShells.x86_64-linux.default = devenv.lib.mkShell {
      inherit inputs pkgs;
      modules = [
        ({ pkgs, ... }: {
          packages = [
            pkgs.graphile-migrate
            pkgs.postgresql_15
            pkgs.sqlint
            pkgs.pgformatter
          ];

          processes.migrate.exec = "sleep 1 && graphile-migrate watch";

          services.postgres = {
            enable = true;
            package = pkgs.postgresql_15;
            initialDatabases = [
              { name = "mergestat"; }
              { name = "mergestat-shadow"; }
            ];
            initialScript = ''
              CREATE USER postgres SUPERUSER;
            '';
          };
        })
      ];
    };
  };
}
