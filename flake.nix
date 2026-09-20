{
  description = "WISVCH DOMjudge packaging: a Nix-built judgehost image, and the pinned DOMjudge both images are built from";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # One DOMjudge version for both images, in a file CI can read with jq
      # as easily as Nix reads it here. The domserver image is still built
      # by docker/domserver, but from this version rather than whatever the
      # newest release happens to be that day - that is what let domserver
      # and judgehost drift apart.
      domjudgeVersion = (builtins.fromJSON (builtins.readFile ./nix/domjudge.json)).version;

      # The domserver image that CI built from that version, by digest. The
      # build_domserver job rewrites this file after pushing, so bumping
      # this flake as an input moves a consumer's domserver and judgehost
      # in one step.
      domserverPin = builtins.removeAttrs (builtins.fromJSON (
        builtins.readFile ./nix/domserver-image.json
      )) [ "_comment" ];

      # Everything a judgehost image is made of, for one set of toolchains.
      # icpc-nix calls this with the versions it pins (its languages.nix);
      # ./nix/toolchains.nix is only what this repository builds by itself.
      judgehostFor =
        {
          pkgs,
          toolchains,
          name ? "judgehost-nix",
          tag ? "latest",
        }:
        let
          domjudge-judgehost = pkgs.callPackage ./nix/domjudge-judgehost.nix {
            version = domjudgeVersion;
          };
          chroot = pkgs.callPackage ./nix/chroot.nix { inherit toolchains; };
        in
        {
          inherit domjudge-judgehost chroot;
          image = pkgs.callPackage ./nix/image.nix {
            inherit
              pkgs
              domjudge-judgehost
              chroot
              name
              tag
              ;
          };
          check = pkgs.callPackage ./nix/check-chroot.nix { inherit chroot; };
        };

      own = judgehostFor {
        inherit pkgs;
        toolchains = import ./nix/toolchains.nix { inherit pkgs; };
      };
    in
    {
      # The judgehost image, built from the toolchains the caller pins.
      # Returns the image; .passthru carries the chroot and DOMjudge build.
      lib.mkJudgehostImage = args: (judgehostFor args).image;

      # The same, as the pieces, for a caller that wants to check or reuse
      # one of them (icpc-nix compares the chroot's toolchains with its
      # contestant image's).
      lib.judgehostFor = judgehostFor;

      # The DOMjudge both images are built from. CI reads this to decide
      # which release docker/domserver builds; see .github/workflows.
      inherit domjudgeVersion;

      images.${system}.domserver = pkgs.dockerTools.pullImage domserverPin;

      packages.${system} = {
        judgehost = own.image;
        domserver = self.images.${system}.domserver;
        judgehost-chroot = own.chroot;
        domjudge-judgehost = own.domjudge-judgehost;
        default = own.image;
      };

      # Compiles and runs a hello world for every language inside the
      # chroot, the way a judging does. No KVM and no root, so CI runs it.
      checks.${system}.chroot = own.check;

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
