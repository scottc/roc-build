app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.14.0/Erv2CTy8LJML6JuhvQ3WcmFpXSA6FnGPcfDTi1iFX9B8.tar.zst" }

import pf.Config
import pf.Recipes
import pf.System

# Roc 0.1.0_RC1 (15177e91f62cafddf5336c455e00e9f05427ac16)
# https://github.com/roc-lang/roc/releases/tag/0.1.0_RC1
roc_rc1 : System -> Config.Download
roc_rc1 = |system| {
    base = "https://github.com/roc-lang/roc/releases/download/0.1.0_RC1"
    match system {
        "x86_64-linux" =>
            Archive("${base}/roc-linux_x86_64-0.1.0_RC1.tar.gz", TarGz, "roc-linux_x86_64-0.1.0_RC1/roc")
        "aarch64-linux" =>
            Archive("${base}/roc-linux_arm64-0.1.0_RC1.tar.gz", TarGz, "roc-linux_arm64-0.1.0_RC1/roc")
        "aarch64-darwin" =>
            Archive("${base}/roc-macos_apple_silicon-0.1.0_RC1.tar.gz", TarGz, "roc-macos_apple_silicon-0.1.0_RC1/roc")
        "x86_64-darwin" =>
            Archive("${base}/roc-macos_x86_64-0.1.0_RC1.tar.gz", TarGz, "roc-macos_x86_64-0.1.0_RC1/roc")
        "x86_64-windows" =>
            Archive("${base}/roc-windows_x86_64-0.1.0_RC1.zip", Zip, "roc-windows_x86_64-0.1.0_RC1/roc.exe")
        _ => Unavailable
    }
}

config = [
    Name("roc-build"),
    Systems(["x86_64-linux", "aarch64-linux", "aarch64-darwin", "x86_64-darwin"]),
    Packages("nix", From(NixPackages("github:NixOS/nixpkgs/nixos-unstable"))),
    Shell("default", [Use("dev-env")]),
    Environment("dev-env", [
        Programs([Fetch("roc", roc_rc1)]),
        Tools([
            "nix#zig",
        ]),
    ]),
    Environment(
        "ci-env",
        [
            Programs([Fetch("roc", roc_rc1)]),
            Tools([
                "nix#zig",
            ]),
        ],
    ),
    Task("ci", [
        Use("ci-env"),
        #Run(["roc", "run", "scripts/ci.do-not-use.roc", "--"])
        Run(["sh", "-c", "scripts/ci.sh"])
    ]),
    Environment(
        "gh-publish-env",
        [
            Programs([Fetch("roc", roc_rc1)]),
            Tools([
                "nix#gh",
                "nix#zig",
            ]),
        ],
    ),
    Task("publish", [
        Use("gh-publish-env"),
        #Run(["roc", "run", "scripts/publish.do-not-use.roc", "--"])
        Run(["sh", "-c", "scripts/publish.sh"])
    ]),
]
