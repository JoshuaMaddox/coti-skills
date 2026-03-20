# COTI Skills — Automated Setup Prompt for Claude Code

Copy everything below this line and paste it into Claude Code, or run:
```
claude < setup/setup-prompt.md
```

---

You are helping me set up the COTI Skills library for Claude Code from scratch. I want you to run every step automatically using your tools. Do not just give me instructions — actually execute each step. Ask me only when you genuinely need a piece of information you cannot figure out yourself (like my desired install folder). Otherwise, make sensible choices and keep going.

Work through these steps in order. After each step, tell me what you did and whether it succeeded. If something fails, tell me exactly what the error was and how you fixed it before moving on.

---

## Step 1 — Check that Node.js is installed

Run `node --version` in the shell.

- If it returns a version number (e.g. `v20.x.x`), tell me the version and move on.
- If the command is not found, stop here and tell me to install Node.js from https://nodejs.org (click the LTS button), then restart this session after installing.

---

## Step 2 — Check that Git is installed

Run `git --version` in the shell.

- If it returns a version number, move on.
- If not found, stop and tell me to install Git from https://git-scm.com/downloads, then restart this session.

---

## Step 3 — Choose an install folder

I want both MCP servers and the skills repo cloned into the same parent folder.

Ask me: "Where would you like to install the COTI servers? (Press Enter to use your home folder, or type a path)"

If I press Enter or say nothing, use `~/coti` as the folder. Create it if it doesn't exist.

Remember this folder for the rest of the setup. Call it INSTALL_DIR.

---

## Step 4 — Clone and build coti-agent-messaging

Run these commands inside INSTALL_DIR:

```bash
git clone https://github.com/coti-io/coti-agent-messaging.git
cd coti-agent-messaging
npm install
npm run build
```

If the folder already exists (because they ran this before), do `git pull` inside it instead of cloning again, then re-run `npm install` and `npm run build`.

Tell me when it's done, or show the error if it fails.

---

## Step 5 — Create the .env file for coti-agent-messaging

Check if INSTALL_DIR/coti-agent-messaging/.env already exists.

- If it does NOT exist, create it with this exact content:

```
PRIVATE_KEY=PLACEHOLDER_FILL_IN_STEP_9
AES_KEY=PLACEHOLDER_FILL_IN_STEP_9
CONTRACT_ADDRESS=0xc94189E22144500a66669E5bA1B42387DCc5Cd6a
COTI_NETWORK=testnet
```

- If it already exists, read it and show me the current values (replace the actual PRIVATE_KEY and AES_KEY values with `[hidden]` for security). Ask me if I want to keep it or reset it.

Tell me where the file is located.

---

## Step 6 — Clone and build coti-mcp

Run these commands inside INSTALL_DIR:

```bash
git clone https://github.com/coti-io/coti-mcp.git
cd coti-mcp
npm install
```

If the folder already exists, do `git pull` and re-run `npm install`.

---

## Step 7 — Create run-stdio.ts inside coti-mcp

Check if INSTALL_DIR/coti-mcp/run-stdio.ts already exists.

If it does NOT exist, create it with this exact content:

```typescript
#!/usr/bin/env node
/**
 * Thin wrapper: connects the Smithery-style coti-mcp server to stdio transport.
 * Usage: npx tsx run-stdio.ts
 */
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import createServer from "./index.js";

const server = createServer({ config: { debug: false } });
const transport = new StdioServerTransport();
await server.connect(transport);
```

If it already exists, tell me and skip this step.

---

## Step 8 — Register the MCP servers with Claude Code

Run these two commands to register the servers. Use the full absolute paths to the files (expand ~ to the actual home directory path):

```bash
claude mcp add coti-mcp -- npx tsx INSTALL_DIR/coti-mcp/run-stdio.ts
claude mcp add coti-agent-messaging -- node INSTALL_DIR/coti-agent-messaging/dist/mcp-server.js
```

After running them, run `claude mcp list` to confirm both servers appear.

If a server is already registered (you'll get an "already exists" error), skip it and tell me.

---

## Step 9 — Copy the skills into Claude Code's skills directory

Find or create ~/.claude/skills/.

Then copy all 8 skill folders from the coti-skills repository (the folder this setup-prompt.md lives in) into ~/.claude/skills/. The skill folders are named:
- coti-account-setup
- coti-starter-grant
- coti-private-messaging
- coti-rewards-management
- coti-private-erc20
- coti-private-nft
- coti-smart-contracts
- coti-transaction-tools

The source path is the parent directory of this file (setup/setup-prompt.md). Copy each skill folder so the result looks like:
```
~/.claude/skills/coti-account-setup/SKILL.md
~/.claude/skills/coti-starter-grant/SKILL.md
... etc
```

Tell me when all 8 are copied.

---

## Step 10 — Start the coti-agent-messaging server

Open a background process to start the messaging server:

```bash
cd INSTALL_DIR/coti-agent-messaging && npm run mcp:start
```

You don't need to wait for it — just launch it. Tell me the command I would use to start it manually in the future.

---

## Step 11 — Create my COTI wallet

Now use the coti-mcp MCP server to create a wallet. Call the `create_account` tool.

Show me the result. Tell me:
- My new wallet **address** (safe to share)
- My new **private key** (must be kept secret)

Immediately warn me to copy these values somewhere safe before continuing. Ask me to confirm I've saved them before proceeding.

---

## Step 12 — Generate my AES key

Call the `generate_aes_key` tool using the private key from Step 11.

Show me the **AES key**. Ask me to save it alongside my private key.

---

## Step 13 — Update the .env file with my real keys

Take the private key from Step 11 and the AES key from Step 12 and write them into INSTALL_DIR/coti-agent-messaging/.env, replacing the PLACEHOLDER values.

The file should look like:
```
PRIVATE_KEY=0x[the real key]
AES_KEY=[the real aes key]
CONTRACT_ADDRESS=0xc94189E22144500a66669E5bA1B42387DCc5Cd6a
COTI_NETWORK=testnet
```

Tell me the file has been updated.

---

## Step 14 — Claim the starter grant (get free COTI for gas)

Call the `request_starter_grant` tool to claim the one-time COTI starter grant for my new wallet.

If it succeeds, show me the transaction hash and amount received.

If it fails with "service not configured" or similar, tell me to get testnet COTI from the COTI Discord instead: https://discord.com/invite/Z4r8D6ez49 — and continue to Step 15 anyway.

---

## Step 15 — Check my balance

Call the `get_native_balance` tool with my wallet address.

- If the balance is above 0, tell me I'm all set and show the balance.
- If the balance is 0, remind me to get COTI from the Discord faucet before sending messages or deploying contracts.

---

## Step 16 — Final summary

Print a summary that includes:

1. The location of both installed servers (full paths)
2. My wallet address
3. The command to start coti-agent-messaging in the future
4. A reminder that my private key and AES key are in the .env file
5. Three things I can try right now:
   - "Send a private message to [my own address]"
   - "Deploy a private token called TestToken with symbol TEST"
   - "Check my COTI balance"
6. A note that all 8 skill folders are loaded in ~/.claude/skills/

---

That's the full setup. Go through every step now, starting with Step 1.
