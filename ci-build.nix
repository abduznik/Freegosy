# CI-only: builds from local AppImage
# Usage: FREEGOSY_SRC=./Freegosy-x86_64.AppImage nix-build ci-build.nix
let
  pkgs = import <nixpkgs> {};
  src = ./. + (builtins.getEnv "FREEGOSY_SRC");
  pname = "freegosy";
  version = builtins.getEnv "FREEGOSY_VERSION";
  appimageContents = pkgs.appimageTools.extractType1 { inherit pname version src; };
in
pkgs.appimageTools.wrapType2 rec {
  inherit pname version src;
  extraPkgs = pkgs: [ pkgs.webkitgtk_4_1 ];
  extraInstallCommands = ''
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=${meta.mainProgram}' \
      --replace-fail 'Icon=AppRun' 'Icon=${pname}'
    if [ -f "${appimageContents}/${pname}.png" ]; then
      mkdir -p $out/share/icons/hicolor/512x512/apps
      cp "${appimageContents}/${pname}.png" $out/share/icons/hicolor/512x512/apps/${pname}.png
    fi
  '';
  meta = with pkgs.lib; {
    description = "All-in-one game manager for RomM";
    homepage = "https://github.com/abduznik/Freegosy";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "freegosy";
  };
}
