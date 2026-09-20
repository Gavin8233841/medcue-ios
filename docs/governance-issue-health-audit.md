# Reproducible GitHub Issue Health Audit

`tools/audit-issue-health.py` produces a read-only governance snapshot for a
GitHub repository. It is a manual audit entry point, not a GitHub Action, bot,
or remote-state reconciliation tool.

The report is designed to answer whether current Issues have useful labels,
title prefixes, assignees, current-form fields, milestones, explicit blockers,
and links from recently merged pull requests. It does not modify any Issue,
pull request, label, assignee, milestone, comment, branch, or workflow.

## Windows prerequisites

- Python 3.10 or newer.
- GitHub CLI (`gh`) available on `PATH`.
- Existing `gh` authentication with read access to the target repository.

Confirm the local tools and authentication before running the audit:

```powershell
python --version
gh --version
gh auth status
```

The tool delegates authentication to `gh`. It does not read a token itself,
include a token in a command argument, or print raw `gh` stderr. An existing
`GH_TOKEN` or GitHub CLI credential may therefore be used according to normal
`gh` behavior without becoming report content.

## Run the audit

Write a complete report atomically to a temporary-directory file:

```powershell
$auditReport = Join-Path $env:TEMP "medcue-issue-health-audit.md"
python .\tools\audit-issue-health.py `
  --repo Gavin8233841/medcue-ios `
  --output $auditReport
if ($LASTEXITCODE -ne 0) { throw "Issue health audit failed" }
Get-Content -LiteralPath $auditReport
```

Use `--output -` (the default) to write the complete report to standard output:

```powershell
python .\tools\audit-issue-health.py --repo Gavin8233841/medcue-ios
```

At CLI startup the tool reconfigures standard output and standard error as
UTF-8. This avoids Windows legacy-console encodings corrupting Chinese label,
Form, and milestone names when output is displayed or piped.

Do not use shell redirection when preservation of an existing report matters.
Shells open a redirected destination before Python begins, so a failed network
request could leave that destination empty. `--output <path>` instead writes a
same-directory temporary file, flushes it, and calls `os.replace` only after
all collection, validation, analysis, and rendering succeeds.

The process returns zero only for a complete audit. Invalid repository input,
missing authentication, network or permission failures, malformed JSON,
missing API fields (distinct from API fields that legally contain `null`),
pagination duplicates, malformed Issue Forms, and output failures return
nonzero and do not replace an existing report.

## Data collected

All list endpoints request 100 records per page and use `gh api --paginate`.
The report records the number of pages received for each list.

The tool reads:

- repository metadata and the default branch;
- every open and closed Issue, excluding pull requests returned by the shared
  Issues endpoint;
- the repository-wide Issue-comments endpoint;
- every repository label and every open or closed milestone;
- every open pull request;
- every closed pull request, from which merged pull requests are selected using
  non-null `merged_at` values;
- every Issue Form YAML file in `.github/ISSUE_TEMPLATE` on the current default
  branch, excluding `config.yml`.

The REST Issue-comments endpoint also contains pull-request conversation
comments. The audit resolves each comment URL against the fully fetched Issue
and pull-request number sets, reports the separate counts, and fails if a target
cannot be reconciled. A `gh --jq` projection removes comment bodies before the
Python process receives each page.

Issue and pull-request bodies are needed for Form headings, explicit dependency
markers, and Issue-link semantics. They remain in memory only. The report never
emits an Issue title or body, pull-request title or body, comment body, assignee
login, local path, credential, or raw API error. It emits GitHub numbers,
counts, configured label/Form names, milestone names, and rule outcomes.

## Exact audit rules

### Labels

Any-label coverage is separate from classification coverage.

- Priority coverage recognizes only `P0`, `P1`, `P2`, and `P3`.
- Type coverage recognizes only `功能`, `缺陷`, `增强`, `问题`, `技术债务`,
  `治理`, and `文档`.
- Missing repository definitions from those configured sets are reported.

An Issue carrying some other label is counted under any-label coverage but is
still missing priority or type classification as applicable.

### Title prefixes

Every current Open Issue is placed into exactly one class, in this order:

1. full-width priority plus type: `【P#】【type】`;
2. ASCII priority plus type: `[P#][type]`;
3. full-width priority only: `【P#】`;
4. ASCII priority only: `[P#]`;
5. an exact current Issue Form `title` prefix;
6. another bracketed prefix;
7. no recognized prefix.

The report includes every Issue number in every class without shortening long
lists. A bilingual title is governance metadata only; it is not treated as
evidence that the product is localized.

### Issue Form adherence

The deterministic audit population is all current Open Issues whose title
starts with exactly one current Issue Form `title` prefix. There is no random
sample. For each Form, the report lists every parsed field, whether the current
Form marks it required, and every matched Issue with an absent response.

Responses are matched to GitHub-generated `### <field label>` headings. Empty
content, HTML comments alone, and GitHub's `_No response_` placeholder are
absent. A user-entered `N/A` remains an explicit response; judging whether its
reason is adequate requires human review. Optional field omissions are
informational; required field omissions are compliance findings.

If no Open Issue matches a Form's exact prefix, every field is reported as not
assessed rather than incorrectly reporting zero missing responses. Overlapping
Form prefixes that make one Issue match multiple Forms fail the audit instead
of double-counting it.

Issues without a current exact Form prefix are listed as manual, historical, or
differently prefixed and are not counted as Form failures. GitHub does not
expose which Form version created an Issue, so the report does not claim that a
current required field was required when a historical Issue was opened.

### Assignees

Coverage uses the current Open Issue `assignees` array. Every unassigned Issue
number is reported. The exact `已阻塞` label is explicitly not treated as an
assignment mechanism.

### Recently merged pull requests

The tool fully paginates closed pull requests, keeps only entries with a
non-null `merged_at`, sorts descending by that timestamp (then descending by PR
number for a deterministic tie-break), and selects the first 10.

Local Issue references in each selected PR title and body are separated into:

- automatic close semantics: `close`, `fix`, and `resolve` variants;
- ordinary relation semantics: `ref`, `reference`, `support`, and `related`
  variants;
- negated close statements such as `does not close #N`, which are explicitly
  reported and treated as ordinary relations rather than auto-close intent;
- unqualified local Issue references;
- unresolved local numbers, including references that identify a PR rather
  than an Issue or a number absent from the complete Issue set.

References may use `#N`, `owner/repository#N`, or a full local Issue URL.

### Blocked dependencies

Only current Open Issues carrying the exact `已阻塞` label enter this section.
The parser extracts numbers only from explicit dependency headings or same-line
markers, including `Blocked by`, `Depends on`, `Dependencies:`, `阻塞项`,
`阻塞依赖`, `依赖：`, and `前置依赖：`. An unrelated `#N` elsewhere in a body
is not silently promoted to a dependency.

Each dependency is resolved against the fully fetched Issue set and classified
as open, closed/stale, or missing/non-Issue. A blocked Issue with no parsed
number is reported as lacking a numbered reason. Strongly connected components
among current Open Issue dependencies identify potential multi-Issue and
self-referential cycles.

GitHub's snapshot API does not expose when a label was first applied. The audit
states this limitation and never substitutes Issue creation time as a false
blocked-duration measurement.

### Milestones

Every repository milestone is listed with its state, count of current Open
Issues, and complete Issue-number list. Open Issues without a milestone are
listed separately. A milestone is scheduling state, not a permanent type label.

## Offline verification

The test suite uses only synthetic fixtures and does not depend on GitHub:

```powershell
python -m py_compile `
  .\tools\audit-issue-health.py `
  .\tools\test-audit-issue-health.py
python .\tools\test-audit-issue-health.py
```

Fixtures cover multi-page JSON, malformed JSON, safe API failures, Issue Form
required and optional fields, overlapping Form prefixes, exact title classes,
automatic, negated, and ordinary PR relations, non-dependency references,
closed and missing blockers, unnamed blockers, self and multi-Issue cycles,
merged-time ordering, full untruncated number lists, API field-presence checks,
UTF-8 CLI output in a subprocess, content non-disclosure, and successful and
failed atomic writes.

An online run is a separate integration check because repository state changes
over time. Its counts must be read from the newly generated report rather than
hard-coded into tests or this document.

## Residual limits

- The report is a current snapshot and contains no historical trend analysis.
- Current default-branch Forms cannot prove the schema used by historical or
  manually created Issues.
- The dependency-free Form reader supports the standard GitHub Issue Form
  indentation and scalar structure used by this repository. Unsupported or
  malformed Form structure aborts the audit rather than producing partial
  field statistics.
- Dependency and PR relation classification is based on the exact documented
  markers. Free-form prose without those markers remains unclassified.
- Label history, including the first time `已阻塞` was applied, is unavailable
  from the queried snapshot endpoints.
- This tool performs no GitHub automation and does not relax any existing CI,
  review, source-package, device, account, privacy, or release gate.
