# Phase 3 — Scoring rubric

**Per:** `../../PLAN.md` Phase 3 correctness rubric.

For each smoke prompt response, score on three axes (1-5 each, 15 total). 12+ to pass per prompt; 13+ average for the subagent acceptance gate.

## Axis 1 — Specificity (1-5)

How concrete and traceable is the answer?

| Score | Criterion |
|---|---|
| 5 | Names actual run IDs, application IDs, resource IDs, timestamps. Reader can copy any value into the portal and find the exact resource. |
| 4 | Names most identifiers but uses some "the pipeline" or "this run" instead of a specific ID. |
| 3 | Mixed — some specifics, some generics. Reader has to infer which resource is meant. |
| 2 | Mostly generic descriptions ("a few pipelines failed") with one or two specifics. |
| 1 | Pure handwaving — "your environment has issues with X." No identifiers. |

## Axis 2 — Citation quality (1-5)

How well does the answer prove its claim with log evidence?

| Score | Criterion |
|---|---|
| 5 | Shows the KQL query in full, names the source table(s), and numbers in the answer trace back to specific log rows. The reviewer can re-run the KQL and reproduce the answer. |
| 4 | Names source tables and shows partial KQL or a description of the query approach. Numbers traceable but query not fully reproducible from the answer alone. |
| 3 | Names a source table or two but no KQL shown. Numbers presented as facts without clear trace. |
| 2 | "Based on the logs" type phrasing. Specific table/query not visible. |
| 1 | Numbers stated without any reference to where they came from. (Possibly hallucinated.) |

## Axis 3 — Recommendation usefulness (1-5)

Does the answer end with an actionable next step?

| Score | Criterion |
|---|---|
| 5 | One or more concrete next actions: a specific KQL to run, an Azure CLI command, a config change, a team to page. The reader knows exactly what to do next AND why. |
| 4 | A clear recommendation but missing one of: specifics, justification, or fallback if the recommendation doesn't work. |
| 3 | A vague recommendation ("investigate further", "check the logs") without specifics. |
| 2 | Acknowledges that an action might be needed but doesn't say what. |
| 1 | Just describes the problem with no recommendation at all. |

## Bonus tracking (no points, but worth noting)

| Field | Captures |
|---|---|
| **Time-to-answer** | Wall-clock seconds from prompt submission to first complete response. Note for trend analysis. |
| **Pain-point label** | Did the agent label its findings with `[Pain Point #N]` per the system prompt instruction? Yes/No. |
| **Hallucinations** | Did the agent invent any names, IDs, or behaviours not present in the actual logs? List them. |
| **Citation recursion** | When asked "show me the KQL that produced this", does the agent's KQL match what it claimed it ran? |

## Aggregate scoring template

Per prompt:

```
Prompt N — {topic}

Vanilla:
  Specificity:     X/5
  Citation:        X/5
  Recommendation:  X/5
  Total:           X/15
  Time:            Xs
  Pain-point label: Yes/No
  Hallucinations:  none / list
  Comments:        ...

Subagent (synapse_expert):
  Specificity:     X/5
  Citation:        X/5
  Recommendation:  X/5
  Total:           X/15
  Time:            Xs
  Pain-point label: Yes/No
  Hallucinations:  none / list
  Comments:        ...
```

## Acceptance gate decision tree

```
After all 5 prompts scored:

  Vanilla average ≥ 12/15  ──Yes──>  SRE Agent works on Synapse out-of-box. Phase 3 PASSES.
                            ──No───>  Diagnose: RBAC? Missing diag settings? KQL coverage gap?
                                      Document in wiki/projects/customer-customer-synapse-sre-pilot.md.
                                      Fix root cause; rerun Phase 3.

  Subagent average ≥ 13  AND
  Subagent strictly > Vanilla  ──Yes──>  Custom subagent worth the work. Phase 4 PASSES.
  on ≥ 3 of 5 prompts          ──No───>  Revise: KQL too generic? System prompt too short?
                                          KB files lack interpretation guidance?
                                          Iterate on synapse_expert.yaml + runbooks/, rerun Phase 4.
```
