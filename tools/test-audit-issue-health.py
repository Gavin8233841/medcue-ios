#!/usr/bin/env python3
"""Offline tests for audit-issue-health.py using synthetic fixtures only."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from dataclasses import replace
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).with_name("audit-issue-health.py")
SPEC = importlib.util.spec_from_file_location("audit_issue_health", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load audit-issue-health.py")
audit = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = audit
SPEC.loader.exec_module(audit)


def synthetic_form_text() -> str:
    return """\
name: Synthetic bug
title: "[Bug] "
body:
  - type: markdown
    attributes:
      value: Do not include sensitive data.
  - type: textarea
    id: impact
    attributes:
      label: User impact
    validations:
      required: true
  - type: textarea
    id: notes
    attributes:
      label: Optional notes
    validations:
      required: false
"""


def issue(
    number: int,
    *,
    state: str = "open",
    title: str = "Synthetic issue",
    body: str = "",
    labels: tuple[str, ...] = (),
    assignees: tuple[str, ...] = (),
    milestone: dict[str, object] | None = None,
) -> dict[str, object]:
    return {
        "number": number,
        "state": state,
        "title": title,
        "body": body,
        "labels": labels,
        "assignees": assignees,
        "milestone": milestone,
        "is_pull_request": False,
    }


def pull_request(
    number: int,
    *,
    state: str,
    merged_at: str | None,
    title: str = "Synthetic pull request",
    body: str = "",
) -> dict[str, object]:
    return {
        "number": number,
        "state": state,
        "title": title,
        "body": body,
        "merged_at": merged_at,
    }


def synthetic_snapshot() -> audit.Snapshot:
    form = audit.parse_issue_form(synthetic_form_text(), ".github/ISSUE_TEMPLATE/bug.yml")
    milestone = {"number": 1, "title": "Synthetic M1", "state": "open"}
    issues = (
        issue(
            1,
            title="[Bug] SECRET_TITLE_MUST_NOT_LEAK",
            body="### User impact\n\nA bounded synthetic impact.\n\n### Optional notes\n\n_No response_",
            labels=("P1", "缺陷"),
            assignees=("worker",),
            milestone=milestone,
        ),
        issue(
            2,
            title="【P2】【治理】Self-blocked",
            body="## Dependencies\n\n- #2\n- #3\n- #99\nSECRET_BODY_MUST_NOT_LEAK",
            labels=("P2", "治理", "已阻塞"),
        ),
        issue(3, state="closed", title="Closed dependency"),
        issue(
            4,
            title="[P2][Governance] Cycle A",
            body="Blocked by #5",
            labels=("P2", "治理", "已阻塞"),
        ),
        issue(5, title="[Feature] Cycle B", body="Dependencies: #4", labels=("功能",)),
        issue(6, title="No prefix", labels=("已阻塞",)),
    )
    comments = (
        {"id": 1001, "issue_url": "https://api.github.com/repos/example/project/issues/1"},
        {"id": 1002, "issue_url": "https://api.github.com/repos/example/project/issues/101"},
    )
    open_prs = (
        pull_request(101, state="open", merged_at=None),
    )
    closed_prs = (
        pull_request(
            102,
            state="closed",
            merged_at="2026-02-03T00:00:00Z",
            title="SECRET_PR_TITLE_MUST_NOT_LEAK",
            body="Fixes #1, #2. Refs #3 and #4. See #5. SECRET_PR_BODY_MUST_NOT_LEAK",
        ),
        pull_request(
            103,
            state="closed",
            merged_at="2026-02-02T00:00:00Z",
            body="Supports #4 and #5",
        ),
        pull_request(104, state="closed", merged_at=None, body="Closed without merge"),
    )
    return audit.Snapshot(
        repository="example/project",
        default_branch="main",
        issues=issues,
        comments=comments,
        open_prs=open_prs,
        closed_prs=closed_prs,
        labels=("P1", "P2", "功能", "缺陷", "治理", "已阻塞"),
        milestones=(milestone,),
        forms=(form,),
        pages={
            "issues": 2,
            "comments": 3,
            "open_prs": 1,
            "closed_prs": 2,
            "labels": 1,
            "milestones": 1,
        },
    )


class JsonAndApiTests(unittest.TestCase):
    def test_decode_json_stream_accepts_multiple_pages(self) -> None:
        values = audit.decode_json_stream('[{"id": 1}]\n[{"id": 2}]\n', "fixture")
        self.assertEqual(values, [[{"id": 1}], [{"id": 2}]])

    def test_decode_json_stream_fails_closed_on_trailing_garbage(self) -> None:
        with self.assertRaises(audit.AuditError):
            audit.decode_json_stream("[] not-json", "fixture")

    def test_paginated_api_uses_no_shell_and_keeps_every_page(self) -> None:
        calls: list[tuple[list[str], dict[str, object]]] = []

        def runner(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
            calls.append((command, kwargs))
            return subprocess.CompletedProcess(command, 0, '[{"id": 1}]\n[{"id": 2}]\n', "")

        client = audit.GhApi(runner=runner)
        result = client.get_pages("repos/example/project/items?per_page=100", "map({id: .id})", "items")

        self.assertEqual(result.page_count, 2)
        self.assertEqual([item["id"] for item in result.items], [1, 2])
        command, kwargs = calls[0]
        self.assertEqual(command[:2], ["gh", "api"])
        self.assertIn("--paginate", command)
        self.assertIn("--jq", command)
        self.assertNotIn("shell", kwargs)

    def test_api_failure_does_not_relay_sensitive_stderr(self) -> None:
        secret = "TOKEN_SHOULD_NOT_APPEAR"

        def runner(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
            return subprocess.CompletedProcess(command, 1, "", secret)

        client = audit.GhApi(runner=runner)
        with self.assertRaises(audit.AuditError) as context:
            client.get_json("repos/example/project", "metadata")
        self.assertNotIn(secret, str(context.exception))

    def test_comment_projection_excludes_comment_body(self) -> None:
        self.assertNotIn("body", audit.COMMENT_PROJECTION)
        self.assertIn("issue_url", audit.COMMENT_PROJECTION)

    def test_repository_validation_rejects_command_like_input(self) -> None:
        for value in ("owner/repo;echo", "owner/repo/extra", "../repo", "owner", ""):
            with self.subTest(value=value), self.assertRaises(audit.AuditError):
                audit.validate_repository(value)

    def test_issue_validation_distinguishes_missing_fields_from_legal_null_body(self) -> None:
        projected = {
            "number": 1,
            "state": "open",
            "title": "Synthetic",
            "body_present": True,
            "body": None,
            "labels": [],
            "assignees": [],
            "milestone_present": True,
            "milestone": None,
            "is_pull_request": False,
        }
        self.assertEqual(audit.validate_issue(projected)["body"], "")

        for field in ("title", "body_present", "labels", "assignees", "milestone_present"):
            with self.subTest(field=field):
                incomplete = {**projected}
                incomplete.pop(field)
                with self.assertRaises(audit.AuditError):
                    audit.validate_issue(incomplete)

    def test_pr_validation_distinguishes_missing_fields_from_legal_nulls(self) -> None:
        projected = {
            "number": 10,
            "state": "open",
            "title": "Synthetic",
            "body_present": True,
            "body": None,
            "merged_at_present": True,
            "merged_at": None,
        }
        validated = audit.validate_pr(projected, "pull requests")
        self.assertEqual(validated["body"], "")
        self.assertIsNone(validated["merged_at"])

        for field in ("title", "body_present", "merged_at_present"):
            with self.subTest(field=field):
                incomplete = {**projected}
                incomplete.pop(field)
                with self.assertRaises(audit.AuditError):
                    audit.validate_pr(incomplete, "pull requests")

    def test_cli_stdout_is_utf8_even_when_host_default_differs(self) -> None:
        child_code = f"""\
import importlib.util
import sys
spec = importlib.util.spec_from_file_location("audit_issue_health_child", {str(MODULE_PATH)!r})
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
module.fetch_snapshot = lambda repository, api: None
module.analyze = lambda snapshot: {{}}
module.render_report = lambda snapshot, result, generated_at: "治理"
raise SystemExit(module.main(["--repo", "example/project", "--output", "-"]))
"""
        completed = subprocess.run(
            [sys.executable, "-B", "-c", child_code],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8"))
        self.assertEqual(completed.stdout.decode("utf-8").strip(), "治理")


class IssueFormTests(unittest.TestCase):
    def test_parse_form_records_required_and_optional_fields(self) -> None:
        form = audit.parse_issue_form(synthetic_form_text(), "bug.yml")
        self.assertEqual(form.name, "Synthetic bug")
        self.assertEqual(form.title_prefix, "[Bug] ")
        self.assertEqual(
            [(field.field_id, field.label, field.required) for field in form.fields],
            [("impact", "User impact", True), ("notes", "Optional notes", False)],
        )

    def test_parse_form_rejects_missing_field_label(self) -> None:
        malformed = """\
name: Broken
title: "[Broken] "
body:
  - type: textarea
    id: missing-label
    validations:
      required: true
"""
        with self.assertRaises(audit.AuditError):
            audit.parse_issue_form(malformed, "broken.yml")

    def test_parse_form_rejects_fields_outside_missing_body(self) -> None:
        malformed = """\
name: Broken
title: "[Broken] "
not_body:
  - type: textarea
    id: decoy
    attributes:
      label: Decoy field
"""
        with self.assertRaisesRegex(audit.AuditError, "top-level body"):
            audit.parse_issue_form(malformed, "broken.yml")

    def test_parse_form_only_counts_items_inside_body(self) -> None:
        form_text = synthetic_form_text() + """\
not_body:
  - type: textarea
    id: decoy
    attributes:
      label: Decoy field
"""
        form = audit.parse_issue_form(form_text, "mixed.yml")
        self.assertEqual([field.field_id for field in form.fields], ["impact", "notes"])

    def test_parse_form_rejects_duplicate_body(self) -> None:
        with self.assertRaisesRegex(audit.AuditError, "top-level body"):
            audit.parse_issue_form(synthetic_form_text() + "body:\n", "duplicate.yml")

    def test_parse_form_separates_items_when_type_is_not_first(self) -> None:
        form_text = """\
name: Ordered fields
title: "[Ordered] "
body:
  - type: textarea
    id: first
    attributes:
      label: First response
    validations:
      required: true
  - id: second
    type: textarea
    attributes:
      label: Second response
    validations:
      required: true
"""
        form = audit.parse_issue_form(form_text, "ordered.yml")
        self.assertEqual(
            [(field.field_id, field.label, field.required) for field in form.fields],
            [("first", "First response", True), ("second", "Second response", True)],
        )

    def test_parse_form_rejects_body_item_without_supported_type(self) -> None:
        malformed = synthetic_form_text() + """\
  - id: hidden
    attributes:
      label: Hidden response
"""
        with self.assertRaisesRegex(audit.AuditError, "body item type"):
            audit.parse_issue_form(malformed, "hidden.yml")

    def test_parse_form_rejects_unsupported_folded_title(self) -> None:
        malformed = synthetic_form_text().replace('title: "[Bug] "', 'title: >-\n  [Bug]')
        with self.assertRaisesRegex(audit.AuditError, "unsupported YAML scalar"):
            audit.parse_issue_form(malformed, "folded.yml")

    def test_parse_form_rejects_flow_validation_mapping(self) -> None:
        malformed = synthetic_form_text().replace(
            "    validations:\n      required: true",
            "    validations: {required: true}",
            1,
        )
        with self.assertRaisesRegex(audit.AuditError, "unsupported validations mapping"):
            audit.parse_issue_form(malformed, "flow.yml")

    def test_parse_form_reads_valid_spaced_mapping_keys(self) -> None:
        form_text = synthetic_form_text().replace(
            "    validations:\n      required: true",
            "    validations :\n      required : true",
            1,
        )
        form = audit.parse_issue_form(form_text, "spaced.yml")
        self.assertTrue(form.fields[0].required)

    def test_parse_form_rejects_unsupported_validation_indentation(self) -> None:
        malformed = synthetic_form_text().replace(
            "      required: true", "        required: true", 1
        )
        with self.assertRaisesRegex(audit.AuditError, "unsupported validations entry"):
            audit.parse_issue_form(malformed, "indented.yml")

    def test_parse_form_rejects_quoted_validation_keys(self) -> None:
        for original, replacement, expected in (
            ("    validations:", '    "validations":', "unsupported body property"),
            ("      required: true", '      "required": true', "unsupported validations entry"),
        ):
            with self.subTest(replacement=replacement):
                malformed = synthetic_form_text().replace(original, replacement, 1)
                with self.assertRaisesRegex(audit.AuditError, expected):
                    audit.parse_issue_form(malformed, "quoted.yml")

    def test_form_sections_treat_github_no_response_marker_as_missing(self) -> None:
        sections = audit.extract_form_sections(
            "### Required\n\nA value\n\n### Optional\n\n<!-- hidden -->\n_No response_"
        )
        self.assertTrue(audit.response_present(sections["Required"]))
        self.assertFalse(audit.response_present(sections["Optional"]))
        self.assertFalse(audit.response_present(()))
        self.assertTrue(audit.response_present(("N/A",)))


class ClassificationTests(unittest.TestCase):
    def test_title_prefix_rules_are_exact_and_ordered(self) -> None:
        cases = {
            "【P1】【治理】中文 / English": "full-width priority + type",
            "[P2][Governance] English": "ASCII priority + type",
            "【P3】Only": "full-width priority only",
            "[P0] Only": "ASCII priority only",
            "[Bug] Template": "exact current Issue Form prefix",
            "[Feature] Historical": "other bracketed prefix",
            "No prefix": "no recognized prefix",
        }
        for title, expected in cases.items():
            with self.subTest(title=title):
                self.assertEqual(audit.classify_title(title, ("[Bug] ",)), expected)

    def test_pr_linkage_distinguishes_semantics_and_unresolved_numbers(self) -> None:
        text = (
            "Fixes #1, #2. Refs #3 and #4. See #5. "
            "Resolves example/project#6. Related to "
            "https://github.com/example/project/issues/7. Mentions #99."
        )
        result = audit.classify_pr_references(text, "example/project", set(range(1, 8)))
        self.assertEqual(result["automatic"], (1, 2, 6))
        self.assertEqual(result["ordinary"], (3, 4, 7))
        self.assertEqual(result["unqualified"], (5,))
        self.assertEqual(result["unresolved"], (99,))

    def test_pr_linkage_treats_negated_close_as_ordinary_relation(self) -> None:
        text = (
            "This checkpoint does not close #1, #2, or #3. "
            "Related: #1, #2, #3. Fixes #4."
        )
        result = audit.classify_pr_references(text, "example/project", {1, 2, 3, 4})
        self.assertEqual(result["automatic"], (4,))
        self.assertEqual(result["ordinary"], (1, 2, 3))
        self.assertEqual(result["negated_automatic"], (1, 2, 3))
        self.assertEqual(result["unqualified"], ())

    def test_dependency_parser_uses_explicit_markers_only(self) -> None:
        body = """\
See #88 for context; this is not a dependency.
Depends on #1 and #2.

## 前置依赖

- #3
- https://github.com/example/project/issues/4

## Verification

Check #77.
"""
        self.assertEqual(audit.extract_dependencies(body, "example/project"), (1, 2, 3, 4))

    def test_dependency_parser_accepts_reference_on_heading_line(self) -> None:
        body = "## Blocked by #7\n\n- #8\n\n## Verification\n\nSee #9."
        self.assertEqual(audit.extract_dependencies(body, "example/project"), (7, 8))

    def test_cycle_detection_handles_self_and_multi_node_cycles(self) -> None:
        graph = {1: {1}, 2: {3}, 3: {2}, 4: {5}, 5: set()}
        self.assertEqual(audit.find_cycle_components(graph), ((1,), (2, 3)))

    def test_number_lists_are_never_truncated(self) -> None:
        rendered = audit.number_list(range(1, 151))
        self.assertIn("#1", rendered)
        self.assertIn("#150", rendered)
        self.assertNotIn("...", rendered)
        self.assertEqual(rendered.count("#"), 150)


class AnalysisAndReportTests(unittest.TestCase):
    def test_analysis_covers_labels_forms_assignees_comments_and_milestones(self) -> None:
        result = audit.analyze(synthetic_snapshot())

        self.assertEqual(result["labels"]["none"], ())
        self.assertEqual(result["labels"]["no_priority"], (5, 6))
        self.assertEqual(result["unassigned"], (2, 4, 5, 6))
        self.assertEqual(result["forms"][0]["matched"], (1,))
        required = result["forms"][0]["fields"][0]
        optional = result["forms"][0]["fields"][1]
        self.assertEqual(required["missing"], ())
        self.assertEqual(optional["missing"], (1,))
        self.assertEqual(result["unmatched_forms"], (2, 4, 5, 6))
        self.assertEqual(result["issue_comment_count"], 1)
        self.assertEqual(result["open_issue_comment_count"], 1)
        self.assertEqual(result["pr_comment_count"], 1)
        self.assertEqual(result["without_milestone"], (2, 4, 5, 6))

    def test_blockers_report_closed_missing_unnamed_and_cycles(self) -> None:
        result = audit.analyze(synthetic_snapshot())
        blockers = {item["number"]: item for item in result["blockers"]}

        self.assertEqual(set(blockers), {2, 4, 6})
        self.assertEqual(blockers[2]["closed"], (3,))
        self.assertEqual(blockers[2]["missing"], (99,))
        self.assertEqual(blockers[6]["dependencies"], ())
        self.assertEqual(result["blocker_cycles"], ((2,), (4, 5)))

    def test_recent_prs_are_sorted_by_merged_at_and_limited_to_ten(self) -> None:
        snapshot = synthetic_snapshot()
        merged = []
        for number in range(200, 212):
            day = number - 199
            merged.append(
                pull_request(
                    number,
                    state="closed",
                    merged_at=f"2026-03-{day:02d}T00:00:00Z",
                    body="Refs #1",
                )
            )
        result = audit.analyze(replace(snapshot, closed_prs=tuple(reversed(merged))))

        self.assertEqual(len(result["recent_prs"]), 10)
        self.assertEqual([item["number"] for item in result["recent_prs"]], list(range(211, 201, -1)))

    def test_report_never_emits_issue_or_pr_title_or_body(self) -> None:
        snapshot = synthetic_snapshot()
        result = audit.analyze(snapshot)
        report = audit.render_report(
            snapshot, result, datetime(2026, 3, 1, tzinfo=timezone.utc)
        )

        for sentinel in (
            "SECRET_TITLE_MUST_NOT_LEAK",
            "SECRET_BODY_MUST_NOT_LEAK",
            "SECRET_PR_TITLE_MUST_NOT_LEAK",
            "SECRET_PR_BODY_MUST_NOT_LEAK",
        ):
            self.assertNotIn(sentinel, report)
        self.assertIn("Status: COMPLETE", report)
        self.assertIn("closed/stale=#3", report)
        self.assertIn("missing/non-Issue=#99", report)
        self.assertIn("Potential open dependency cycle components: #2; #4, #5", report)
        self.assertIn('Exact title prefix: `"[Bug] "`', report)

    def test_report_marks_empty_form_population_as_not_assessed(self) -> None:
        snapshot = synthetic_snapshot()
        unmatched = {**snapshot.issues[0], "title": "Historical title"}
        snapshot = replace(snapshot, issues=(unmatched, *snapshot.issues[1:]))
        result = audit.analyze(snapshot)
        report = audit.render_report(
            snapshot, result, datetime(2026, 3, 1, tzinfo=timezone.utc)
        )

        self.assertIn(
            "not assessed because no Open Issue matched this Form's exact title prefix",
            report,
        )

    def test_overlapping_form_prefixes_fail_closed(self) -> None:
        snapshot = synthetic_snapshot()
        broad_form = audit.IssueForm(
            path=".github/ISSUE_TEMPLATE/broad.yml",
            name="Broad",
            title_prefix="[",
            fields=(audit.FormField("field", "Field", True),),
        )
        snapshot = replace(snapshot, forms=(snapshot.forms[0], broad_form))
        with self.assertRaises(audit.AuditError):
            audit.analyze(snapshot)


class AtomicOutputTests(unittest.TestCase):
    def test_atomic_write_replaces_complete_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "audit.md"
            output.write_text("old\n", encoding="utf-8")
            audit.atomic_write_text(output, "new report")
            self.assertEqual(output.read_text(encoding="utf-8"), "new report\n")
            self.assertEqual([item.name for item in output.parent.iterdir()], ["audit.md"])

    def test_atomic_write_failure_preserves_old_file_and_removes_temp(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "audit.md"
            output.write_text("old\n", encoding="utf-8")
            with mock.patch.object(audit.os, "replace", side_effect=OSError("synthetic")):
                with self.assertRaises(audit.AuditError):
                    audit.atomic_write_text(output, "new report")
            self.assertEqual(output.read_text(encoding="utf-8"), "old\n")
            self.assertEqual([item.name for item in output.parent.iterdir()], ["audit.md"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
