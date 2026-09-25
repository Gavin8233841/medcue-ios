#!/usr/bin/env python3
"""Generate a read-only, fail-closed GitHub Issue health audit."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterable, Sequence
from urllib.parse import quote


DEFAULT_REPOSITORY = "Gavin8233841/medcue-ios"
PRIORITY_LABELS = frozenset({"P0", "P1", "P2", "P3"})
TYPE_LABELS = frozenset({"功能", "缺陷", "增强", "问题", "技术债务", "治理", "文档"})
BLOCKED_LABEL = "已阻塞"
NO_RESPONSE_MARKERS = frozenset({"", "no response", "_no response_"})
REPOSITORY_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
ISSUE_URL_NUMBER_RE = re.compile(r"/issues/(\d+)$")
HASH_REFERENCE_RE = re.compile(r"(?<![A-Za-z0-9_])#(\d+)\b")


class AuditError(RuntimeError):
    """A safe-to-display error that means no complete audit can be produced."""


@dataclass(frozen=True)
class PageResult:
    items: tuple[dict[str, Any], ...]
    page_count: int


@dataclass(frozen=True)
class FormField:
    field_id: str
    label: str
    required: bool


@dataclass(frozen=True)
class IssueForm:
    path: str
    name: str
    title_prefix: str
    fields: tuple[FormField, ...]


@dataclass(frozen=True)
class Snapshot:
    repository: str
    default_branch: str
    issues: tuple[dict[str, Any], ...]
    comments: tuple[dict[str, Any], ...]
    open_prs: tuple[dict[str, Any], ...]
    closed_prs: tuple[dict[str, Any], ...]
    labels: tuple[str, ...]
    milestones: tuple[dict[str, Any], ...]
    forms: tuple[IssueForm, ...]
    pages: dict[str, int]


RunCommand = Callable[..., subprocess.CompletedProcess[str]]


class GhApi:
    """Small gh API adapter that never invokes a shell or exposes raw errors."""

    def __init__(
        self,
        executable: str = "gh",
        timeout_seconds: int = 180,
        runner: RunCommand = subprocess.run,
    ) -> None:
        self.executable = executable
        self.timeout_seconds = timeout_seconds
        self.runner = runner

    def _invoke(self, arguments: Sequence[str], resource: str) -> str:
        command = [self.executable, "api", *arguments]
        try:
            completed = self.runner(
                command,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="strict",
                timeout=self.timeout_seconds,
                check=False,
            )
        except FileNotFoundError as exc:
            raise AuditError("GitHub CLI is not installed or is not on PATH") from exc
        except subprocess.TimeoutExpired as exc:
            raise AuditError(f"GitHub API request timed out while reading {resource}") from exc
        except UnicodeError as exc:
            raise AuditError(f"GitHub returned non-UTF-8 data for {resource}") from exc
        except OSError as exc:
            raise AuditError(f"GitHub API request could not start for {resource}") from exc

        if completed.returncode != 0:
            # stderr is intentionally not relayed because authentication and proxy
            # failures can contain credentials or private machine details.
            raise AuditError(
                f"GitHub API request failed while reading {resource} "
                f"(gh exit code {completed.returncode})"
            )
        return completed.stdout

    def get_json(self, endpoint: str, resource: str) -> Any:
        raw = self._invoke([endpoint], resource)
        try:
            return json.loads(raw)
        except json.JSONDecodeError as exc:
            raise AuditError(f"GitHub returned invalid JSON for {resource}") from exc

    def get_pages(self, endpoint: str, projection: str, resource: str) -> PageResult:
        # gh applies the jq projection to each page. This keeps unrelated API
        # fields, especially comment bodies, outside this process.
        raw = self._invoke([endpoint, "--paginate", "--jq", projection], resource)
        page_values = decode_json_stream(raw, resource)
        if not page_values:
            raise AuditError(f"GitHub pagination returned no page for {resource}")

        items: list[dict[str, Any]] = []
        for page in page_values:
            if not isinstance(page, list):
                raise AuditError(f"GitHub pagination returned a non-list page for {resource}")
            for item in page:
                if not isinstance(item, dict):
                    raise AuditError(f"GitHub returned a non-object item for {resource}")
                items.append(item)
        return PageResult(tuple(items), len(page_values))


def decode_json_stream(raw: str, resource: str = "API data") -> list[Any]:
    """Decode one or more whitespace-separated JSON values without string tricks."""

    text = raw.lstrip("\ufeff")
    decoder = json.JSONDecoder()
    position = 0
    values: list[Any] = []
    while True:
        while position < len(text) and text[position].isspace():
            position += 1
        if position == len(text):
            return values
        try:
            value, position = decoder.raw_decode(text, position)
        except json.JSONDecodeError as exc:
            raise AuditError(f"GitHub returned invalid paginated JSON for {resource}") from exc
        values.append(value)


def validate_repository(value: str) -> str:
    if not REPOSITORY_RE.fullmatch(value):
        raise AuditError("repository must use the exact owner/name form")
    owner, name = value.split("/", 1)
    if owner in {".", ".."} or name in {".", ".."}:
        raise AuditError("repository must use the exact owner/name form")
    return value


def require_string(value: Any, field: str, resource: str, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str) or (not allow_empty and not value.strip()):
        raise AuditError(f"GitHub response is missing {field} for {resource}")
    return value


def require_positive_int(value: Any, field: str, resource: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise AuditError(f"GitHub response has invalid {field} for {resource}")
    return value


def ensure_unique(items: Iterable[Any], key: Callable[[Any], Any], resource: str) -> None:
    seen: set[Any] = set()
    for item in items:
        identity = key(item)
        if identity in seen:
            raise AuditError(f"GitHub pagination returned duplicate data for {resource}")
        seen.add(identity)


def validate_issue(raw: dict[str, Any]) -> dict[str, Any]:
    number = require_positive_int(raw.get("number"), "number", "issues")
    state = require_string(raw.get("state"), "state", f"issue #{number}")
    if state not in {"open", "closed"}:
        raise AuditError(f"GitHub response has invalid state for issue #{number}")
    title = require_string(raw.get("title"), "title", f"issue #{number}")
    if raw.get("body_present") is not True:
        raise AuditError(f"GitHub response is missing body for issue #{number}")
    raw_body = raw.get("body")
    if raw_body is None:
        body = ""
    else:
        body = require_string(raw_body, "body", f"issue #{number}", allow_empty=True)
    labels = raw.get("labels")
    assignees = raw.get("assignees")
    if not isinstance(labels, list) or not all(isinstance(item, str) for item in labels):
        raise AuditError(f"GitHub response has invalid labels for issue #{number}")
    if not isinstance(assignees, list) or not all(isinstance(item, str) for item in assignees):
        raise AuditError(f"GitHub response has invalid assignees for issue #{number}")

    if raw.get("milestone_present") is not True:
        raise AuditError(f"GitHub response is missing milestone for issue #{number}")
    milestone = raw.get("milestone")
    if milestone is not None:
        if not isinstance(milestone, dict):
            raise AuditError(f"GitHub response has invalid milestone for issue #{number}")
        require_positive_int(milestone.get("number"), "milestone number", f"issue #{number}")
        require_string(milestone.get("title"), "milestone title", f"issue #{number}")
        milestone_state = require_string(
            milestone.get("state"), "milestone state", f"issue #{number}"
        )
        if milestone_state not in {"open", "closed"}:
            raise AuditError(f"GitHub response has invalid milestone state for issue #{number}")

    is_pull_request = raw.get("is_pull_request")
    if not isinstance(is_pull_request, bool):
        raise AuditError(f"GitHub response is missing issue kind for issue #{number}")
    return {
        "number": number,
        "state": state,
        "title": title,
        "body": body,
        "labels": tuple(labels),
        "assignees": tuple(assignees),
        "milestone": milestone,
        "is_pull_request": is_pull_request,
    }


def validate_pr(raw: dict[str, Any], resource: str) -> dict[str, Any]:
    number = require_positive_int(raw.get("number"), "number", resource)
    state = require_string(raw.get("state"), "state", f"pull request #{number}")
    if state not in {"open", "closed"}:
        raise AuditError(f"GitHub response has invalid state for pull request #{number}")
    title = require_string(raw.get("title"), "title", f"pull request #{number}")
    if raw.get("body_present") is not True:
        raise AuditError(f"GitHub response is missing body for pull request #{number}")
    raw_body = raw.get("body")
    if raw_body is None:
        body = ""
    else:
        body = require_string(raw_body, "body", f"pull request #{number}", allow_empty=True)
    if raw.get("merged_at_present") is not True:
        raise AuditError(f"GitHub response is missing merged_at for pull request #{number}")
    merged_at = raw.get("merged_at")
    if merged_at is not None and not isinstance(merged_at, str):
        raise AuditError(f"GitHub response has invalid merged_at for pull request #{number}")
    return {
        "number": number,
        "state": state,
        "title": title,
        "body": body,
        "merged_at": merged_at,
    }


def yaml_scalar(value: str) -> str:
    value = value.strip()
    if not value:
        return ""
    if value[0] in "|>[{&*!":
        raise AuditError("Issue Form contains an unsupported YAML scalar")
    if value.startswith('"'):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError as exc:
            raise AuditError("Issue Form contains an invalid quoted scalar") from exc
        if not isinstance(parsed, str):
            raise AuditError("Issue Form contains a non-string scalar")
        return parsed
    if value.startswith("'"):
        if len(value) < 2 or not value.endswith("'"):
            raise AuditError("Issue Form contains an invalid quoted scalar")
        return value[1:-1].replace("''", "'")
    return value.split(" #", 1)[0].rstrip()


def parse_issue_form(text: str, path: str) -> IssueForm:
    if "\t" in text:
        raise AuditError(f"Issue Form uses unsupported tab indentation: {path}")
    lines = text.splitlines()
    root_values: dict[str, str] = {}
    for line in lines:
        match = re.match(r"^(name|title):\s*(.*)$", line)
        if match:
            root_values[match.group(1)] = yaml_scalar(match.group(2))

    name = root_values.get("name", "").strip()
    title_prefix = root_values.get("title", "")
    if not name or not title_prefix.strip():
        raise AuditError(f"Issue Form must define name and title prefix: {path}")

    body_headers = [
        index
        for index, line in enumerate(lines)
        if re.match(r"^body:\s*(?:#.*)?$", line)
    ]
    if len(body_headers) != 1:
        raise AuditError(f"Issue Form must define one top-level body: {path}")
    body_start = body_headers[0] + 1
    body_end = next(
        (
            index
            for index in range(body_start, len(lines))
            if lines[index].strip() and not lines[index][0].isspace() and not lines[index].startswith("#")
        ),
        len(lines),
    )
    body_lines = lines[body_start:body_end]
    if any(
        re.match(r"^  [^\s#]", line) and not re.match(r"^  -(?:\s|$)", line)
        for line in body_lines
    ):
        raise AuditError(f"Issue Form body contains an unsupported entry: {path}")
    starts = [
        index
        for index in range(body_start, body_end)
        if re.match(r"^  -(?:\s|$)", lines[index])
    ]
    if not starts:
        raise AuditError(f"Issue Form does not contain a parseable body: {path}")

    fields: list[FormField] = []
    for offset, start in enumerate(starts):
        end = starts[offset + 1] if offset + 1 < len(starts) else body_end
        first_match = re.match(r"^  -(?:\s+([A-Za-z0-9_-]+):\s*(.*))?$", lines[start])
        if first_match is None:
            raise AuditError(f"Issue Form contains an invalid body item: {path}")
        item_lines = lines[start + 1 : end]
        if first_match.group(1) is not None:
            item_lines = [f"    {first_match.group(1)}: {first_match.group(2)}", *item_lines]

        field_type = ""
        field_id = ""
        label = ""
        required = False
        required_seen = False
        section = ""
        for line in item_lines:
            property_match = re.match(r"^    ([A-Za-z0-9_-]+)\s*:\s*(.*)$", line)
            if property_match:
                key, value = property_match.groups()
                if key == "type":
                    if field_type:
                        raise AuditError(f"Issue Form body item repeats type: {path}")
                    field_type = yaml_scalar(value).strip()
                elif key == "id":
                    if field_id:
                        raise AuditError(f"Issue Form body item repeats id: {path}")
                    field_id = yaml_scalar(value).strip()
                elif key in {"attributes", "validations"}:
                    if value.strip() and not value.strip().startswith("#"):
                        raise AuditError(f"Issue Form has unsupported {key} mapping: {path}")
                    section = key
                    continue
                section = ""
                continue
            if re.match(r"^    \S", line) and not line.lstrip().startswith("#"):
                raise AuditError(f"Issue Form has unsupported body property: {path}")
            if section == "attributes":
                label_match = re.match(r"^      label\s*:\s*(.*)$", line)
                if label_match:
                    if label:
                        raise AuditError(f"Issue Form body item repeats label: {path}")
                    label = yaml_scalar(label_match.group(1)).strip()
            elif section == "validations":
                required_match = re.match(r"^      required\s*:\s*(.*)$", line)
                if required_match:
                    if required_seen:
                        raise AuditError(f"Issue Form body item repeats required: {path}")
                    scalar = yaml_scalar(required_match.group(1)).strip().lower()
                    if scalar not in {"true", "false"}:
                        raise AuditError(f"Issue Form has invalid required value: {path}")
                    required = scalar == "true"
                    required_seen = True
                elif line.strip() and not line.lstrip().startswith("#"):
                    raise AuditError(f"Issue Form has unsupported validations entry: {path}")

        if field_type not in {"markdown", "input", "textarea", "dropdown"}:
            raise AuditError(f"Issue Form has missing or unsupported body item type: {path}")
        if field_type == "markdown":
            continue
        if not field_id or not label:
            raise AuditError(f"Issue Form field is missing id or label: {path}")
        fields.append(FormField(field_id, label, required))

    if not fields:
        raise AuditError(f"Issue Form has no auditable fields: {path}")
    ensure_unique(fields, lambda field: field.field_id, f"Issue Form {path} field ids")
    ensure_unique(fields, lambda field: field.label, f"Issue Form {path} field labels")
    return IssueForm(path, name, title_prefix, tuple(fields))


ISSUE_PROJECTION = (
    "map({number: .number, state: .state, title: .title, "
    "body_present: has(\"body\"), body: .body, "
    "labels: (if (.labels | type) == \"array\" then [.labels[] | .name] else .labels end), "
    "assignees: (if (.assignees | type) == \"array\" then "
    "[.assignees[] | .login] else .assignees end), "
    "milestone_present: has(\"milestone\"), "
    "milestone: (if .milestone == null then null elif (.milestone | type) == \"object\" then "
    "{number: .milestone.number, title: .milestone.title, state: .milestone.state} "
    "else .milestone end), "
    "is_pull_request: has(\"pull_request\")})"
)
COMMENT_PROJECTION = (
    "map({id: .id, issue_url: .issue_url})"
)
PR_PROJECTION = (
    "map({number: .number, state: .state, title: .title, "
    "body_present: has(\"body\"), body: .body, "
    "merged_at_present: has(\"merged_at\"), merged_at: .merged_at})"
)
LABEL_PROJECTION = "map({name: .name})"
MILESTONE_PROJECTION = "map({number: .number, title: .title, state: .state})"


def fetch_snapshot(repository: str, api: GhApi) -> Snapshot:
    requested_repository = validate_repository(repository)
    metadata = api.get_json(f"repos/{requested_repository}", "repository metadata")
    if not isinstance(metadata, dict):
        raise AuditError("GitHub returned invalid repository metadata")
    actual_repository = require_string(metadata.get("full_name"), "full_name", "repository")
    if actual_repository.casefold() != requested_repository.casefold():
        raise AuditError("GitHub repository identity did not match the requested repository")
    default_branch = require_string(metadata.get("default_branch"), "default_branch", "repository")

    issues_page = api.get_pages(
        f"repos/{requested_repository}/issues?state=all&per_page=100&sort=created&direction=asc",
        ISSUE_PROJECTION,
        "all issues",
    )
    raw_issues = [validate_issue(item) for item in issues_page.items]
    ensure_unique(raw_issues, lambda issue: issue["number"], "all issues and pull requests")
    issues = tuple(issue for issue in raw_issues if not issue["is_pull_request"])

    comments_page = api.get_pages(
        f"repos/{requested_repository}/issues/comments?per_page=100&sort=created&direction=asc",
        COMMENT_PROJECTION,
        "issue comments",
    )
    comments: list[dict[str, Any]] = []
    for comment in comments_page.items:
        comment_id = require_positive_int(comment.get("id"), "id", "issue comments")
        issue_url = require_string(comment.get("issue_url"), "issue_url", "issue comments")
        if not ISSUE_URL_NUMBER_RE.search(issue_url):
            raise AuditError("GitHub response has an invalid issue URL in comments")
        comments.append({"id": comment_id, "issue_url": issue_url})
    ensure_unique(comments, lambda comment: comment["id"], "issue comments")

    open_pr_page = api.get_pages(
        f"repos/{requested_repository}/pulls?state=open&per_page=100&sort=created&direction=asc",
        PR_PROJECTION,
        "open pull requests",
    )
    open_prs = tuple(validate_pr(item, "open pull requests") for item in open_pr_page.items)
    if any(pr["state"] != "open" for pr in open_prs):
        raise AuditError("GitHub returned a non-open pull request in the open query")
    ensure_unique(open_prs, lambda pr: pr["number"], "open pull requests")

    closed_pr_page = api.get_pages(
        f"repos/{requested_repository}/pulls?state=closed&per_page=100&sort=created&direction=asc",
        PR_PROJECTION,
        "closed pull requests",
    )
    closed_prs = tuple(validate_pr(item, "closed pull requests") for item in closed_pr_page.items)
    if any(pr["state"] != "closed" for pr in closed_prs):
        raise AuditError("GitHub returned a non-closed pull request in the closed query")
    ensure_unique(closed_prs, lambda pr: pr["number"], "closed pull requests")
    ensure_unique(
        (*open_prs, *closed_prs), lambda pr: pr["number"], "all pull requests"
    )

    label_page = api.get_pages(
        f"repos/{requested_repository}/labels?per_page=100",
        LABEL_PROJECTION,
        "labels",
    )
    labels = tuple(
        require_string(item.get("name"), "name", "labels") for item in label_page.items
    )
    ensure_unique(labels, lambda label: label.casefold(), "labels")

    milestone_page = api.get_pages(
        f"repos/{requested_repository}/milestones?state=all&per_page=100&sort=due_on&direction=asc",
        MILESTONE_PROJECTION,
        "milestones",
    )
    milestones: list[dict[str, Any]] = []
    for item in milestone_page.items:
        number = require_positive_int(item.get("number"), "number", "milestones")
        state = require_string(item.get("state"), "state", f"milestone #{number}")
        if state not in {"open", "closed"}:
            raise AuditError(f"GitHub returned invalid state for milestone #{number}")
        milestones.append(
            {
                "number": number,
                "title": require_string(item.get("title"), "title", f"milestone #{number}"),
                "state": state,
            }
        )
    ensure_unique(milestones, lambda milestone: milestone["number"], "milestones")

    encoded_branch = quote(default_branch, safe="")
    template_directory = api.get_json(
        f"repos/{requested_repository}/contents/.github/ISSUE_TEMPLATE?ref={encoded_branch}",
        "Issue Template directory",
    )
    if not isinstance(template_directory, list):
        raise AuditError("GitHub returned invalid Issue Template directory data")
    form_entries = []
    for entry in template_directory:
        if not isinstance(entry, dict):
            raise AuditError("GitHub returned an invalid Issue Template entry")
        path = require_string(entry.get("path"), "path", "Issue Template entry")
        entry_type = require_string(entry.get("type"), "type", f"Issue Template {path}")
        lower_name = Path(path).name.lower()
        if entry_type == "file" and lower_name.endswith((".yml", ".yaml")) and lower_name != "config.yml":
            form_entries.append(path)
    if not form_entries:
        raise AuditError("no Issue Form files were found on the default branch")
    ensure_unique(form_entries, lambda path: path, "Issue Form paths")

    forms: list[IssueForm] = []
    for path in sorted(form_entries):
        encoded_path = quote(path, safe="/")
        content_object = api.get_json(
            f"repos/{requested_repository}/contents/{encoded_path}?ref={encoded_branch}",
            f"Issue Form {path}",
        )
        if not isinstance(content_object, dict):
            raise AuditError(f"GitHub returned invalid Issue Form data: {path}")
        if content_object.get("encoding") != "base64":
            raise AuditError(f"GitHub returned unsupported Issue Form encoding: {path}")
        encoded_content = require_string(
            content_object.get("content"), "content", f"Issue Form {path}"
        )
        try:
            decoded = base64.b64decode("".join(encoded_content.split()), validate=True).decode("utf-8")
        except (ValueError, UnicodeError) as exc:
            raise AuditError(f"GitHub returned invalid Issue Form content: {path}") from exc
        forms.append(parse_issue_form(decoded, path))
    ensure_unique(forms, lambda form: form.title_prefix, "Issue Form title prefixes")

    pages = {
        "issues": issues_page.page_count,
        "comments": comments_page.page_count,
        "open_prs": open_pr_page.page_count,
        "closed_prs": closed_pr_page.page_count,
        "labels": label_page.page_count,
        "milestones": milestone_page.page_count,
    }
    return Snapshot(
        actual_repository,
        default_branch,
        issues,
        tuple(comments),
        open_prs,
        closed_prs,
        labels,
        tuple(milestones),
        tuple(forms),
        pages,
    )


def classify_title(title: str, form_prefixes: Sequence[str]) -> str:
    if re.match(r"^【P[0-3]】【[^】]+】", title):
        return "full-width priority + type"
    if re.match(r"^\[P[0-3]\]\[[^\]]+\]", title):
        return "ASCII priority + type"
    if re.match(r"^【P[0-3]】(?!【)", title):
        return "full-width priority only"
    if re.match(r"^\[P[0-3]\](?!\[)", title):
        return "ASCII priority only"
    if any(title.startswith(prefix) for prefix in form_prefixes):
        return "exact current Issue Form prefix"
    if title.startswith(("【", "[")):
        return "other bracketed prefix"
    return "no recognized prefix"


def visible_markdown_lines(body: str) -> Iterable[tuple[int, str]]:
    fence_character = ""
    fence_length = 0
    offset = 0
    for line in body.splitlines(keepends=True):
        content = line.rstrip("\r\n")
        fence = re.match(r"^ {0,3}(`{3,}|~{3,})", content)
        if fence_character:
            if re.fullmatch(
                rf" {{0,3}}{re.escape(fence_character)}{{{fence_length},}}[ \t]*",
                content,
            ):
                fence_character = ""
        elif fence:
            fence_character = fence.group(1)[0]
            fence_length = len(fence.group(1))
        else:
            yield offset, content
        offset += len(line)


def extract_form_sections(body: str) -> dict[str, tuple[str, ...]]:
    headings: list[tuple[int, int, str]] = []
    for offset, content in visible_markdown_lines(body):
        heading = re.match(r"^###\s+(.+?)\s*$", content)
        if heading:
            headings.append((offset, offset + len(content), heading.group(1).strip()))
    sections: dict[str, list[str]] = {}
    for index, (_, start, label) in enumerate(headings):
        end = headings[index + 1][0] if index + 1 < len(headings) else len(body)
        sections.setdefault(label, []).append(body[start:end].strip())
    return {label: tuple(values) for label, values in sections.items()}


def response_present(values: Sequence[str]) -> bool:
    for value in values:
        without_comments = re.sub(r"<!--.*?-->", "", value, flags=re.DOTALL).strip()
        if without_comments.casefold() not in NO_RESPONSE_MARKERS:
            return True
    return False


def extract_local_references(text: str, repository: str) -> set[int]:
    escaped_repository = re.escape(repository)
    references = {int(value) for value in HASH_REFERENCE_RE.findall(text)}
    references.update(
        int(value)
        for value in re.findall(
            rf"https://github\.com/{escaped_repository}/issues/(\d+)\b", text, flags=re.IGNORECASE
        )
    )
    references.update(
        int(value)
        for value in re.findall(rf"\b{escaped_repository}#(\d+)\b", text, flags=re.IGNORECASE)
    )
    return references


AUTOMATIC_NEGATION_RE = re.compile(
    r"(?:"
    r"\b(?:do|does|did|will|would|should|could|can|must|is|are|was|were)\s+not"
    r"|\b(?:don't|doesn't|didn't|won't|wouldn't|shouldn't|couldn't|can't|mustn't)\b"
    r"|\bcannot\b|\bnever\b|\bno\s+(?:intent|plan|attempt)\s+to\b"
    r"|\bnot\s+(?:intended|meant|expected|planned)\s+to\b"
    r"|不(?:会|应|应该|打算|计划)?\s*"
    r")(?:[\s-]+[A-Za-z]+){0,3}[\s-]*$",
    flags=re.IGNORECASE,
)


def automatic_keyword_is_negated(text: str, keyword_start: int) -> bool:
    boundary = max(
        text.rfind("\n", 0, keyword_start),
        text.rfind(".", 0, keyword_start),
        text.rfind(";", 0, keyword_start),
        text.rfind("。", 0, keyword_start),
        text.rfind("；", 0, keyword_start),
    )
    prefix = text[boundary + 1 : keyword_start].replace("’", "'")
    return bool(AUTOMATIC_NEGATION_RE.search(prefix))


def keyword_references(
    text: str,
    repository: str,
    keywords: str,
    *,
    negation_aware: bool = False,
) -> tuple[set[int], set[int]]:
    escaped_repository = re.escape(repository)
    token = (
        rf"(?:https://github\.com/{escaped_repository}/issues/\d+|"
        rf"{escaped_repository}#\d+|#\d+)"
    )
    separator = (
        r"(?:\s*(?:(?:,|、)\s*(?:(?:\band\b|\bor\b|以及|及|或)\s*)?"
        r"|&|\band\b|\bor\b|以及|及|或)\s*)"
    )
    pattern = re.compile(
        rf"(?:{keywords})\s*[:：]?\s*(?P<refs>{token}(?:{separator}{token})*)",
        flags=re.IGNORECASE,
    )
    references: set[int] = set()
    negated: set[int] = set()
    for match in pattern.finditer(text):
        matched_references = extract_local_references(match.group("refs"), repository)
        if negation_aware and automatic_keyword_is_negated(text, match.start()):
            negated.update(matched_references)
        else:
            references.update(matched_references)
    return references, negated


def classify_pr_references(text: str, repository: str, issue_numbers: set[int]) -> dict[str, tuple[int, ...]]:
    automatic, negated_automatic = keyword_references(
        text,
        repository,
        r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\b",
        negation_aware=True,
    )
    ordinary, _ = keyword_references(
        text,
        repository,
        r"\b(?:refs?|references?|supports?|related(?:\s+to)?|relates\s+to)\b",
    )
    ordinary = (ordinary | negated_automatic) - automatic
    all_references = extract_local_references(text, repository)
    unqualified = all_references - automatic - ordinary
    return {
        "automatic": tuple(sorted(automatic & issue_numbers)),
        "ordinary": tuple(sorted(ordinary & issue_numbers)),
        "negated_automatic": tuple(sorted(negated_automatic & issue_numbers)),
        "unqualified": tuple(sorted(unqualified & issue_numbers)),
        "unresolved": tuple(sorted(all_references - issue_numbers)),
    }


DEPENDENCY_HEADING_RE = re.compile(
    r"^(?:blocked\s+by|dependencies?|depends?\s+on|prerequisites?|"
    r"阻塞项|阻塞依赖|依赖|前置依赖|前置条件)\s*[:：]?\s*$",
    flags=re.IGNORECASE,
)
DEPENDENCY_INLINE_RE = re.compile(
    r"(?:\bblocked\s+by\b|\bdepends?\s+on\b|\bdependencies?\s*[:：]|"
    r"\bprerequisites?\s*[:：]|(?:阻塞于|阻塞项|阻塞依赖|依赖于|依赖|"
    r"前置依赖|前置条件)\s*[:：])",
    flags=re.IGNORECASE,
)


def extract_dependencies(body: str, repository: str) -> tuple[int, ...]:
    dependencies: set[int] = set()
    in_dependency_section = False
    for _, raw_line in visible_markdown_lines(body):
        line = raw_line.strip()
        heading = re.match(r"^#{1,6}\s+(.+?)\s*$", line)
        if heading:
            heading_text = heading.group(1).strip()
            inline_marker = DEPENDENCY_INLINE_RE.search(heading_text)
            in_dependency_section = bool(
                DEPENDENCY_HEADING_RE.fullmatch(heading_text) or inline_marker
            )
            if in_dependency_section:
                dependencies.update(extract_local_references(heading_text, repository))
            continue
        if in_dependency_section:
            dependencies.update(extract_local_references(line, repository))
        elif DEPENDENCY_INLINE_RE.search(line):
            dependencies.update(extract_local_references(line, repository))
    return tuple(sorted(dependencies))


def find_cycle_components(graph: dict[int, set[int]]) -> tuple[tuple[int, ...], ...]:
    index = 0
    indexes: dict[int, int] = {}
    low_links: dict[int, int] = {}
    stack: list[int] = []
    on_stack: set[int] = set()
    components: list[tuple[int, ...]] = []

    def visit(node: int) -> None:
        nonlocal index
        indexes[node] = index
        low_links[node] = index
        index += 1
        stack.append(node)
        on_stack.add(node)

        for target in sorted(graph.get(node, set())):
            if target not in graph:
                continue
            if target not in indexes:
                visit(target)
                low_links[node] = min(low_links[node], low_links[target])
            elif target in on_stack:
                low_links[node] = min(low_links[node], indexes[target])

        if low_links[node] != indexes[node]:
            return
        component: list[int] = []
        while True:
            target = stack.pop()
            on_stack.remove(target)
            component.append(target)
            if target == node:
                break
        if len(component) > 1 or node in graph.get(node, set()):
            components.append(tuple(sorted(component)))

    for node in sorted(graph):
        if node not in indexes:
            visit(node)
    return tuple(sorted(components))


def parse_github_time(value: Any, resource: str) -> datetime:
    timestamp = require_string(value, "timestamp", resource)
    try:
        parsed = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    except ValueError as exc:
        raise AuditError(f"GitHub returned an invalid timestamp for {resource}") from exc
    if parsed.tzinfo is None:
        raise AuditError(f"GitHub returned a timezone-less timestamp for {resource}")
    return parsed


def analyze(snapshot: Snapshot) -> dict[str, Any]:
    issues_by_number = {issue["number"]: issue for issue in snapshot.issues}
    all_issue_numbers = set(issues_by_number)
    open_issues = tuple(
        sorted(
            (issue for issue in snapshot.issues if issue["state"] == "open"),
            key=lambda issue: issue["number"],
        )
    )
    open_numbers = {issue["number"] for issue in open_issues}
    pr_numbers = {pr["number"] for pr in (*snapshot.open_prs, *snapshot.closed_prs)}

    issue_comment_count = 0
    open_issue_comment_count = 0
    pr_comment_count = 0
    for comment in snapshot.comments:
        match = ISSUE_URL_NUMBER_RE.search(comment["issue_url"])
        if match is None:
            raise AuditError("comment data contains an invalid Issue URL")
        number = int(match.group(1))
        if number in all_issue_numbers:
            issue_comment_count += 1
            if number in open_numbers:
                open_issue_comment_count += 1
        elif number in pr_numbers:
            pr_comment_count += 1
        else:
            raise AuditError("comment pagination referenced an unknown issue or pull request")

    any_label = tuple(issue["number"] for issue in open_issues if issue["labels"])
    no_label = tuple(issue["number"] for issue in open_issues if not issue["labels"])
    priority_labeled = tuple(
        issue["number"] for issue in open_issues if PRIORITY_LABELS.intersection(issue["labels"])
    )
    no_priority = tuple(
        issue["number"] for issue in open_issues if not PRIORITY_LABELS.intersection(issue["labels"])
    )
    type_labeled = tuple(
        issue["number"] for issue in open_issues if TYPE_LABELS.intersection(issue["labels"])
    )
    no_type = tuple(
        issue["number"] for issue in open_issues if not TYPE_LABELS.intersection(issue["labels"])
    )

    title_classes: dict[str, list[int]] = {}
    form_prefixes = tuple(form.title_prefix for form in snapshot.forms)
    for issue in open_issues:
        category = classify_title(issue["title"], form_prefixes)
        title_classes.setdefault(category, []).append(issue["number"])

    form_results: list[dict[str, Any]] = []
    matched_issue_numbers: set[int] = set()
    issues_by_form_path: dict[str, list[dict[str, Any]]] = {
        form.path: [] for form in snapshot.forms
    }
    for issue in open_issues:
        matching_forms = [
            form for form in snapshot.forms if issue["title"].startswith(form.title_prefix)
        ]
        if len(matching_forms) > 1:
            raise AuditError(
                f"Open issue #{issue['number']} matches more than one Issue Form title prefix"
            )
        if matching_forms:
            issues_by_form_path[matching_forms[0].path].append(issue)

    for form in snapshot.forms:
        matched = issues_by_form_path[form.path]
        matched_numbers = tuple(issue["number"] for issue in matched)
        matched_issue_numbers.update(matched_numbers)
        field_results: list[dict[str, Any]] = []
        for field in form.fields:
            missing: list[int] = []
            for issue in matched:
                sections = extract_form_sections(issue["body"])
                if not response_present(sections.get(field.label, ())):
                    missing.append(issue["number"])
            field_results.append(
                {
                    "id": field.field_id,
                    "label": field.label,
                    "required": field.required,
                    "missing": tuple(missing),
                }
            )
        form_results.append(
            {
                "path": form.path,
                "name": form.name,
                "prefix": form.title_prefix,
                "matched": matched_numbers,
                "fields": tuple(field_results),
            }
        )

    unassigned = tuple(issue["number"] for issue in open_issues if not issue["assignees"])
    assigned = tuple(issue["number"] for issue in open_issues if issue["assignees"])

    merged_prs: list[tuple[datetime, dict[str, Any]]] = []
    for pr in snapshot.closed_prs:
        if pr["merged_at"] is not None:
            merged_prs.append(
                (parse_github_time(pr["merged_at"], f"pull request #{pr['number']}"), pr)
            )
    merged_prs.sort(key=lambda item: (item[0], item[1]["number"]), reverse=True)
    recent_prs: list[dict[str, Any]] = []
    for merged_at, pr in merged_prs[:10]:
        references = classify_pr_references(
            f"{pr['title']}\n{pr['body']}", snapshot.repository, all_issue_numbers
        )
        recent_prs.append(
            {
                "number": pr["number"],
                "merged_at": merged_at.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                **references,
            }
        )

    dependency_map = {
        issue["number"]: extract_dependencies(issue["body"], snapshot.repository)
        for issue in snapshot.issues
    }
    blocked_issues = tuple(
        issue for issue in open_issues if BLOCKED_LABEL in set(issue["labels"])
    )
    blocker_results: list[dict[str, Any]] = []
    for issue in blocked_issues:
        dependencies = dependency_map[issue["number"]]
        blocker_results.append(
            {
                "number": issue["number"],
                "dependencies": dependencies,
                "open": tuple(
                    number
                    for number in dependencies
                    if number in issues_by_number and issues_by_number[number]["state"] == "open"
                ),
                "closed": tuple(
                    number
                    for number in dependencies
                    if number in issues_by_number and issues_by_number[number]["state"] == "closed"
                ),
                "missing": tuple(number for number in dependencies if number not in issues_by_number),
            }
        )

    open_dependency_graph = {
        issue["number"]: {
            number for number in dependency_map[issue["number"]] if number in open_numbers
        }
        for issue in open_issues
    }
    blocked_numbers = {issue["number"] for issue in blocked_issues}
    blocker_cycles = tuple(
        component
        for component in find_cycle_components(open_dependency_graph)
        if blocked_numbers.intersection(component)
    )

    milestone_issue_numbers: dict[int, list[int]] = {
        milestone["number"]: [] for milestone in snapshot.milestones
    }
    without_milestone: list[int] = []
    for issue in open_issues:
        milestone = issue["milestone"]
        if milestone is None:
            without_milestone.append(issue["number"])
            continue
        milestone_number = milestone["number"]
        if milestone_number not in milestone_issue_numbers:
            raise AuditError("an issue referenced a milestone absent from milestone pagination")
        milestone_issue_numbers[milestone_number].append(issue["number"])

    return {
        "open_issues": open_issues,
        "issue_comment_count": issue_comment_count,
        "open_issue_comment_count": open_issue_comment_count,
        "pr_comment_count": pr_comment_count,
        "labels": {
            "any": any_label,
            "none": no_label,
            "priority": priority_labeled,
            "no_priority": no_priority,
            "type": type_labeled,
            "no_type": no_type,
        },
        "title_classes": {name: tuple(numbers) for name, numbers in title_classes.items()},
        "forms": tuple(form_results),
        "unmatched_forms": tuple(sorted(open_numbers - matched_issue_numbers)),
        "assigned": assigned,
        "unassigned": unassigned,
        "recent_prs": tuple(recent_prs),
        "merged_pr_count": len(merged_prs),
        "blockers": tuple(blocker_results),
        "blocker_cycles": blocker_cycles,
        "milestone_issue_numbers": {
            number: tuple(numbers) for number, numbers in milestone_issue_numbers.items()
        },
        "without_milestone": tuple(without_milestone),
    }


def number_list(numbers: Iterable[int]) -> str:
    values = sorted(set(numbers))
    return ", ".join(f"#{number}" for number in values) if values else "(none)"


def percentage(count: int, total: int) -> str:
    return f"{(100.0 * count / total) if total else 0.0:.1f}%"


def inline_code(value: str) -> str:
    safe = " ".join(value.replace("`", "'").split())
    return f"`{safe}`"


def exact_string_code(value: str) -> str:
    """Render whitespace-significant configuration text unambiguously."""

    encoded = json.dumps(value, ensure_ascii=False).replace("`", "'")
    return f"`{encoded}`"


def render_report(snapshot: Snapshot, result: dict[str, Any], generated_at: datetime) -> str:
    if generated_at.tzinfo is None:
        raise AuditError("report generation time must include a timezone")
    generated = generated_at.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )
    open_issues = result["open_issues"]
    total = len(open_issues)
    labels = result["labels"]
    lines = [
        "# GitHub Issue Health Audit",
        "",
        "- Status: COMPLETE",
        f"- Generated: {generated}",
        f"- Repository: {inline_code(snapshot.repository)}",
        f"- Default branch queried for Issue Forms: {inline_code(snapshot.default_branch)}",
        "- Data source: GitHub REST API through authenticated `gh api` read-only requests",
        "- Query scope: every Issue, Issue comment, label, milestone, open PR, and closed PR; "
        "the recent-PR section is selected after sorting every merged PR by `merged_at`",
        "- Privacy boundary: the report emits repository metadata, configuration names, counts, "
        "and GitHub numbers only; it never emits Issue, PR, or comment bodies or titles",
        "",
        "## Snapshot",
        "",
        f"- Open Issues: {total}",
        f"- All Issues fetched: {len(snapshot.issues)}",
        f"- Issue comments fetched: {result['issue_comment_count']} "
        f"({result['open_issue_comment_count']} on current Open Issues)",
        f"- PR conversation comments filtered from the shared Issue-comments endpoint: "
        f"{result['pr_comment_count']}",
        f"- Open PRs: {len(snapshot.open_prs)}; numbers: "
        f"{number_list(pr['number'] for pr in snapshot.open_prs)}",
        f"- Merged PRs found after full closed-PR pagination: {result['merged_pr_count']}",
        f"- Issue Forms fetched from the default branch: {len(snapshot.forms)}",
        "- Pagination pages: "
        + ", ".join(f"{name}={count}" for name, count in sorted(snapshot.pages.items())),
        "",
        "## Label Coverage",
        "",
        f"- Any label: {len(labels['any'])}/{total} ({percentage(len(labels['any']), total)})",
        f"- No label: {number_list(labels['none'])}",
        "- Priority classification uses exact labels: "
        + ", ".join(inline_code(label) for label in sorted(PRIORITY_LABELS)),
    ]
    lines.extend(
        [
            f"- Priority coverage: {len(labels['priority'])}/{total} "
            f"({percentage(len(labels['priority']), total)}); missing: "
            f"{number_list(labels['no_priority'])}",
            "- Type classification uses exact labels: "
            + ", ".join(inline_code(label) for label in sorted(TYPE_LABELS)),
            f"- Type coverage: {len(labels['type'])}/{total} "
            f"({percentage(len(labels['type']), total)}); missing: {number_list(labels['no_type'])}",
            "- Repository label definitions absent from the configured priority/type sets: "
            + ", ".join(
                inline_code(label)
                for label in sorted((PRIORITY_LABELS | TYPE_LABELS) - set(snapshot.labels))
            )
            if (PRIORITY_LABELS | TYPE_LABELS) - set(snapshot.labels)
            else "- All configured priority/type labels exist in the repository label catalog.",
            "",
            "Having any label is not equivalent to having both a priority and a type label.",
            "",
            "## Title Prefix Classification",
            "",
            "Rules are applied in this exact order: full-width `【P#】【type】`, ASCII "
            "`[P#][type]`, priority-only variants, exact current Issue Form title prefixes, "
            "other bracketed prefixes, then no recognized prefix.",
            "",
        ]
    )
    title_order = (
        "full-width priority + type",
        "ASCII priority + type",
        "full-width priority only",
        "ASCII priority only",
        "exact current Issue Form prefix",
        "other bracketed prefix",
        "no recognized prefix",
    )
    for category in title_order:
        numbers = result["title_classes"].get(category, ())
        lines.append(f"- {category}: {len(numbers)}; Issues: {number_list(numbers)}")
    lines.extend(
        [
            "",
            "This prefix inventory is governance evidence only. Chinese/English text in a title "
            "does not prove that any product surface is localized.",
            "",
            "## Issue Form Adherence",
            "",
            "Deterministic population rule: audit every current Open Issue whose title starts "
            "with exactly one current Issue Form `title` prefix. No random sample is used. "
            "Unmatched Issues are reported separately as manual, historical, or differently "
            "prefixed and are not treated as proof of Form noncompliance.",
            "",
        ]
    )
    for form in result["forms"]:
        lines.extend(
            [
                f"### {inline_code(form['path'])}",
                "",
                f"- Form name: {inline_code(form['name'])}",
                f"- Exact title prefix: {exact_string_code(form['prefix'])}",
                f"- Matched Open Issues ({len(form['matched'])}): {number_list(form['matched'])}",
            ]
        )
        for field in form["fields"]:
            requirement = "required" if field["required"] else "optional"
            if not form["matched"]:
                lines.append(
                    f"- Field {inline_code(field['id'])} ({requirement}), "
                    f"label {inline_code(field['label'])}: not assessed because no Open Issue "
                    "matched this Form's exact title prefix"
                )
                continue
            missing_kind = "missing responses" if field["required"] else "not provided (informational)"
            lines.append(
                f"- Field {inline_code(field['id'])} ({requirement}), "
                f"label {inline_code(field['label'])}: {missing_kind}: "
                f"{number_list(field['missing'])}"
            )
        lines.append("")
    lines.extend(
        [
            f"- Unmatched manual/historical/differently prefixed Open Issues "
            f"({len(result['unmatched_forms'])}): {number_list(result['unmatched_forms'])}",
            "- API limitation: GitHub does not expose which Form version created an Issue. "
            "This audit compares current headings with current default-branch Forms and does not "
            "claim historical requiredness.",
            "",
            "## Assignee Coverage",
            "",
            f"- Assigned: {len(result['assigned'])}/{total} "
            f"({percentage(len(result['assigned']), total)})",
            f"- Unassigned: {number_list(result['unassigned'])}",
            f"- The exact {inline_code(BLOCKED_LABEL)} label is a workflow state, not an assignee.",
            "",
            "## Recent 10 Merged PRs and Issue References",
            "",
            "Selection rule: fully paginate closed PRs, discard entries with null `merged_at`, "
            "sort by `merged_at` descending (PR number descending as the deterministic tie-break), "
            "then select 10.",
            "Negated close phrases are reported separately and treated as ordinary relations, "
            "not automatic close intent.",
            "",
        ]
    )
    for pr in result["recent_prs"]:
        has_link = bool(pr["automatic"] or pr["ordinary"] or pr["unqualified"])
        lines.extend(
            [
                f"- PR #{pr['number']} merged {pr['merged_at']}: "
                f"auto-close={number_list(pr['automatic'])}; "
                f"ordinary relation={number_list(pr['ordinary'])}; "
                f"negated close statement={number_list(pr['negated_automatic'])}; "
                f"unqualified local Issue reference={number_list(pr['unqualified'])}; "
                f"unresolved local number={number_list(pr['unresolved'])}; "
                f"Issue reference present={'yes' if has_link else 'no'}",
            ]
        )
    if not result["recent_prs"]:
        lines.append("- No merged PRs were returned.")

    lines.extend(
        [
            "",
            "## Blocked Issue Dependencies",
            "",
            f"Only current Open Issues carrying the exact label {inline_code(BLOCKED_LABEL)} "
            "are counted. Dependency numbers are extracted only from explicit dependency "
            "headings or same-line markers such as `Blocked by`, `Depends on`, `Dependencies:`, "
            "`阻塞项`, `依赖：`, or `前置依赖：`.",
            "",
            f"- Blocked Open Issues ({len(result['blockers'])}): "
            f"{number_list(blocker['number'] for blocker in result['blockers'])}",
        ]
    )
    for blocker in result["blockers"]:
        lines.append(
            f"- #{blocker['number']}: dependencies={number_list(blocker['dependencies'])}; "
            f"open={number_list(blocker['open'])}; closed/stale={number_list(blocker['closed'])}; "
            f"missing/non-Issue={number_list(blocker['missing'])}; "
            f"numbered reason={'yes' if blocker['dependencies'] else 'no'}"
        )
    lines.append(
        "- Blocked Issues without a numbered dependency/reason: "
        + number_list(
            blocker["number"] for blocker in result["blockers"] if not blocker["dependencies"]
        )
    )
    if result["blocker_cycles"]:
        lines.append(
            "- Potential open dependency cycle components: "
            + "; ".join(number_list(component) for component in result["blocker_cycles"])
        )
    else:
        lines.append("- Potential open dependency cycle components: (none)")
    lines.extend(
        [
            "- GitHub's snapshot API does not provide the time when a label was first added. "
            "Created time is therefore not used as a false blocked-duration estimate.",
            "",
            "## Milestones",
            "",
        ]
    )
    for milestone in sorted(snapshot.milestones, key=lambda item: item["number"]):
        numbers = result["milestone_issue_numbers"][milestone["number"]]
        lines.append(
            f"- {inline_code(milestone['title'])} (#{milestone['number']}, "
            f"{milestone['state']}): Open Issues={len(numbers)}; Issues: {number_list(numbers)}"
        )
    lines.extend(
        [
            f"- Open Issues without a milestone: {number_list(result['without_milestone'])}",
            "- A milestone is scheduling state, not a permanent classification label.",
            "",
            "## Completeness and Limits",
            "",
            "- All list endpoints use `per_page=100` plus `gh api --paginate`; duplicate IDs, "
            "invalid JSON, missing required API fields, unknown comment targets, malformed Forms, "
            "or failed requests abort the audit.",
            "- Issue and PR bodies are read only where dependency, Form-heading, or linkage "
            "classification requires them. Comment bodies are projected out by `gh` before Python "
            "receives the paginated JSON. No body or title is written to the report.",
            "- The report is a current snapshot, not historical trend data and not GitHub "
            "automation. It never creates, edits, labels, assigns, comments on, closes, or merges "
            "GitHub objects.",
            "- For file output, the complete report is written to a temporary file in the target "
            "directory, flushed, and atomically replaced only after every read and analysis passes.",
            "",
        ]
    )
    return "\n".join(lines)


def atomic_write_text(path: Path, content: str) -> None:
    parent = path.parent
    if not parent.is_dir():
        raise AuditError("output directory does not exist")
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            prefix=f".{path.name}.",
            suffix=".tmp",
            dir=parent,
            delete=False,
        ) as handle:
            temporary_path = Path(handle.name)
            handle.write(content)
            if not content.endswith("\n"):
                handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
        temporary_path = None
    except OSError as exc:
        raise AuditError("complete report could not be written atomically") from exc
    finally:
        if temporary_path is not None:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Read GitHub governance data and emit a fail-closed Issue health audit."
    )
    parser.add_argument(
        "--repo",
        default=DEFAULT_REPOSITORY,
        help=f"GitHub repository in owner/name form (default: {DEFAULT_REPOSITORY})",
    )
    parser.add_argument(
        "--output",
        default="-",
        help="Output path written atomically, or - for stdout (default: -)",
    )
    return parser


def configure_utf8_standard_streams() -> None:
    """Make redirected and console output deterministic on Windows."""

    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            try:
                reconfigure(encoding="utf-8", errors="strict")
            except (OSError, ValueError) as exc:
                raise AuditError("standard streams could not be configured for UTF-8") from exc


def main(argv: Sequence[str] | None = None) -> int:
    try:
        configure_utf8_standard_streams()
        arguments = build_parser().parse_args(argv)
        repository = validate_repository(arguments.repo)
        snapshot = fetch_snapshot(repository, GhApi())
        result = analyze(snapshot)
        report = render_report(snapshot, result, datetime.now(timezone.utc))
        if arguments.output == "-":
            sys.stdout.write(report)
            if not report.endswith("\n"):
                sys.stdout.write("\n")
        else:
            atomic_write_text(Path(arguments.output), report)
    except AuditError as exc:
        print(f"ERROR: audit incomplete; no report written: {exc}", file=sys.stderr)
        return 1
    except Exception:
        # Unexpected exceptions remain fail-closed without leaking local paths,
        # environment values, API payloads, or credentials.
        print("ERROR: audit incomplete; no report written: unexpected internal failure", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
