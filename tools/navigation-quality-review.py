"""Local speech-journal audit; optional Antigravity review of counts only.

Never edits app policy or sends raw speech, VIN, locations or timestamps to AI.
The journal records playback starts, so completion and missed cues are unknown.
"""
import argparse
import asyncio
import json
import math
from pathlib import Path


def audit(lines):
    report = dict(navigation_starts=0, long_sentences=0,
                  duplicate_starts_within_20s=0, invalid_rows=0)
    recent = {}
    for line in lines:
        try:
            row = json.loads(line)
            if not isinstance(row, dict):
                raise ValueError()
            if row.get("navigation") is not True:
                continue
            text, at, vin = row["text"], row["at"], row["vin"]
            if not isinstance(text, str) or not isinstance(vin, str) or not vin:
                raise ValueError()
            if isinstance(at, bool) or not isinstance(at, (int, float)):
                raise ValueError()
            if not math.isfinite(at) or not text.strip():
                raise ValueError()
            report["navigation_starts"] += 1
            report["long_sentences"] += int(len(text) > 55)
            # VIN is used for local separation only and is never exported.
            key = (vin, text)
            previous = recent.get(key)
            if previous is not None and 0 <= at - previous < 20:
                report["duplicate_starts_within_20s"] += 1
            recent[key] = max(at, previous) if previous is not None else at
        except (ValueError, KeyError, TypeError):
            report["invalid_rows"] += 1
    report["limits"] = ["playback_start_only", "no_completion_or_position_evidence",
                        "long_sentence_is_a_review_candidate_not_a_failure",
                        "duplicate_can_be_legitimate"]
    return report


async def agent_review(report):
    # Lazy import: local auditing needs no SDK, API key or package installation.
    from google.antigravity import Agent, LocalAgentConfig
    from google.antigravity.hooks.policy import deny
    config = LocalAgentConfig(
        policies=[deny("*")],
        system_instructions=(
            "Review navigation speech quality from aggregated counts only. "
            "Return Korean review candidates and required replay tests. "
            "Do not invent driving conditions, causes, measurements or completion. "
            "Do not change routes, maneuver facts, safety warnings or app code. "
            "No tools are allowed. Distinguish observations from hypotheses."
        ),
    )
    async with Agent(config) as agent:
        response = await agent.chat(json.dumps(report, ensure_ascii=False))
        return await response.text()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("journal", type=Path)
    parser.add_argument("--agent", action="store_true",
                        help="Explicitly invoke Gemini via Antigravity; API usage may be billed")
    args = parser.parse_args()
    if args.journal.stat().st_size > 2 * 1024 * 1024:
        parser.error("Journal exceeds the app's 2 MiB read limit")
    with args.journal.open(encoding="utf-8") as stream:
        report = audit(stream)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if args.agent:
        print(asyncio.run(asyncio.wait_for(agent_review(report), timeout=90)))


if __name__ == "__main__":
    main()
