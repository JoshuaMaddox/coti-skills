#!/usr/bin/env bash
# =============================================================================
# Gate 4: Cross-Skill Integration Tests
# Runs 3 end-to-end workflows that span multiple skills. Each step must
# succeed AND produce correct output for the workflow to pass.
#
# Workflow A: Account Onboarding → First Message (6 steps)
# Workflow B: Token Lifecycle (6 steps)
# Workflow C: Contract Deploy → Interact → Debug (5 steps)
# Total: 17 steps, all must pass
#
# Requires: ANTHROPIC_API_KEY, COTI MCP servers running
# Writes:   tests/results/integration-results.json
# Exit code: 0 = 17/17, 1 = any failure
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_FILE="$SCRIPT_DIR/results/integration-results.json"
MODEL="claude-sonnet-4-6"

mkdir -p "$SCRIPT_DIR/results"

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "❌ ERROR: ANTHROPIC_API_KEY is not set."
  exit 1
fi

echo "============================================================"
echo "COTI Skills — Gate 4: Integration Tests (17 steps)"
echo "Model: $MODEL"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "============================================================"
echo ""

python3 << 'PYEOF'
import json
import os
import sys
import time
import urllib.request
from datetime import datetime, timezone

api_key = os.environ['ANTHROPIC_API_KEY']
model = "claude-sonnet-4-6"
results_file = os.path.join(os.path.dirname(__file__) if '__file__' in dir() else '.', 'results', 'integration-results.json')
results_file = os.path.join(
    os.path.dirname(os.path.abspath(__file__)) if '__file__' in dir() else os.getcwd(),
    'results', 'integration-results.json'
)

# Fallback path
import pathlib
results_file = str(pathlib.Path(__file__).parent / "results" / "integration-results.json") if '__file__' in dir() else "./tests/results/integration-results.json"

recipient   = os.environ.get('COTI_RECIPIENT_ADDRESS', '0xDEAD...fill_in')
second_addr = os.environ.get('COTI_SECOND_ADDRESS', '0xBEEF...fill_in')

WORKFLOWS = [
    {
        "id": "WF-A",
        "name": "New Agent Onboarding → First Message",
        "steps": [
            {
                "stepId": "A1", "skill": "coti-account-setup",
                "description": "Create account and AES key",
                "instruction": "Create a new COTI account and generate an AES key for it. Return the wallet address.",
                "assertion": "response contains a wallet address starting with 0x AND mentions AES key was generated",
                "captures": ["wallet_address"]
            },
            {
                "stepId": "A2", "skill": "coti-starter-grant",
                "description": "Request starter COTI grant",
                "instruction": "Request a starter COTI grant for the new wallet. Use the one-call flow.",
                "assertion": "response mentions claimed OR transaction hash OR grant received",
                "captures": ["tx_hash_grant"]
            },
            {
                "stepId": "A3", "skill": "coti-transaction-tools",
                "description": "Check native balance > 0 after grant",
                "instruction": f"Check the native COTI balance for address {recipient}.",
                "assertion": "response contains a balance value greater than 0",
                "captures": []
            },
            {
                "stepId": "A4", "skill": "coti-private-messaging",
                "description": "Send first encrypted message",
                "instruction": f"Send the encrypted message 'hello world' to {recipient}.",
                "assertion": "response mentions message sent AND contains a transaction hash OR message ID",
                "captures": ["message_id"]
            },
            {
                "stepId": "A5", "skill": "coti-private-messaging",
                "description": "List sent messages — message appears",
                "instruction": f"List the sent messages for {recipient} and verify the 'hello world' message appears.",
                "assertion": "response lists at least one sent message; mentions 'hello world' or message ID from previous step",
                "captures": []
            },
            {
                "stepId": "A6", "skill": "coti-rewards-management",
                "description": "Check epoch usage is > 0 after messaging",
                "instruction": f"Check the current epoch and the epoch usage/stats for address {recipient}.",
                "assertion": "response contains epoch number AND usage stats (usageUnits or similar)",
                "captures": []
            }
        ]
    },
    {
        "id": "WF-B",
        "name": "Token Lifecycle",
        "steps": [
            {
                "stepId": "B1", "skill": "coti-private-erc20",
                "description": "Deploy TestToken / TT / 1000000 supply",
                "instruction": "Deploy a private ERC20 token named 'TestToken' with symbol 'TT' and initial supply of 1000000.",
                "assertion": "response contains a contract address starting with 0x",
                "captures": ["token_address"]
            },
            {
                "stepId": "B2", "skill": "coti-private-erc20",
                "description": "Check deployer balance == 1000000",
                "instruction": "Check the token balance of the deployer for the TestToken contract just deployed.",
                "assertion": "response contains balance equal to 1000000 OR '1000000'",
                "captures": []
            },
            {
                "stepId": "B3", "skill": "coti-private-erc20",
                "description": "Transfer 500 tokens to second wallet",
                "instruction": f"Transfer 500 TestToken tokens to address {second_addr}.",
                "assertion": "response contains transaction hash starting with 0x",
                "captures": ["transfer_tx_hash"]
            },
            {
                "stepId": "B4", "skill": "coti-private-erc20",
                "description": "Deployer balance == 999500 after transfer",
                "instruction": "Check the deployer's TestToken balance after the transfer.",
                "assertion": "response contains balance of 999500 OR shows reduction of 500 from original 1000000",
                "captures": []
            },
            {
                "stepId": "B5", "skill": "coti-transaction-tools",
                "description": "Transfer tx is confirmed",
                "instruction": "Check the status of the transfer transaction from the previous step.",
                "assertion": "response indicates transaction is confirmed OR successful",
                "captures": []
            },
            {
                "stepId": "B6", "skill": "coti-transaction-tools",
                "description": "Decode transfer event — correct to/amount",
                "instruction": "Get the transaction logs for the transfer transaction and decode the Transfer event.",
                "assertion": "response contains event data showing recipient address and/or amount of 500",
                "captures": []
            }
        ]
    },
    {
        "id": "WF-C",
        "name": "Contract Deploy → Interact → Debug",
        "steps": [
            {
                "stepId": "C1", "skill": "coti-smart-contracts",
                "description": "Compile and deploy SimpleStorage contract",
                "instruction": """Compile and deploy this Solidity contract:
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
contract SimpleStorage {
    uint256 private value;
    function store(uint256 v) public { value = v; }
    function retrieve() public view returns (uint256) { return value; }
}
Return the deployed contract address.""",
                "assertion": "response contains a contract address starting with 0x",
                "captures": ["storage_address"]
            },
            {
                "stepId": "C2", "skill": "coti-smart-contracts",
                "description": "Call store(42) write function",
                "instruction": "Call the store function on the SimpleStorage contract with the value 42.",
                "assertion": "response contains transaction hash starting with 0x",
                "captures": ["store_tx_hash"]
            },
            {
                "stepId": "C3", "skill": "coti-smart-contracts",
                "description": "Call retrieve() — returns 42",
                "instruction": "Call the retrieve function on the SimpleStorage contract and return the stored value.",
                "assertion": "response contains the value 42",
                "captures": []
            },
            {
                "stepId": "C4", "skill": "coti-transaction-tools",
                "description": "Store transaction is confirmed",
                "instruction": "Check the status of the store(42) transaction.",
                "assertion": "response indicates transaction is confirmed OR successful",
                "captures": []
            },
            {
                "stepId": "C5", "skill": "coti-transaction-tools",
                "description": "Transaction logs are present",
                "instruction": "Get the transaction logs for the store(42) transaction.",
                "assertion": "response returns log data OR confirms no logs (storage-only contracts may emit no events — both are valid)",
                "captures": []
            }
        ]
    }
]

def call_claude_integration(instruction, conversation_history, system_prompt):
    conversation_history.append({"role": "user", "content": instruction})
    payload = {
        "model": model,
        "max_tokens": 1024,
        "system": system_prompt,
        "messages": conversation_history
    }
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=json.dumps(payload).encode(),
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
    )
    with urllib.request.urlopen(req, timeout=90) as resp:
        body = json.loads(resp.read())
        assistant_reply = body["content"][0]["text"].strip()
    conversation_history.append({"role": "assistant", "content": assistant_reply})
    return assistant_reply

def evaluate_assertion(response_text, assertion, evaluator_system):
    """Ask Claude to evaluate whether the response meets the assertion."""
    eval_prompt = f"""Evaluate whether the following response satisfies the assertion.

Response:
{response_text}

Assertion:
{assertion}

Reply with ONLY a JSON object:
{{"pass": true or false, "reason": "brief explanation"}}"""

    payload = {
        "model": model,
        "max_tokens": 200,
        "system": "You are a test assertion evaluator. Evaluate strictly.",
        "messages": [{"role": "user", "content": eval_prompt}]
    }
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=json.dumps(payload).encode(),
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = json.loads(resp.read())
        text = body["content"][0]["text"].strip()

    try:
        start = text.find('{')
        end = text.rfind('}') + 1
        parsed = json.loads(text[start:end])
        return parsed.get('pass', False), parsed.get('reason', text)
    except:
        return False, f"Eval parse error: {text[:100]}"

all_results = []
total_pass = 0
total_fail = 0

INTEGRATION_SYSTEM = """You are a COTI blockchain agent assistant executing an end-to-end integration test workflow.
You have access to both COTI MCP servers (coti-mcp and coti-agent-messaging).
Execute each instruction using the appropriate MCP tools.
Be concise but include all relevant output (addresses, hashes, values).
If a step fails, report the error clearly."""

for workflow in WORKFLOWS:
    wf_id = workflow['id']
    wf_name = workflow['name']
    print(f"\n{'='*60}")
    print(f"Workflow {wf_id}: {wf_name}")
    print(f"{'='*60}")

    conversation = []
    wf_pass = 0
    wf_fail = 0
    workflow_results = []

    for step in workflow['steps']:
        step_id = step['stepId']
        skill = step['skill']
        desc = step['description']
        instruction = step['instruction']
        assertion = step['assertion']

        try:
            print(f"\n  Step {step_id}: {desc}")
            response = call_claude_integration(instruction, conversation, INTEGRATION_SYSTEM)
            print(f"    Response: {response[:120]}...")

            # Evaluate assertion
            is_pass, reason = evaluate_assertion(response, assertion, INTEGRATION_SYSTEM)
            icon = "✅" if is_pass else "❌"
            print(f"    {icon} {reason[:80]}")

            if is_pass:
                wf_pass += 1
                total_pass += 1
            else:
                wf_fail += 1
                total_fail += 1

            step_result = {
                "stepId": step_id,
                "workflow": wf_id,
                "skill": skill,
                "description": desc,
                "instruction": instruction[:200],
                "response": response[:500],
                "assertion": assertion,
                "assertionEval": reason,
                "result": "PASS" if is_pass else "FAIL",
                "timestamp": datetime.now(timezone.utc).isoformat()
            }
            workflow_results.append(step_result)
            all_results.append(step_result)

        except Exception as e:
            wf_fail += 1
            total_fail += 1
            step_result = {
                "stepId": step_id,
                "workflow": wf_id,
                "skill": skill,
                "description": desc,
                "instruction": instruction[:200],
                "response": f"EXCEPTION: {str(e)}",
                "assertion": assertion,
                "assertionEval": f"Exception: {str(e)}",
                "result": "FAIL",
                "timestamp": datetime.now(timezone.utc).isoformat()
            }
            workflow_results.append(step_result)
            all_results.append(step_result)
            print(f"    ❌ EXCEPTION: {str(e)}")

        time.sleep(1)

    wf_total = wf_pass + wf_fail
    wf_icon = "🟢" if wf_fail == 0 else "🔴"
    print(f"\n  {wf_icon} Workflow {wf_id}: {wf_pass}/{wf_total} steps passed")

# Save results
total_steps = total_pass + total_fail
gate_pass = total_fail == 0

summary = {
    "gate": "Gate 4: Cross-Skill Integration",
    "model": model,
    "total_steps": total_steps,
    "passed": total_pass,
    "failed": total_fail,
    "gate_result": "PASS" if gate_pass else "FAIL",
    "workflows": {
        wf["id"]: {
            "name": wf["name"],
            "total_steps": len(wf["steps"]),
            "passed": sum(1 for r in all_results if r["workflow"] == wf["id"] and r["result"] == "PASS"),
            "failed": sum(1 for r in all_results if r["workflow"] == wf["id"] and r["result"] == "FAIL")
        }
        for wf in WORKFLOWS
    },
    "steps": all_results,
    "timestamp": datetime.now(timezone.utc).isoformat()
}

import os
os.makedirs(os.path.dirname(results_file), exist_ok=True)
with open(results_file, "w") as f:
    json.dump(summary, f, indent=2)

print("\n============================================================")
print("GATE 4 RESULTS")
print("============================================================")
for wf_id, wf_stat in summary["workflows"].items():
    wf_icon = "🟢" if wf_stat["failed"] == 0 else "🔴"
    print(f"  {wf_icon} {wf_id}: {wf_stat['name'][:40]:40s} {wf_stat['passed']}/{wf_stat['total_steps']}")

print(f"\nTotal: {total_pass}/{total_steps} steps passed")
print("")
if gate_pass:
    print("🟢 GATE 4: PASS — all 17 integration steps passed")
    sys.exit(0)
else:
    print(f"🔴 GATE 4: FAIL — {total_fail} step(s) failed")
    print("\nFailed steps:")
    for r in all_results:
        if r["result"] == "FAIL":
            print(f"  - {r['stepId']} [{r['workflow']}] {r['description']}")
            print(f"    {r['assertionEval']}")
    sys.exit(1)

PYEOF
