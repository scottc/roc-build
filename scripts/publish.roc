app [main!] {
    pf: platform "../platform/main.roc",
}

import pf.Build
import pf.BuildCmd
import pf.Log

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    Log.info!("Publish: gen glue → build host → bundle platform")

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

## Stage labeled assets + NOTES.md, then gh release create.
## Asset name: <original-hash>.tar.zst
##
## Important: never put bash `${name}` inside a Roc string literal.
## Always build it with sh_dollar_brace("name").
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

    # Emit one staging stanza per engine (slug + label baked in at graph-build time)
    $stage_parts : List(Str)
    var $stage_parts = []

        $stage_parts =
            List.concat(
                $stage_parts,
                [
                    "stage_engine '",
                    "' '",
                    "' '",
                    "'\n",
                ],
            )
    stage_loop = Str.join_with($stage_parts, "")

    # Bash ${…} fragments (built outside Roc interpolations)
    b_token = sh_dollar_brace("GITHUB_TOKEN:-")
    b_repo_env = sh_dollar_brace("GITHUB_REPOSITORY:-")
    b_files0 = sh_dollar_brace("_files[0]")
    b_assets_len = sh_dollar_brace("#ASSETS[@]")
    b_assets_all = sh_dollar_brace("ASSETS[@]")
    b_labels_i = sh_dollar_brace("LABELS[$i]")
    b_slugs_i = sh_dollar_brace("SLUGS[$i]")
    b_assets_i = sh_dollar_brace("ASSETS[$i]")
    b_urls_i = sh_dollar_brace("URLS[$i]")
    b_is_base_i = sh_dollar_brace("IS_BASE[$i]")
    b_slug = sh_dollar_brace("_slug")
    b_hash = sh_dollar_brace("_hash")
    b_lab = sh_dollar_brace("_lab")
    b_url = sh_dollar_brace("_url")
    b_base = sh_dollar_brace("_base")
    b_repo = sh_dollar_brace("REPO")
    b_tag = sh_dollar_brace("TAG")
    b_sha = sh_dollar_brace("SHA")
    b_dest = sh_dollar_brace("_dest")
    b_src = sh_dollar_brace("_src")
    b_dir = sh_dollar_brace("_dir")
    b_label = sh_dollar_brace("_label")

    script =
        Str.join_with(
            [
                "set -eu\n",
                "if [ -z \"",
                b_token,
                "\" ]; then\n",
                "  echo \"[publish] GITHUB_TOKEN required\" >&2\n",
                "  exit 1\n",
                "fi\n",
                "if ! command -v gh >/dev/null 2>&1; then\n",
                "  echo \"[publish] gh CLI not found\" >&2\n",
                "  exit 1\n",
                "fi\n",
                "REPO=\"",
                b_repo_env,
                "\"\n",
                "if [ -z \"$REPO\" ]; then\n",
                "  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)\n",
                "fi\n",
                "if [ -z \"$REPO\" ]; then\n",
                "  echo \"[publish] GITHUB_REPOSITORY unset and gh repo view failed\" >&2\n",
                "  exit 1\n",
                "fi\n",
                tag_line,
                "SHA=$(git rev-parse --short=7 HEAD 2>/dev/null || echo nogit)\n",
                "STAGING=release-assets\n",
                "rm -rf \"$STAGING\"\n",
                "mkdir -p \"$STAGING\"\n",
                "NOTES=\"$STAGING/NOTES.md\"\n",
                "ASSETS=()\n",
                "URLS=()\n",
                "LABELS=()\n",
                "SLUGS=()\n",
                "IS_BASE=()\n",
                "\n",
                "stage_engine() {\n",
                "  _slug=\"$1\"\n",
                "  _label=\"$2\"\n",
                "  _base=\"$3\"\n",
                "  _dir=\"bundle-out/",
                b_slug,
                "\"\n",
                "  if [ ! -d \"",
                b_dir,
                "\" ]; then\n",
                "    echo \"[publish] missing ",
                b_dir,
                "\" >&2\n",
                "    return 0\n",
                "  fi\n",
                "  # shellcheck disable=SC2206\n",
                "  _files=(\"",
                b_dir,
                "\"/*.tar.zst)\n",
                "  if [ ! -e \"",
                b_files0,
                "\" ]; then\n",
                "    echo \"[publish] no .tar.zst under ",
                b_dir,
                "\" >&2\n",
                "    return 0\n",
                "  fi\n",
                "  _src=\"",
                b_files0,
                "\"\n",
                "  _hash=$(basename \"",
                b_src,
                "\" .tar.zst)\n",
                "  _dest=\"$STAGING/",
                b_slug,
                "-",
                b_hash,
                ".tar.zst\"\n",
                "  cp -f \"",
                b_src,
                "\" \"",
                b_dest,
                "\"\n",
                "  ASSETS+=(\"",
                b_dest,
                "\")\n",
                "  URLS+=(\"https://github.com/",
                b_repo,
                "/releases/download/",
                b_tag,
                "/$(basename \"",
                b_dest,
                "\")\")\n",
                "  LABELS+=(\"",
                b_label,
                "\")\n",
                "  SLUGS+=(\"",
                b_slug,
                "\")\n",
                "  IS_BASE+=(\"",
                b_base,
                "\")\n",
                "  echo \"[publish] staged $(basename \"",
                b_dest,
                "\")\"\n",
                "}\n",
                "\n",
                stage_loop,
                "\n",
                "if [ ",
                b_assets_len,
                " -eq 0 ]; then\n",
                "  echo \"[publish] no assets to upload\" >&2\n",
                "  exit 1\n",
                "fi\n",
                "\n",
                "# ---- NOTES.md ----\n",
                "{\n",
                "  echo \"## roc-build ",
                b_tag,
                "\"\n",
                "  echo\n",
                "  echo \"Commit: \\`",
                b_sha,
                "\\`\"\n",
                "  echo\n",
                "  echo \"### Assets\"\n",
                "  echo\n",
                "  i=0\n",
                "  while [ \"$i\" -lt ",
                b_assets_len,
                " ]; do\n",
                "    echo \"- **",
                b_labels_i,
                "** (\\`",
                b_slugs_i,
                "\\`)\"\n",
                "    echo \"  - file: \\`$(basename \"",
                b_assets_i,
                "\")\\`\"\n",
                "    echo \"  - url: \\`",
                b_urls_i,
                "\\`\"\n",
                "    echo\n",
                "    i=$((i + 1))\n",
                "  done\n",
                "  echo \"### Getting started\"\n",
                "  echo\n",
                "  echo \"Pick **one** platform URL below (uncomment / swap as needed).\"\n",
                "  echo\n",
                "  i=0\n",
                "  while [ \"$i\" -lt ",
                b_assets_len,
                " ]; do\n",
                "    _lab=\"",
                b_labels_i,
                "\"\n",
                "    _url=\"",
                b_urls_i,
                "\"\n",
                "    _base=\"",
                b_is_base_i,
                "\"\n",
                "    echo \"#### ",
                b_lab,
                "\"\n",
                "    echo\n",
                "    echo '```roc'\n",
                "    echo 'app [main!] {'\n",
                "    if [ \"",
                b_base,
                "\" = \"yes\" ]; then\n",
                "      echo \"    # [baseline] ",
                b_lab,
                "\"\n",
                "      echo \"    pf: platform \\\"",
                b_url,
                "\\\",\"\n",
                "    else\n",
                "      echo \"    # ",
                b_lab,
                "\"\n",
                "      echo \"    pf: platform \\\"",
                b_url,
                "\\\",\"\n",
                "    fi\n",
                "    echo '}'\n",
                "    echo\n",
                "    echo '}'\n",
                "    echo '```'\n",
                "    echo\n",
                "    i=$((i + 1))\n",
                "  done\n",
                "  echo \"### All platforms in one app header (pick one)\"\n",
                "  echo\n",
                "  echo '```roc'\n",
                "  echo 'app [main!] {'\n",
                "  i=0\n",
                "  while [ \"$i\" -lt ",
                b_assets_len,
                " ]; do\n",
                "    _lab=\"",
                b_labels_i,
                "\"\n",
                "    _url=\"",
                b_urls_i,
                "\"\n",
                "    _base=\"",
                b_is_base_i,
                "\"\n",
                "    if [ \"",
                b_base,
                "\" = \"yes\" ]; then\n",
                "      echo \"    # [baseline] ",
                b_lab,
                "\"\n",
                "      echo \"    pf: platform \\\"",
                b_url,
                "\\\",\"\n",
                "    else\n",
                "      echo \"    # ",
                b_lab,
                "\"\n",
                "      echo \"    # pf: platform \\\"",
                b_url,
                "\\\",\"\n",
                "    fi\n",
                "    i=$((i + 1))\n",
                "  done\n",
                "  echo '}'\n",
                "  echo '```'\n",
                "} >\"$NOTES\"\n",
                "\n",
                "echo \"[publish] release ",
                b_tag,
                " (",
                b_assets_len,
                " assets)\"\n",
                "gh release create \"",
                b_tag,
                "\" ",
                b_assets_all,
                " \\\n",
                "  --title \"roc-build ",
                b_tag,
                "\" \\\n",
                "  --notes-file \"$NOTES\"\n",
            ],
            "",
        )

    cmd = BuildCmd.new({
        program: "sh",
        args: ["-c", script],
        description: "GitHub release (labeled assets + notes)",
    })

    cmd
}
