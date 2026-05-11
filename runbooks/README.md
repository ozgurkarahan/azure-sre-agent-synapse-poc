# `runbooks/` — `synapse_expert` SRE Agent subagent + KQL runbooks

Per Phase 4 of `../PLAN.md`. This folder contains:

| File | Purpose |
|---|---|
| `synapse_expert.yaml` | Subagent definition for Azure SRE Agent Builder / Agent Canvas. Authored offline; uploaded by user once SRE Agent is provisioned (Phase 3). |
| `synapse-pipeline-failures.kql.md` | Pain Point #1 + #4 — find failed and silently-anomalous Synapse pipelines, with RCA hints |
| `synapse-spark-runaway.kql.md` | Pain Point #2 — Spark applications that didn't auto-stop |
| `synapse-alert-delivery.kql.md` | Pain Point #3 — Action Group delivery failures (the SMTP "OK ≠ delivered" insight) |
| `synapse-silent-skip-detection.kql.md` | Pain Point #1 (sharper) — schema drift + row-count anomalies on copy activities |

## How to use

1. After Phase 3 (SRE Agent provisioned), open the SRE Agent in the Azure Portal → Builder / Agent Canvas.
2. Create a new subagent named `synapse_expert`.
3. Paste the system prompt + tools list from `synapse_expert.yaml` into the canvas.
4. For each `.kql.md` file, attach as a knowledge-base entry (or copy into the subagent's "Custom runbooks" section depending on canvas version).
5. Test by prompting the SRE Agent with `/agent synapse_expert {your question}` (or the equivalent invocation in your canvas version).

## Why this exists

Vanilla SRE Agent CAN answer the same questions, but tends to:
- Generate generic KQL that misses Synapse-specific tables (e.g., uses `AzureDiagnostics` instead of `SynapseIntegrationPipelineRuns`)
- Skip the "why" interpretation — just shows query results
- Miss the cross-table joins (e.g., correlating a pipeline failure with its Spark application's failure stack)

The runbook KQL queries are pre-validated and the markdown adds the "what does this mean" interpretation. Result: Sharper, faster, more confident answers grounded in evidence.

## Validation against the canvas

The Agent Canvas YAML schema may differ slightly from what's authored here. After uploading, verify:
- Tools `execute_kusto_query`, `azure_cli`, `azure_resource_graph` are available (names may differ in your canvas version)
- Knowledge base accepts `.md` files (alternatives: paste content into rich-text fields)
- System prompt size limit is not exceeded (typically 8K-16K chars; current ~3K)
