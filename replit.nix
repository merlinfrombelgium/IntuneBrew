{pkgs}: {
  deps = [
    pkgs.wget
    pkgs.uv
    pkgs.python312Packages.flask
  ];
}
