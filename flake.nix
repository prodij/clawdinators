{
  description = "CLAWDINATOR infra + Nix modules";

  inputs = {
    nix-clawdbot.url = "github:clawdbot/nix-clawdbot"; # latest upstream
    nixpkgs.follows = "nix-clawdbot/nixpkgs";
    agenix.url = "github:ryantm/agenix";
  };

  outputs = { self, nixpkgs, nix-clawdbot, agenix }:
    let
      lib = nixpkgs.lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: lib.genAttrs systems (system: f system);
      clawdbotOverlay = nix-clawdbot.overlays.default;
    in
    {
      nixosModules.clawdinator = import ./nix/modules/clawdinator.nix;
      nixosModules.default = self.nixosModules.clawdinator;

      overlays.clawdbot = clawdbotOverlay;
      overlays.default = clawdbotOverlay;

      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
          gateway =
            if pkgs ? clawdbot-gateway
            then pkgs.clawdbot-gateway
            else pkgs.clawdbot;
        in {
          clawdbot-gateway = gateway;
          default = gateway;
        });

      nixosConfigurations.clawdinator-1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ({ ... }: { nixpkgs.overlays = [ self.overlays.default ]; })
          agenix.nixosModules.default
          ./nix/hosts/clawdinator-1.nix
        ];
      };

      nixosConfigurations.clawdinator-1-image = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ({ ... }: { nixpkgs.overlays = [ self.overlays.default ]; })
          agenix.nixosModules.default
          ./nix/hosts/clawdinator-1-image.nix
        ];
      };
    };
}
