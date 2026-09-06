"""Produce a lightweight, CI-portable quality report for MQ4 and MQ5 source."""

from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRECTORIES = (ROOT / "MQL4", ROOT / "MQL5")
REPORT_DIRECTORY = ROOT / "reports"


@dataclass
class SourceResult:
    path: str
    platform: str
    status: str
    warnings: list[str]


def without_strings_and_comments(source: str) -> str:
    source = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    source = re.sub(r"//.*", "", source)
    return re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)


def inspect_source(path: Path) -> SourceResult:
    source = path.read_text(encoding="utf-8-sig")
    clean_source = without_strings_and_comments(source)
    warnings: list[str] = []

    if clean_source.count("{") != clean_source.count("}"):
        warnings.append("Unbalanced braces")
    if "#property strict" not in source:
        warnings.append("Missing #property strict")
    if not re.search(r"\bvoid\s+OnTick\s*\(", clean_source):
        warnings.append("Missing OnTick event handler")

    platform = "MQL4" if path.suffix.lower() == ".mq4" else "MQL5"
    return SourceResult(
        path=path.relative_to(ROOT).as_posix(),
        platform=platform,
        status="warning" if warnings else "pass",
        warnings=warnings,
    )


def main() -> None:
    sources = sorted(
        source
        for directory in SOURCE_DIRECTORIES
        if directory.exists()
        for source in directory.rglob("*")
        if source.suffix.lower() in {".mq4", ".mq5"}
    )
    results = [inspect_source(source) for source in sources]
    failures = [result for result in results if result.status != "pass"]

    REPORT_DIRECTORY.mkdir(exist_ok=True)
    report = {
        "source_count": len(results),
        "passing_count": len(results) - len(failures),
        "warning_count": len(failures),
        "sources": [asdict(result) for result in results],
    }
    (REPORT_DIRECTORY / "mql-validation.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )

    lines = [
        "## MQL validation report",
        "",
        f"- Sources inspected: **{report['source_count']}**",
        f"- Passing: **{report['passing_count']}**",
        f"- Warnings: **{report['warning_count']}**",
        "",
        "| Source | Platform | Status | Details |",
        "|---|---|---|---|",
    ]
    for result in results:
        details = "; ".join(result.warnings) if result.warnings else "Ready for MetaEditor compilation"
        lines.append(f"| `{result.path}` | {result.platform} | {result.status} | {details} |")
    (REPORT_DIRECTORY / "mql-validation.md").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )

    if not results:
        raise SystemExit("No .mq4 or .mq5 sources found under MQL4/ or MQL5/.")
    if failures:
        raise SystemExit(f"{len(failures)} MQL source file(s) need attention.")


if __name__ == "__main__":
    main()
