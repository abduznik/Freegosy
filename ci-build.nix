# CI-only: builds from local AppImage
# Usage: FREEGOSY_SRC=Freegosy-x86_64.AppImage FREEGOSY_VERSION=0.5.10 nix-build ci-build.nix
let
  pkgs = import <nixpkgs> {};
  src = ./. + "/${builtins.getEnv "FREEGOSY_SRC"}";
  pname = "freegosy";
  version = builtins.getEnv "FREEGOSY_VERSION";
  appimageContents = pkgs.appimageTools.extractType1 { inherit pname version src; };
in
pkgs.appimageTools.wrapType2 rec {
  inherit pname version src;
  extraPkgs = pkgs: [ pkgs.webkitgtk_4_1 ];
  extraInstallCommands = ''
    # Flutter AppImages may not ship a .desktop file — create one
    mkdir -p $out/share/applications
    cat > $out/share/applications/${pname}.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Freegosy
    Exec=${pname}
    Icon=${pname}
    Categories=Game;
    Comment=All-in-one game manager for RomM
    EOF

    # Copy icon if present
    mkdir -p $out/share/icons/hicolor/256x256/apps
    find ${appimageContents} -maxdepth 1 -name "*.png" -exec cp {} $out/share/icons/hicolor/256x256/apps/${pname}.png \; 2>/dev/null || true
  '';
  meta = with pkgs.lib; {
    description = "All-in-one game manager for RomM";
    homepage = "https://github.com/abduznik/Freegosy";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "freegosy";
  };
}
