# Renders `dart pub outdated --json` as a markdown table of direct and dev
# dependencies whose latest release is newer than the resolved version.
# Used by ai-research.yml; no upgrade is attempted.
[.packages[]
  | select(.kind != "transitive" and .current != null and .latest != null)
  | select(.current.version != .latest.version)]
| sort_by(.package)
| if length == 0 then
    "All direct dependencies are on their latest release."
  else
    "| Package | Kind | Current | Upgradable | Latest | Note |",
    "|---|---|---|---|---|---|",
    (.[] | "| `\(.package)` | \(.kind) | \(.current.version) | \(.upgradable.version // "-") | \(.latest.version) | \(
      [ (if (.current.version | split(".")[0]) != (.latest.version | split(".")[0]) then "major" else empty end),
        (if .isDiscontinued then "discontinued" else empty end),
        (if .isCurrentAffectedByAdvisory then "**advisory**" else empty end),
        (if .isCurrentRetracted then "retracted" else empty end)
      ] | join(", ")) |"),
    "",
    "Report only: upgrades come through the weekly Dependabot PR, which runs full CI."
  end
