#!/usr/bin/env bash
# =============================================================================
# Gate 1: Structural Compliance Tests
# Validates all 14 assertions × 8 skills = 112 total checks
# Writes full results to tests/results/structural-results.txt
# Exit code: 0 = all pass, 1 = any fail
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_FILE="$SCRIPT_DIR/results/structural-results.txt"

mkdir -p "$SCRIPT_DIR/results"
> "$RESULTS_FILE"  # clear/create

PASS=0
FAIL=0
TOTAL=0

EXPECTED_SKILLS=(
  "coti-account-setup"
  "coti-starter-grant"
  "coti-private-messaging"
  "coti-rewards-management"
  "coti-private-erc20"
  "coti-private-nft"
  "coti-smart-contracts"
  "coti-transaction-tools"
)

# ------------------------------------------------------------------
log() { echo "$1" | tee -a "$RESULTS_FILE"; }
pass() { log "  ✅ PASS  S${1}: ${2}"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { log "  ❌ FAIL  S${1}: ${2}"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }
# ------------------------------------------------------------------

log "============================================================"
log "COTI Skills — Gate 1: Structural Compliance"
log "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
log "Skills dir: $SKILLS_DIR"
log "============================================================"
log ""

# ------------------------------------------------------------------
# S14: All 8 expected skill folders exist
# (Check this first — everything else depends on it)
# ------------------------------------------------------------------
log "--- S14: All 8 expected skill folders exist ---"
all_folders_exist=true
for skill in "${EXPECTED_SKILLS[@]}"; do
  if [[ -d "$SKILLS_DIR/$skill" ]]; then
    log "  Found: $skill"
  else
    log "  MISSING: $skill"
    all_folders_exist=false
  fi
done
if $all_folders_exist; then
  pass 14 "All 8 expected skill folders exist"
else
  fail 14 "One or more expected skill folders are missing"
fi
log ""

# ------------------------------------------------------------------
# Per-skill assertions (S1–S13)
# ------------------------------------------------------------------
for skill in "${EXPECTED_SKILLS[@]}"; do
  SKILL_DIR="$SKILLS_DIR/$skill"
  SKILL_FILE="$SKILL_DIR/SKILL.md"

  log "------------------------------------------------------------"
  log "Skill: $skill"
  log "------------------------------------------------------------"

  # S1: Folder uses kebab-case (lowercase letters, digits, hyphens only)
  if echo "$skill" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    pass 1 "[$skill] Folder name is kebab-case"
  else
    fail 1 "[$skill] Folder name is NOT kebab-case: '$skill'"
  fi

  # S2: Folder contains exactly one file named SKILL.md (case-sensitive)
  # Use ls to get actual filenames (works correctly on case-insensitive macOS HFS+)
  ACTUAL_MD_FILES=$(ls "$SKILL_DIR/" | grep -iE '^skill.*\.md$' || true)
  EXACT_MATCH=$(ls "$SKILL_DIR/" | grep -xF "SKILL.md" || true)
  BAD_VARIANTS=$(ls "$SKILL_DIR/" | grep -iE '^skill.*\.md$' | grep -vxF "SKILL.md" || true)

  if [[ -n "$EXACT_MATCH" ]]; then
    if [[ -z "$BAD_VARIANTS" ]]; then
      pass 2 "[$skill] Contains exactly SKILL.md (correct casing)"
    else
      fail 2 "[$skill] Contains incorrect variants alongside SKILL.md: $BAD_VARIANTS"
    fi
  else
    if [[ -n "$ACTUAL_MD_FILES" ]]; then
      fail 2 "[$skill] Has .md files but NOT named SKILL.md (found: $ACTUAL_MD_FILES)"
    else
      fail 2 "[$skill] Missing SKILL.md"
    fi
    log ""
    continue
  fi

  # S3: No README.md inside the skill folder
  if [[ ! -f "$SKILL_DIR/README.md" ]]; then
    pass 3 "[$skill] No README.md inside skill folder"
  else
    fail 3 "[$skill] Contains a README.md (not allowed per Skills spec)"
  fi

  # Extract frontmatter (between first two --- delimiters)
  FRONTMATTER=$(awk '/^---$/{if(++n==2) exit} n==1' "$SKILL_FILE")

  # S4: YAML frontmatter has 'name' field
  if echo "$FRONTMATTER" | grep -qE '^name:' 2>/dev/null; then
    pass 4 "[$skill] Frontmatter has 'name' field"
  else
    fail 4 "[$skill] Frontmatter missing 'name' field"
  fi

  # S5: YAML frontmatter has 'description' field
  if echo "$FRONTMATTER" | grep -qE '^description:' 2>/dev/null; then
    pass 5 "[$skill] Frontmatter has 'description' field"
  else
    fail 5 "[$skill] Frontmatter missing 'description' field"
  fi

  # S6: 'name' value matches folder name exactly
  NAME_VALUE=$(echo "$FRONTMATTER" | grep -E '^name:' | sed 's/^name:[[:space:]]*//' | tr -d '"'"'" | xargs || true)
  if [[ "$NAME_VALUE" == "$skill" ]]; then
    pass 6 "[$skill] name field ('$NAME_VALUE') matches folder name"
  else
    fail 6 "[$skill] name field ('$NAME_VALUE') does NOT match folder name ('$skill')"
  fi

  # S7: description is under 1024 characters
  DESC_LINE=$(echo "$FRONTMATTER" | grep -E '^description:' | sed 's/^description:[[:space:]]*//' || true)
  DESC_LEN=${#DESC_LINE}
  if [[ $DESC_LEN -lt 1024 ]]; then
    pass 7 "[$skill] Description length ($DESC_LEN chars) is under 1024"
  else
    fail 7 "[$skill] Description length ($DESC_LEN chars) EXCEEDS 1024 characters"
  fi

  # S8: description has NO XML angle brackets
  if echo "$DESC_LINE" | grep -qE '[<>]' 2>/dev/null; then
    fail 8 "[$skill] Description contains XML angle brackets (< or >)"
  else
    pass 8 "[$skill] Description has no XML angle brackets"
  fi

  # S9: description contains "Use when" trigger pattern
  if echo "$DESC_LINE" | grep -qi "Use when" 2>/dev/null; then
    pass 9 "[$skill] Description contains 'Use when' trigger pattern"
  else
    fail 9 "[$skill] Description is missing 'Use when' trigger condition"
  fi

  # S10: name does NOT start with 'claude' or 'anthropic'
  if echo "$NAME_VALUE" | grep -qiE '^(claude|anthropic)' 2>/dev/null; then
    fail 10 "[$skill] name starts with reserved prefix 'claude' or 'anthropic'"
  else
    pass 10 "[$skill] name does not use reserved prefix"
  fi

  # S11: SKILL.md body is under 5,000 words
  BODY=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$SKILL_FILE")
  WORD_COUNT=$(echo "$BODY" | wc -w | xargs)
  if [[ $WORD_COUNT -lt 5000 ]]; then
    pass 11 "[$skill] Body word count ($WORD_COUNT) is under 5,000"
  else
    fail 11 "[$skill] Body word count ($WORD_COUNT) EXCEEDS 5,000 words"
  fi

  # S12: Required sections present
  required_sections=("## Overview" "## Prerequisites" "## Workflow" "## Error Handling" "## Examples")
  all_sections=true
  for section in "${required_sections[@]}"; do
    if ! grep -qF "$section" "$SKILL_FILE" 2>/dev/null; then
      fail 12 "[$skill] Missing required section: '$section'"
      all_sections=false
    fi
  done
  if $all_sections; then
    pass 12 "[$skill] All required sections present (Overview, Prerequisites, Workflow, Error Handling, Examples)"
  fi

  # S13: metadata.mcp-server field is present
  if echo "$FRONTMATTER" | grep -qE 'mcp-server:' 2>/dev/null; then
    pass 13 "[$skill] metadata.mcp-server field present"
  else
    fail 13 "[$skill] metadata.mcp-server field MISSING"
  fi

  log ""
done

# ------------------------------------------------------------------
# Final summary
# ------------------------------------------------------------------
log "============================================================"
log "GATE 1 RESULTS"
log "============================================================"
log "Total assertions: $TOTAL"
log "Passed:           $PASS"
log "Failed:           $FAIL"
log ""

if [[ $FAIL -eq 0 ]]; then
  log "🟢 GATE 1: PASS — $PASS/$TOTAL structural assertions passed"
  log "============================================================"
  echo ""
  echo "🟢 GATE 1 PASS: $PASS/$TOTAL"
  exit 0
else
  log "🔴 GATE 1: FAIL — $FAIL/$TOTAL assertions FAILED"
  log "Fix the above failures before proceeding to Gate 2."
  log "============================================================"
  echo ""
  echo "🔴 GATE 1 FAIL: $FAIL failures out of $TOTAL assertions"
  exit 1
fi
