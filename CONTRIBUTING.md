# Contributing

Thanks for your interest in this Azure SRE Agent + Synapse pilot template. PRs welcome — particularly for:

- **Additional KQL runbooks** for other Synapse failure modes (cold-start regression, IR availability, CMK rotation issues, etc.)
- **Ports of the scaffold** to Microsoft Fabric (Notebooks + Lakehouse) or Databricks (workflows + cluster monitoring)
- **Additional pain-point scenarios** beyond the four built in
- **Improvements to the Bicep** (better RBAC, private endpoints, CMK support)

## Before you submit a PR

1. **Open an issue first** for non-trivial changes. We want to make sure your direction matches the template's purpose before you invest time.
2. **Run the security checks** from the original audit script before opening the PR. In particular, verify your changes do not introduce:
   - Real subscription IDs, tenant IDs, principal IDs, or any GUID that resolves to a real Azure resource
   - Email addresses other than `bad@invalid.invalid` (use the RFC 2606 reserved `.invalid` TLD for examples)
   - Real SAS tokens, connection strings, or webhook URLs
   - Customer-identifying names, project codenames, or internal references

   ```powershell
   # Quick local check — should return zero matches
   git ls-files | ForEach-Object {
     Select-String -Path $_ -Pattern '@(microsoft|outlook)\.com|InstrumentationKey=|SharedAccessSignature|sig=[A-Za-z0-9%]{20,}' -ErrorAction SilentlyContinue
   }
   ```
3. **Test the Bicep with `--what-if`** before opening the PR if you changed `infra/`. Provide the what-if output in the PR description.
4. **Update the docs.** If your change adds a new runbook, update `runbooks/README.md`. If it changes the deploy steps, update `infra/README.md`. If it adds a new scenario, update `demos/README.md` and `PLAN.md`'s test-scenario table.

## Coding conventions

- **Bicep:** follow the existing module structure (one resource type per module under `infra/modules/`); descriptive parameter `@description()` annotations on every parameter.
- **PowerShell:** use `[CmdletBinding()]`, `param()` blocks with `[Parameter(Mandatory = $true)]` where appropriate, and `$ErrorActionPreference = 'Stop'`. Don't use `-ErrorAction SilentlyContinue` to mask failures.
- **KQL runbooks:** every runbook follows the same template — When to use → Primary KQL → Drill-down KQL → Patterns → Interpretation guidance → Cross-references → Template context.
- **Markdown:** use sentence case for headings, fenced code blocks with language tags, and tables instead of bullet lists for tabular data.

## Code of Conduct

Be kind, give credit, assume good intent. The maintainers may close PRs that don't follow this norm.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
