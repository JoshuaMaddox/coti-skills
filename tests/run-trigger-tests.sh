#!/usr/bin/env bash
# =============================================================================
# Gate 2: Trigger Accuracy Tests
# Sends 160 queries to Claude API (claude-sonnet-4-6) with all 8 skill
# descriptions loaded as context. Measures whether the correct skill
# would be selected for each query.
#
# Requires: ANTHROPIC_API_KEY env var, jq, python3
# Writes:   tests/results/trigger-results.json
# Exit code: 0 = ≥90% pass, 1 = below threshold
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
QUERIES_FILE="$SCRIPT_DIR/prompts/trigger-queries.json"
RESULTS_FILE="$SCRIPT_DIR/results/trigger-results.json"
MODEL="claude-sonnet-4-6"
PASS_THRESHOLD=144  # 90% of 160

mkdir -p "$SCRIPT_DIR/results"

# Accept ANTHROPIC_API_KEY or fall back to Claude Code OAuth token
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    export ANTHROPIC_API_KEY="$CLAUDE_CODE_OAUTH_TOKEN"
    export USE_BEARER_AUTH="true"
    echo "  ℹ️  Using Claude Code OAuth token for authentication"
  else
    echo "❌ ERROR: ANTHROPIC_API_KEY is not set."
    echo "   Export it: export ANTHROPIC_API_KEY=sk-ant-..."
    exit 1
  fi
fi
USE_BEARER_AUTH="${USE_BEARER_AUTH:-false}"

if ! command -v jq &>/dev/null; then
  echo "❌ ERROR: jq is required. Install with: brew install jq"
  exit 1
fi

echo "============================================================"
echo "COTI Skills — Gate 2: Trigger Accuracy (160 queries)"
echo "Model: $MODEL"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "============================================================"
echo ""

# ------------------------------------------------------------------
# Build the skill-descriptions context from frontmatter of all 8 skills
# ------------------------------------------------------------------
SKILL_NAMES=(
  "coti-account-setup"
  "coti-starter-grant"
  "coti-private-messaging"
  "coti-rewards-management"
  "coti-private-erc20"
  "coti-private-nft"
  "coti-smart-contracts"
  "coti-transaction-tools"
)

SKILLS_CONTEXT="You are a Claude skill router. Given the following 8 skill descriptions, determine which single skill (by name) would be activated for the user's query. Reply with ONLY the skill name (e.g. 'coti-account-setup') or 'none' if no skill applies. Do not explain.\n\nAVAILABLE SKILLS:\n"

for skill in "${SKILL_NAMES[@]}"; do
  SKILL_FILE="$SKILLS_DIR/$skill/SKILL.md"
  # Extract name and description from frontmatter
  NAME=$(awk '/^---$/{if(++n==2) exit} n==1' "$SKILL_FILE" | grep '^name:' | sed 's/^name:[[:space:]]*//')
  DESC=$(awk '/^---$/{if(++n==2) exit} n==1' "$SKILL_FILE" | grep '^description:' | sed 's/^description:[[:space:]]*//')
  SKILLS_CONTEXT+="- name: $NAME\n  description: $DESC\n"
done

SKILLS_CONTEXT+="\nFor the user query below, reply with exactly ONE skill name from the list above, or 'none'. No other text."

# ------------------------------------------------------------------
# Run each query
# ------------------------------------------------------------------
RESULTS=()
PASS=0
FAIL=0
TOTAL=0

TOTAL_QUERIES=$(jq '.queries | length' "$QUERIES_FILE")
echo "Running $TOTAL_QUERIES queries..."
echo ""

# Process with Python for clean JSON handling and API calls
python3 << PYEOF
import json
import os
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone

api_key = os.environ['ANTHROPIC_API_KEY']
use_bearer = os.environ.get('USE_BEARER_AUTH', 'false').lower() == 'true'
model = "$MODEL"
results_file = "$RESULTS_FILE"
queries_file = "$QUERIES_FILE"
skills_context = """$SKILLS_CONTEXT"""

with open(queries_file) as f:
    data = json.load(f)

queries = data['queries']
results = []
passed = 0
failed = 0

def call_claude(system_prompt, user_message):
    payload = {
        "model": model,
        "max_tokens": 50,
        "system": system_prompt,
        "messages": [{"role": "user", "content": user_message}]
    }
    if use_bearer:
        headers = {
            "Authorization": f"Bearer {api_key}",
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
    else:
        headers = {
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=json.dumps(payload).encode(),
        headers=headers
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = json.loads(resp.read())
        return body["content"][0]["text"].strip().lower().rstrip(".,;:")

for i, q in enumerate(queries):
    qid = q["id"]
    query = q["query"]
    expected = q["expected"]
    qtype = q["type"]
    skill = q["skill"]

    try:
        actual = call_claude(skills_context, query)
        # Normalize: strip quotes, whitespace, and map common variations
        actual = actual.strip("'\"").strip()

        if qtype == "negative":
            # For negative tests: pass if no skill triggered (none) or wrong skill triggered
            # We want: actual == 'none'
            is_pass = (actual == "none")
        else:
            # For positive/paraphrased: pass if expected skill matches
            is_pass = (actual == expected)

        result_val = "PASS" if is_pass else "FAIL"
        if is_pass:
            passed += 1
        else:
            failed += 1

        result_entry = {
            "queryId": qid,
            "skill": skill,
            "type": qtype,
            "query": query,
            "expected": expected,
            "actual": actual,
            "result": result_val,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        results.append(result_entry)

        icon = "✅" if is_pass else "❌"
        print(f"  {icon} {qid} [{qtype:12s}] expected={expected:30s} actual={actual}")

    except Exception as e:
        failed += 1
        result_entry = {
            "queryId": qid,
            "skill": skill,
            "type": qtype,
            "query": query,
            "expected": expected,
            "actual": f"ERROR: {str(e)}",
            "result": "FAIL",
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        results.append(result_entry)
        print(f"  ❌ {qid} ERROR: {str(e)}")

    # Small delay to avoid rate limiting
    if (i + 1) % 20 == 0:
        print(f"\n  [{i+1}/{len(queries)} completed — {passed} pass, {failed} fail so far]\n")
        time.sleep(1)

# Compute per-skill breakdown
skill_stats = {}
for r in results:
    s = r["skill"]
    if s not in skill_stats:
        skill_stats[s] = {"pass": 0, "fail": 0, "total": 0}
    skill_stats[s]["total"] += 1
    if r["result"] == "PASS":
        skill_stats[s]["pass"] += 1
    else:
        skill_stats[s]["fail"] += 1

total = len(queries)
gate_pass = passed >= $PASS_THRESHOLD
summary = {
    "gate": "Gate 2: Trigger Accuracy",
    "model": model,
    "total_queries": total,
    "passed": passed,
    "failed": failed,
    "pass_rate": round(passed / total * 100, 1),
    "threshold": $PASS_THRESHOLD,
    "gate_result": "PASS" if gate_pass else "FAIL",
    "per_skill": skill_stats,
    "queries": results,
    "timestamp": datetime.now(timezone.utc).isoformat()
}

os.makedirs(os.path.dirname(results_file), exist_ok=True)
with open(results_file, "w") as f:
    json.dump(summary, f, indent=2)

print("\n============================================================")
print("GATE 2 RESULTS")
print("============================================================")
for sk, st in sorted(skill_stats.items()):
    rate = round(st["pass"] / st["total"] * 100)
    icon = "🟢" if st["fail"] == 0 else ("🟡" if rate >= 90 else "🔴")
    print(f"  {icon} {sk:35s} {st['pass']:2d}/{st['total']:2d} ({rate}%)")

print(f"\nTotal: {passed}/{total} passed ({round(passed/total*100,1)}%)")
print(f"Threshold: {$PASS_THRESHOLD}/{total} (90%)")
print("")
if gate_pass:
    print("🟢 GATE 2: PASS")
    sys.exit(0)
else:
    print(f"🔴 GATE 2: FAIL — only {passed}/{total} passed (need {$PASS_THRESHOLD}+)")
    sys.exit(1)
PYEOF
