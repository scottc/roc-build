app [main!] {
    # TODO: we cannot build self-hosted
    # because we need the zig binaries to exist before we can run
    # chicken & egg bootstrapping problem
    # We could use a previously built zig binaries,
    # OR! we can compile the current version with zig...
    # AND THEN... we can continue.
    pf: platform "../platform/main.roc",
}

import pf.Build
import pf.BuildCmd
import pf.Log

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    Log.info!("Publish: gen glue -> build host -> bundle platform")

    mkdir_targets_out = BuildCmd.new({
        program: "mkdir",
        args: ["-p", "platform/targets-out/x64musl/"],
        description: "Ensure 'platform/targets-out/x64musl/' dir."
    })

    mkdir_bundle_out = BuildCmd.new({
        program: "mkdir",
        args: ["-p", "bundle-out/"],
        description: "Ensure 'bundle-out/' dir."
    })

    gen_glue = BuildCmd.new({
        program: "sh",
        args: ["-c", "scripts/gen_glue.sh"],
        description: "Generate host/roc_platform_abi.zig",
    })

    cp = BuildCmd.new({
        program: "cp",
        args: ["-a", "vendor/targets/x64musl/.", "platform/targets-out/x64musl/"],
        description: "Install platform dependencies",
    })
    .depends_on([mkdir_targets_out])

    zig_build_lib =
        BuildCmd.new({
            program: "zig",
            args: [
                "build-lib",
                "host/host.zig",
                "-femit-bin=platform/targets-out/x64musl/libhost.a",
                "-OReleaseSafe",
                "-target", "x86_64-linux-musl",
                "-lc",
                "-fPIC",
            ],
            description: "Build Zig Host",
        })
        .depends_on([gen_glue, mkdir_targets_out])

    roc_bundle =
        BuildCmd.new({
            program: "roc",
            args: [
                "bundle",
                "main.roc",
                "Build.roc",
                "Host.roc",
                "Log.roc",
                "targets-out/x64musl/crt1.o",
                "targets-out/x64musl/libc.a",
                "targets-out/x64musl/libcompiler_rt.a",
                "targets-out/x64musl/libzigc.a",
                "targets-out/x64musl/libhost.a",
            ],
            description: "Roc Bundle",
        })
        .with_cwd("platform/")
        .depends_on([cp, zig_build_lib, mkdir_bundle_out])

    mv = BuildCmd.new({
        program: "mv",
        args: ["platform/*.tar.zst", "bundle-out/"],
        description: "mv bundle to 'bundle-out/'",
    })
    .depends_on([roc_bundle])

    # TODO: GHA to publish a release.
    gh_pub = gh_publish(AutoTag).depends_on([mv])

    graph = Build.graph([
        mkdir_targets_out,
        mkdir_bundle_out,
        gen_glue,
        cp,
        zig_build_lib,
        roc_bundle,
        mv,
        gh_pub
    ])

    match Build.run!(graph) {
        Ok({}) => {
            Log.info!("all tasks finished")
            Ok({})
        }
        Err(BuildFailed(msg)) => {
            Log.error!(msg)
            Err(Exit(1))
        }
    }
}

## Shell script helper
## Bash ${…} fragments (built outside Roc interpolations)
sh_dollar_brace : Str -> Str
sh_dollar_brace = |inner| Str.concat("$", Str.concat("{", Str.concat(inner, "}")))

GHTag : [Tag(Str), AutoTag]

gh_publish : GHTag -> BuildCmd
gh_publish = |tag| {
    tag_line =
        match tag {
            Tag(t) => Str.concat("TAG='", Str.concat(t, "'\n"))
            AutoTag =>
                Str.join_with(
                    [
                        "SHORT=$(git rev-parse --short=7 HEAD 2>/dev/null || echo nogit)\n",
                        "TAG=\"nightly-$(date -u +%Y-%m-%d)-$SHORT\"\n",
                    ],
                    "",
                )
        }

    b_token = sh_dollar_brace("GITHUB_TOKEN:-")
    b_repo_env = sh_dollar_brace("GITHUB_REPOSITORY:-")
    b_files0 = sh_dollar_brace("_files[0]")
    b_src = sh_dollar_brace("_src")
    b_hash = sh_dollar_brace("_hash")
    b_dest = sh_dollar_brace("_dest")
    b_repo = sh_dollar_brace("REPO")
    b_tag = sh_dollar_brace("TAG")
    b_sha = sh_dollar_brace("SHA")
    b_url = sh_dollar_brace("_url")
    b_asset = sh_dollar_brace("_asset")

    script =
        Str.join_with(
            [
                "set -eu\n",
                "if [ -z \"", b_token, "\" ]; then\n",
                "  echo \"[publish] GITHUB_TOKEN required\" >&2\n",
                "  exit 1\n",
                "fi\n",
                "if ! command -v gh >/dev/null 2>&1; then\n",
                "  echo \"[publish] gh CLI not found\" >&2\n",
                "  exit 1\n",
                "fi\n",
                "REPO=\"", b_repo_env, "\"\n",
                "if [ -z \"$REPO\" ]; then\n",
                "  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)\n",
                "fi\n",
                "if [ -z \"$REPO\" ]; then\n",
                "  echo \"[publish] GITHUB_REPOSITORY unset and gh repo view failed\" >&2\n",
                "  exit 1\n",
                "fi\n",
                tag_line,
                "SHA=$(git rev-parse --short=7 HEAD 2>/dev/null || echo nogit)\n",
                "\n",
                "# One platform bundle from bundle-out/\n",
                "_files=(bundle-out/*.tar.zst)\n",
                "if [ ! -e \"", b_files0, "\" ]; then\n",
                "  echo \"[publish] no .tar.zst in bundle-out/\" >&2\n",
                "  exit 1\n",
                "fi\n",
                "_src=\"", b_files0, "\"\n",
                "_hash=$(basename \"", b_src, "\" .tar.zst)\n",
                "STAGING=release-assets\n",
                "rm -rf \"$STAGING\"\n",
                "mkdir -p \"$STAGING\"\n",
                "_dest=\"$STAGING/", b_hash, ".tar.zst\"\n",
                "cp -f \"", b_src, "\" \"", b_dest, "\"\n",
                "_asset=\"", b_dest, "\"\n",
                "_url=\"https://github.com/", b_repo, "/releases/download/", b_tag, "/$(basename \"", b_dest, "\")\"\n",
                "NOTES=\"$STAGING/NOTES.md\"\n",
                "\n",
                "{\n",
                "  echo \"## roc-build ", b_tag, "\"\n",
                "  echo\n",
                "  echo \"Commit: \\`", b_sha, "\\`\"\n",
                "  echo\n",
                "  echo \"### Asset\"\n",
                "  echo\n",
                "  echo \"- file: \\`$(basename \"", b_asset, "\")\\`\"\n",
                "  echo \"- url: \\`", b_url, "\\`\"\n",
                "  echo\n",
                "  echo \"### App header (copy & paste)\"\n",
                "  echo\n",
                "  echo '```roc'\n",
                "  echo 'app [main!] {'\n",
                "  echo \"    pf: platform \\\"", b_url, "\\\",\"\n",
                "  echo '}'\n",
                "  echo '```'\n",
                "  echo\n",
                "  echo \"Target: **x86_64-linux-musl**\"\n",
                "} >\"$NOTES\"\n",
                "\n",
                "echo \"[publish] release ", b_tag, "\"\n",
                "gh release create \"", b_tag, "\" \"", b_asset, "\" \\\n",
                "  --title \"roc-build ", b_tag, "\" \\\n",
                "  --notes-file \"$NOTES\"\n",
            ],
            "",
        )

    BuildCmd.new({
        program: "sh",
        args: ["-c", script],
        description: "GitHub release (bundle + notes)",
    })
}
