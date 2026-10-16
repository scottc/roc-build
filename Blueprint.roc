app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.5.0/CupqPH9snWf11g7tWgcJf4Yg5cJ3K9fhL7fSgqDcqJQH.tar.zst" }

# roc versions: https://github.com/roc-lang/roc-overlay/blob/master/sources.json

config = [
	Name("roc-build"),
	Overlay("roc", "github:roc-lang/roc-overlay"),
	Shell("default", [Use("dev-env")]),
	Environment("dev-env", [
    	Overlays(["roc"]),
    	Command("roc", "rocpkgs.nightly-2026-10-15-38e6c42"),
  			Tools([
				"zig",
			]),
	]),
	Environment(
		"ci-env",
		[
			Overlays(["roc"]),
			Command("roc", "rocpkgs.nightly-2026-10-15-38e6c42"),
			Tools([
				"zig",
			]),
		],
	),
	Task("ci", [
	    Use("ci-env"),
		Run([
		    "scripts/ci.roc", "--",
		])
	]),
	Environment(
		"gh-publish-env",
		[
			Overlays(["roc"]),
			Command("roc", "rocpkgs.nightly-2026-10-15-38e6c42"),
			Tools([
			    "gh",
    			"zig",
			]),
		],
	),
	Task("publish", [
	    Use("gh-publish-env"),
		Run([
		    "scripts/publish.roc", "--",
		])
	]),
]
