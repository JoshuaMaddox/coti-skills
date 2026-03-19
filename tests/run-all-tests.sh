#!/usr/bin/env bash
# =============================================================================
# Master Test Runner — COTI Skills Testing Suite
# Runs all 4 gates in sequence and writes a final summary report.
#
# Usage:
#   bash tests/run-all-tests.sh
#
# Required env vars for Gates 2–4:
#   ANTHROPIC_API_KEY         - Anthropic API key (claude-sonnet-4-6)
#   COTI_PRIVATE_KEY          - Test wallet private key (0x...)
#   COTI_AES_KEY              - Test wallet AES encryption key
#   COTI_CONTRACT_ADDRESS     - Deployed PrivateAgentMessaging contract address
#   COTI_RECIPIENT_ADDRESS    - Recipient wallet address for messaging tests
#   COTI_SECOND_ADDRESS       - Second wallet address for transfer/approval tests
#
# Optional:
#   COTI_SENDER_ADDRESS       - Sender address (defaults to COTI_RECIPIENT_ADDRESS)
#   SKIP_GATES                - Comma-separated gates to skip, e.g. "3,4"
#
# Output:
#   tests/results/structural-results.txt
#   tests/results/trigger-results.json
#   tests/results/functional-results.json
#   tests/results/integration-results.json
#   tests/results/summary.md
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
SUMMARY_FILE="$RESULTS_DIR/summary.md"

mkdir -p "$RESULTS_DIR"
START_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

SKIP_GATES="${SKIP_GATES:-}"

# Gate results: 0=not run, 1=pass, 2=fail
declare -A GATE_RESULT
GATE_RESULT[1]="not_run"
GATE_RESULT[2]="not_run"
GATE_RESULT[3]="not_run"
GATE_RESULT[4]="not_run"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          COTI SKILLS — FULL TEST SUITE                   ║"
echo "║          Model: claude-sonnet-4-6                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Started: $START_TIME"
echo "Skills:  $SKILLS_DIR"
echo "Results: $RESULTS_DIR"
echo ""

# ------------------------------------------------------------------
# Helper: skip check
# ------------------------------------------------------------------
should_skip() {
  local gate="$1"
  [[ ",$SKIP_GATES," == *",$gate,"* ]]
}

# ------------------------------------------------------------------
# GATE 1: Structural Tests (automated, no API needed)
# ------------------------------------------------------------------
echo "┌──────────────────────────────────────────────────────────┐"
echo "│  GATE 1: Structural Compliance (112 assertions)           │"
echo "└──────────────────────────────────────────────────────────┘"

if should_skip 1; then
  echo "  ⏭  SKIPPED (SKIP_GATES includes 1)"
  GATE_RESULT[1]="skipped"
else
  if bash "$SCRIPT_DIR/structural-tests.sh" 2>&1; then
    GATE_RESULT[1]="pass"
    echo ""
    echo "  🟢 Gate 1 complete."
  else
    GATE_RESULT[1]="fail"
    echo ""
    echo "  🔴 Gate 1 FAILED. Fix structural issues before running Gates 2–4."
    echo "  See: $RESULTS_DIR/structural-results.txt"
    # Don't exit — still run remaining gates and write summary
  fi
fi

echo ""

# ------------------------------------------------------------------
# GATE 2: Trigger Accuracy (160 queries → Claude API)
# ------------------------------------------------------------------
echo "┌──────────────────────────────────────────────────────────┐"
echo "│  GATE 2: Trigger Accuracy (160 queries, ≥90% required)   │"
echo "└──────────────────────────────────────────────────────────┘"

if should_skip 2; then
  echo "  ⏭  SKIPPED (SKIP_GATES includes 2)"
  GATE_RESULT[2]="skipped"
elif [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "  ⚠️  SKIPPED — ANTHROPIC_API_KEY not set"
  GATE_RESULT[2]="skipped"
else
  if bash "$SCRIPT_DIR/run-trigger-tests.sh" 2>&1; then
    GATE_RESULT[2]="pass"
    echo ""
    echo "  🟢 Gate 2 complete."
  else
    GATE_RESULT[2]="fail"
    echo ""
    echo "  🔴 Gate 2 FAILED. See: $RESULTS_DIR/trigger-results.json"
  fi
fi

echo ""

# ------------------------------------------------------------------
# GATE 3: Functional Tests (48 MCP tool calls → COTI testnet)
# ------------------------------------------------------------------
echo "┌──────────────────────────────────────────────────────────┐"
echo "│  GATE 3: Functional Correctness (48 tool calls, 100%)    │"
echo "└──────────────────────────────────────────────────────────┘"

GATE3_PREREQS_MET=true
for var in ANTHROPIC_API_KEY COTI_PRIVATE_KEY COTI_AES_KEY COTI_CONTRACT_ADDRESS COTI_RECIPIENT_ADDRESS COTI_SECOND_ADDRESS; do
  if [[ -z "${!var:-}" ]]; then
    echo "  ⚠️  Missing: $var"
    GATE3_PREREQS_MET=false
  fi
done

if should_skip 3; then
  echo "  ⏭  SKIPPED (SKIP_GATES includes 3)"
  GATE_RESULT[3]="skipped"
elif [[ "$GATE3_PREREQS_MET" == "false" ]]; then
  echo "  ⚠️  SKIPPED — missing required environment variables (see above)"
  GATE_RESULT[3]="skipped"
else
  if bash "$SCRIPT_DIR/run-functional-tests.sh" 2>&1; then
    GATE_RESULT[3]="pass"
    echo ""
    echo "  🟢 Gate 3 complete."
  else
    GATE_RESULT[3]="fail"
    echo ""
    echo "  🔴 Gate 3 FAILED. See: $RESULTS_DIR/functional-results.json"
  fi
fi

echo ""

# ------------------------------------------------------------------
# GATE 4: Integration Tests (3 workflows, 17 steps)
# ------------------------------------------------------------------
echo "┌──────────────────────────────────────────────────────────┐"
echo "│  GATE 4: Integration Workflows (17 steps, 100%)          │"
echo "└──────────────────────────────────────────────────────────┘"

if should_skip 4; then
  echo "  ⏭  SKIPPED (SKIP_GATES includes 4)"
  GATE_RESULT[4]="skipped"
elif [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "  ⚠️  SKIPPED — ANTHROPIC_API_KEY not set"
  GATE_RESULT[4]="skipped"
else
  if bash "$SCRIPT_DIR/run-integration-tests.sh" 2>&1; then
    GATE_RESULT[4]="pass"
    echo ""
    echo "  🟢 Gate 4 complete."
  else
    GATE_RESULT[4]="fail"
    echo ""
    echo "  🔴 Gate 4 FAILED. See: $RESULTS_DIR/integration-results.json"
  fi
fi

# ------------------------------------------------------------------
# Final summary — write summary.md
# ------------------------------------------------------------------
END_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

gate_icon() {
  case "$1" in
    pass)    echo "🟢 PASS" ;;
    fail)    echo "🔴 FAIL" ;;
    skipped) echo "⏭  SKIP" ;;
    not_run) echo "⬜ N/A"  ;;
  esac
}

# Determine overall ship status
SHIP="YES"
for g in 1 2 3 4; do
  if [[ "${GATE_RESULT[$g]}" == "fail" ]]; then
    SHIP="NO"
    break
  fi
done

cat > "$SUMMARY_FILE" << EOF
# COTI Skills Test Suite — Results Summary

**Run started:** $START_TIME
**Run ended:**   $END_TIME
**Model:**       claude-sonnet-4-6

---

## Gate Results

| Gate | Description | Threshold | Result |
|------|-------------|-----------|--------|
| Gate 1 | Structural Compliance | 112/112 assertions | $(gate_icon "${GATE_RESULT[1]}") |
| Gate 2 | Trigger Accuracy | ≥144/160 queries (90%) | $(gate_icon "${GATE_RESULT[2]}") |
| Gate 3 | Functional Correctness | 48/48 tool calls | $(gate_icon "${GATE_RESULT[3]}") |
| Gate 4 | Integration Workflows | 17/17 steps | $(gate_icon "${GATE_RESULT[4]}") |

---

## Ship / No-Ship Verdict

EOF

if [[ "$SHIP" == "YES" ]]; then
  echo "### ✅ SHIP — All gates passed" >> "$SUMMARY_FILE"
else
  echo "### ❌ NO SHIP — One or more gates failed" >> "$SUMMARY_FILE"
  echo "" >> "$SUMMARY_FILE"
  echo "Failed gates:" >> "$SUMMARY_FILE"
  for g in 1 2 3 4; do
    if [[ "${GATE_RESULT[$g]}" == "fail" ]]; then
      echo "- Gate $g" >> "$SUMMARY_FILE"
    fi
  done
fi

cat >> "$SUMMARY_FILE" << EOF

---

## Result Files

| File | Gate |
|------|------|
| \`tests/results/structural-results.txt\` | Gate 1 |
| \`tests/results/trigger-results.json\` | Gate 2 |
| \`tests/results/functional-results.json\` | Gate 3 |
| \`tests/results/integration-results.json\` | Gate 4 |

EOF

# Print to terminal
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                  FINAL SUMMARY                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Gate 1 — Structural (112/112):       $(gate_icon "${GATE_RESULT[1]}")"
echo "  Gate 2 — Triggers   (≥144/160):      $(gate_icon "${GATE_RESULT[2]}")"
echo "  Gate 3 — Functional (48/48):         $(gate_icon "${GATE_RESULT[3]}")"
echo "  Gate 4 — Integration (17/17):        $(gate_icon "${GATE_RESULT[4]}")"
echo ""

if [[ "$SHIP" == "YES" ]]; then
  echo "  ╔══════════════════════════╗"
  echo "  ║  ✅  READY TO SHIP       ║"
  echo "  ╚══════════════════════════╝"
else
  echo "  ╔══════════════════════════╗"
  echo "  ║  ❌  NOT READY TO SHIP   ║"
  echo "  ╚══════════════════════════╝"
fi

echo ""
echo "Full report: $SUMMARY_FILE"
echo ""

# Exit 0 only if all run gates passed
ALL_PASS=true
for g in 1 2 3 4; do
  if [[ "${GATE_RESULT[$g]}" == "fail" ]]; then
    ALL_PASS=false
    break
  fi
done

if $ALL_PASS; then exit 0; else exit 1; fi
