{ inputs =
    { nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
      purs-nix.url = "github:purs-nix/purs-nix/ps-0.14";
      utils.url = "github:numtide/flake-utils";
    };

  outputs = { nixpkgs, utils, ... }@inputs:
    utils.lib.eachDefaultSystem
      (system:
         let
           pkgs = nixpkgs.legacyPackages.${system};
           purs-nix = inputs.purs-nix { inherit system; };

           ps =
             purs-nix.purs
               { dependencies =
                   with purs-nix.ps-pkgs;
                   [ effect
                     lists
                     arrays
                     maybe
                     either
                     aff
                     aff-promise
                     argonaut-core
                     argonaut-codecs
                     argonaut-generic
                     optparse
                     node-fs
                     debug
                   ];

                 dir = ./.;
               };
         in
         { packages.default =
             ps.modules.Main.app { name = "hours"; incremental = false; };

           devShells.default =
             pkgs.mkShell
               { packages =
                   with pkgs;
                   [ nodejs
                     (ps.command {})
                     purs-nix.esbuild
                     purs-nix.purescript
                   ];
               };
         }
      );
}
