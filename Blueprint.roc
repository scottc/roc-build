app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.11.0/EuSPs8vc71qJNFg29YzegvVRL1bR9pKqUYDHFiSCPTQ1.tar.zst" }

import pf.Recipes

# roc versions: https://github.com/roc-lang/roc-overlay/blob/master/sources.json

config = [
	Name("roc-build"),
	Packages("nix", From(NixPackages("github:NixOS/nixpkgs/nixos-unstable"))),
	Shell("default", [Use("dev-env")]),
	Environment("dev-env", [
	    Programs([Fetch("roc", Recipes.roc_nightly("nightly-2026-10-28-bad769b"))]),
		Tools([
			"nix#zig",
		]),
	]),
	Environment(
		"ci-env",
		[
		    Programs([Fetch("roc", Recipes.roc_nightly("nightly-2026-10-28-bad769b"))]),
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
		    Programs([Fetch("roc", Recipes.roc_nightly("nightly-2026-10-28-bad769b"))]),
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
