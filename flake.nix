{
  description = "Freegosy — All-in-one game manager for RomM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          version = "0.5.10";
          pname = "freegosy";

          src = pkgs.fetchurl {
            url = "https://github.com/abduznik/Freegosy/releases/download/v${version}/Freegosy-linux-x86_64.AppImage";
            hash = "sha256-PLACEHOLDER"; # nix will compute on first build
          };

          appimageContents = pkgs.appimageTools.extractType1 { inherit pname version src; };
        in {
          default = pkgs.appimageTools.wrapType2 rec {
            inherit pname version src;

            extraPkgs = pkgs: [ pkgs.webkitgtk_4_1 ];

            extraInstallCommands = ''
              # Fix desktop entry
              substituteInPlace $out/share/applications/${pname}.desktop \
                --replace-fail 'Exec=AppRun' 'Exec=${meta.mainProgram}' \
                --replace-fail 'Icon=AppRun' 'Icon=${pname}'
              # Install icon if present
              if [ -f "${appimageContents}/${pname}.png" ]; then
                mkdir -p $out/share/icons/hicolor/512x512/apps
                cp "${appimageContents}/${pname}.png" $out/share/icons/hicolor/512x512/apps/${pname}.png
              fi
            '';

            meta = with pkgs.lib; {
              description = "All-in-one game manager for RomM — browse, download, launch, and sync saves";
              homepage = "https://github.com/abduznik/Freegosy";
              downloadPage = "https://github.com/abduznik/Freegosy/releases";
              license = licenses.mit;
              sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
              platforms = [ "x86_64-linux" "aarch64-linux" ];
              mainProgram = "freegosy";
            };
          };
        }
      );

      # Quick run: nix run github:abduznik/Freegosy
      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/freegosy";
        };
      });

      # Development shell
      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          buildInputs = with nixpkgs.legacyPackages.${system}; [
            flutter
            dart
            git
          ];
        };
      });
    };
}
