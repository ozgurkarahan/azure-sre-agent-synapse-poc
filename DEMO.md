# DEMO.md — Live walkthrough guide

**Audience:** Anyone evaluating Azure SRE Agent against Synapse pain points (your team, a customer, an exec)
**Setup state:** Assumes the pilot has been deployed end-to-end (Phases 1-3.5 complete) and the four pain-point scenarios have been run at least once recently.

---

## ⚡ Quick links you'll need open

| What | URL / path |
|---|---|
| **SRE Agent management portal** | https://sre.azure.com → select your agent (e.g., `sre-<prefix>-pilot`) |
| **Azure Portal — RG** | `portal.azure.com` → `<your-rg>` |
| **Synapse Studio** | (ask the agent: "give me the Synapse Studio URL") |
| **Teams channel** (where SRE Agent posts) | the channel you wired in Phase 3.5 |
| **This file** | open in your editor on a 2nd monitor |

---

## 🎯 What you're proving

Azure SRE Agent can address the four most common Synapse observability pain points:

| # | Pain point | Demo evidence |
|---|---|---|
| 1 | Pipelines silently fail / skip data | Schema drift on `pipeline-B-schema-drift` (`loyalty_tier` dropped) — agent downloads actual files when telemetry is empty |
| 2 | Spark clusters never auto-stop | Pipeline C runaway detected, recommended cancel + auto-pause review |
| 3 | **Alerts never delivered despite "OK"** | `bad@invalid.invalid` + revoked Logic App webhook — agent identifies `.invalid` as RFC 2606 reserved TLD |
| 4 | RCA hard without deep log access | Multi-source investigation across LAW + Synapse API + App Insights + Storage |
| **Bonus** | "Proactive vs reactive" | **Teams notification arrives autonomously when alert fires** (Phase 3.5 wiring) |

---

## ⏱️ Three demo lengths — pick by audience time

### 🚀 5-min EXPRESS demo (just the killshot — for skeptical execs)

1. Open `sre.azure.com` → your agent
2. Show the killshot: paste this prompt
   ```
   The Service Health dashboard shows the action group ag-<prefix>-<suffix> as
   healthy and our metric alert 'alert-pipeline-runs-ended' is enabled. But
   nobody on the team has received any alert emails or notifications. Did this
   action group actually deliver any notifications in the last 24 hours? If
   delivery failed, why?
   ```
3. **Wait ~30s.** Read the response aloud.
4. Highlight this line word-for-word (the agent says it almost verbatim if KQL runbooks are attached):
   > *"Service Health reports on Azure platform availability, not on whether your action group successfully delivers notifications. An action group with bogus receivers is still a valid Azure resource in a Succeeded provisioning state — it just silently fails at delivery time."*
5. Switch to Teams → show the autonomous Teams notification you received earlier (from Phase 3.5).
6. Punchline: *"That's 30 minutes of triage saved per incident. The on-call engineer wakes up to context, not a cryptic alert."*

### 🎭 15-min FULL demo (all 4 pain points + proactive loop)

| Min | Action | What you say |
|---|---|---|
| 0-1 | Set context | "Synapse customers tell us about 4 recurring observability gaps. We built a sandbox that reproduces all 4. Now I'll show how Azure SRE Agent handles each." |
| 1-3 | **Prompt #3 (alert delivery)** — same as Express demo step 2-4 | *"Pain point #3 — the killshot. Service Health shows 'OK' but nothing was actually delivered."* |
| 3-5 | **Prompt #4 (schema drift)** — paste:<br>`The pipeline 'pipeline-B-schema-drift' succeeded yesterday around 01:16 UTC, but downstream consumers report their loyalty tier dashboard is missing data. Why did the pipeline succeed if data is wrong?` | *"Pain point #1 — silent skips. Watch what happens when the agent finds NO telemetry for the schema mismatch..."* (it downloads the actual files to verify) |
| 5-7 | Show Teams autonomous notification | *"This wasn't us asking — the agent saw the alert fire on its own scan, investigated, posted to Teams. That's the proactive value."* |
| 7-10 | **Prompt #1 (failed pipelines)** — paste:<br>`What Synapse pipelines failed in the last 24 hours in resource group <your-rg>?` | *"Pain point #4 — RCA is hard without deep logs. The agent gets you to root cause in seconds."* |
| 10-12 | **Prompt #2 (Spark runaway)** — paste:<br>`Show me Spark pool applications that have been running for more than 6 hours on pool pooldefault.` | *"Pain point #2 — runaway clusters. Note: the agent says 'no, your auto-pause is working' instead of hallucinating a problem."* |
| 12-15 | Wrap + Q&A | Three closing points: (1) Reader-mode safety (Azure SRE Agent didn't change anything), (2) Cost ~€8 of agent time across this whole demo, (3) ready to pilot at your scale |

### 🔬 30-min DEEP dive (full storytelling for technical audiences)

Add to the 15-min above:

- **Prompt #5 (open anomaly hunt)** — paste:
  ```
  Looking at all our Synapse pipelines in resource group <your-rg>
  over the last 24 hours, can you detect any silent data anomalies?
  ```
  *"Now an open question. The agent will hunt — and in the reference run it found two bonus bugs we didn't even design (Pipeline A no output + customer_id type drift)."*
- **Prompt #7 (RBAC self-diagnosis)** — paste:
  ```
  Cancel pipeline run <pipeline-run-id>
  ```
  → agent attempts → blocked by Reader mode → diagnoses missing role → user grants → agent retries → correctly attributes outcome to user, no hallucination of credit.
  *"This is the trust pattern. The agent is honest about what it can and cannot do. Operators will trust this — and that's what makes the difference between a pilot and a production deployment."*

---

## 🛟 Fallbacks if something fails live

| Symptom | Fallback |
|---|---|
| Agent gives slow / weak answer | Open `demos/transcripts/phase3-smoke-prompts.md` — show the captured 15/15 answer from the reference run |
| Teams notification not arriving | Show the screenshot you captured during Phase 3.5 verification + show `Builder → Incidents` to demonstrate the agent saw the alert |
| Login error AADSTS50011 | Use **`https://sre.azure.com`** NOT `portal.azuresre.ai` (a common gotcha — the latter is the agent runtime hostname pattern, not the management portal) |
| Pipeline data > 24h old (KQL filters miss it) | Re-trigger pipeline B: `az synapse pipeline create-run --workspace-name <your-synapse-workspace> --name pipeline-B-schema-drift` (takes ~3 min for fresh data) |
| Internet/VPN flaky | The transcripts in `demos/transcripts/phase3-smoke-prompts.md` and the readout summary in `docs/customer-readout-summary.md` are the offline backup |

---

## 📊 What to highlight verbally

These are the three soundbites that sell the pilot:

1. **The killshot (pain point #3):** *"Service Health reports rule health, not delivery success."*
2. **The proactive value:** *"Your on-call engineer wakes up to a 200-word RCA, not a cryptic alert."*
3. **The trust pattern:** *"The agent self-diagnoses what it can't do. It tells you what permission it needs. It doesn't claim credit for actions it didn't perform."*

---

## 🧹 After the demo — cleanup options

| Action | Command | Why |
|---|---|---|
| **Pause Spark pool only** (€0.50/day) | `az synapse spark pool update --workspace-name <your-synapse-workspace> -g <your-rg> --name pooldefault --enable-auto-pause true --delay 5` | Keep infra for next demo; just stop the pricey component |
| **Full teardown** (€0/day) | `az group delete --name <your-rg> --yes --no-wait` | If you don't expect to demo again soon. Can redeploy in <10 min from `infra/main.bicep`. |
| **Stop SRE Agent only** | Portal → agent → Stop | Halts AAU consumption while keeping Synapse running |

---

## 🗃️ All artifacts you might need

| File | Purpose |
|---|---|
| `demos/transcripts/phase3-smoke-prompts.md` | Verbatim agent responses to the 5 smoke prompts with scores (sanitized reference run) |
| `docs/customer-readout-summary.md` | 1-page summary memo (the deck content compressed) |
| `runbooks/synapse_expert.yaml` + 4 `.kql.md` | KQL runbook library attached as agent knowledge |
| `infra/main.bicep` | Reproducible deployment for another sandbox |
| `infra/README.md` | Deploy / teardown commands |

---

## ✅ Pre-demo checklist (run 5 min before)

- [ ] `https://sre.azure.com` loads, signed in with the right account
- [ ] Your agent (e.g., `sre-<prefix>-pilot`) shows status "Running" in the portal
- [ ] Quick test: ask the agent "What time is it?" — confirm it responds
- [ ] Teams channel where you wired the connector is open in another tab
- [ ] This DEMO.md is open on a 2nd monitor / phone for reference
- [ ] (Optional) Re-trigger Pipeline B for fresh data: `az synapse pipeline create-run --workspace-name <your-synapse-workspace> --name pipeline-B-schema-drift`

---

## 🎤 Opening line suggestions

Pick one based on audience:

- **For your account team / collaborators:** *"Quick demo — I want to show you what we have before we take it to a customer. 5 minutes for the killshot, longer if you want to play."*
- **For someone skeptical of AI agents:** *"This is Azure SRE Agent in Reader mode — it can't change anything. I want to show you it answers Synapse questions correctly, then you tell me if it's better than what your KQL expert gives in the same time."*
- **For someone who wants the pitch:** *"Synapse customers tell us their pipelines fail silently, their alerts don't deliver, and their RCA is opaque. Here's a real-world reproduction with each pain point, and how SRE Agent handles them."*
