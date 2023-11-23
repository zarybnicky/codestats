{
  inputs.nixpkgs.url = github:NixOS/nixpkgs/release-23.05;
  inputs.devenv.url = github:cachix/devenv/python-rewrite;
  inputs.graphile-migrate-flake.url = github:zarybnicky/graphile-migrate-flake;
  inputs.buildNodeModules-flake.url = github:adisbladis/buildNodeModules;
  inputs.buildNodeModules-flake.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, devenv, graphile-migrate-flake, buildNodeModules-flake, ... } @ inputs: let
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [
        graphile-migrate-flake.overlays.default
      ];
    };

    buildNodeModules = buildNodeModules-flake.lib.x86_64-linux;

    modules = buildNodeModules.buildNodeModules {
      packageRoot = ./.;
      nodejs = pkgs.nodejs;
    };

    nodePackage = pkgs.stdenv.mkDerivation {
      pname = "codestats";
      version = "1.0.0";
      src = ./.;

      nativeBuildInputs = with pkgs; [
        buildNodeModules.hooks.npmConfigHook
        libkrb5
        inetutils
        file
        gccStdenv.cc
        curl
        openssl
        nodejs
        nodejs.passthru.python # for node-gyp
        # npmHooks.npmBuildHook
        npmHooks.npmInstallHook
      ];

      nodeModules = buildNodeModules.fetchNodeModules {
        packageRoot = ./.;
      };
    };
  in {
    devenv-up = self.devShells.x86_64-linux.default.config.procfileScript;

    devShells.x86_64-linux.nodeModules = pkgs.mkShell {
      buildInputs = [
        buildNodeModules.hooks.linkNodeModulesHook
      ];

      nodeModules = buildNodeModules.buildNodeModules {
        packageRoot = ./.;
        inherit (pkgs) nodejs;

        buildInputs = with pkgs; [
          libkrb5
          inetutils
          file
          gccStdenv.cc
          curl
          openssl
          nodejs
          nodejs.passthru.python # for node-gyp
        ];
      };
    };

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
