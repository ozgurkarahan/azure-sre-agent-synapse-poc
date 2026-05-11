## What this PR changes
<!-- Brief summary -->

## Sanitization checklist (REQUIRED before merge)
- [ ] No real subscription / tenant / principal IDs added
- [ ] No real customer / person / company names added
- [ ] No connection strings / SAS tokens / API keys added
- [ ] No real email addresses (only `*@invalid.invalid` placeholders or `<placeholder>` syntax)
- [ ] No `~/projects/memory/` paths or `[[wiki-backlinks]]` (those are private wiki conventions)

## Tested
- [ ] Bicep what-if (if infra changed): `az deployment sub what-if ...`
- [ ] Documentation updates render correctly (preview the markdown)
