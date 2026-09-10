#!/usr/bin/env bash
# GitHub Issue Health Audit Tool
# Read-only audit for medcue-ios repository issue governance
# Windows-capable, requires GitHub CLI (gh)

set -euo pipefail

REPO="${1:-Gavin8233841/medcue-ios}"
OUTPUT_FILE="${2:-issue-health-audit-$(date +%Y%m%d-%H%M%S).md}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 GitHub Issue Health Audit${NC}"
echo -e "${BLUE}Repository: $REPO${NC}"
echo -e "${BLUE}Output: $OUTPUT_FILE${NC}"
echo ""

# Check gh CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ GitHub CLI (gh) not found. Please install from https://cli.github.com/${NC}"
    exit 1
fi

# Check authentication
if ! gh auth status &> /dev/null; then
    echo -e "${RED}❌ Not authenticated with GitHub. Run: gh auth login${NC}"
    exit 1
fi

echo -e "${GREEN}✅ GitHub CLI authenticated${NC}"
echo ""

# Fetch data
echo -e "${BLUE}📥 Fetching issue data...${NC}"

ISSUES_JSON=$(gh issue list --repo "$REPO" --state open --limit 500 --json number,title,labels,assignees,milestone,createdAt,updatedAt,body 2>&1) || {
    echo -e "${RED}❌ Failed to fetch issues${NC}"
    echo "$ISSUES_JSON"
    exit 1
}

MERGED_PRS_JSON=$(gh pr list --repo "$REPO" --state merged --limit 10 --json number,title,mergedAt,body 2>&1) || {
    echo -e "${RED}❌ Failed to fetch PRs${NC}"
    echo "$MERGED_PRS_JSON"
    exit 1
}

echo -e "${GREEN}✅ Data fetched successfully${NC}"
echo ""

# Generate report header
{
cat << HEADER
# GitHub Issue Health Audit Report

**Generated**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Repository**: $REPO
**Tool**: tools/audit-issue-health.sh
**Data Source**: GitHub API via gh CLI
**Scope**: Open issues and last 10 merged PRs

---

## Executive Summary

HEADER

# Parse data with Python
python3 << PYTHON_SCRIPT
import json
import sys
import re
from datetime import datetime
from collections import defaultdict

# Load data
try:
    issues = json.loads('''$ISSUES_JSON''')
    merged_prs = json.loads('''$MERGED_PRS_JSON''')
except json.JSONDecodeError as e:
    print(f"ERROR: Failed to parse JSON: {e}", file=sys.stderr)
    sys.exit(1)

total_issues = len(issues)

# 1. Label coverage
issues_with_labels = [i for i in issues if i.get('labels')]
issues_without_labels = [i for i in issues if not i.get('labels')]
label_coverage = len(issues_with_labels) / total_issues * 100 if total_issues > 0 else 0

# Priority labels
priority_labels = ['P0', 'P1', 'P2', 'P3']
issues_with_priority = [i for i in issues if any(l.get('name') in priority_labels for l in i.get('labels', []))]
priority_coverage = len(issues_with_priority) / total_issues * 100 if total_issues > 0 else 0

# Type labels (common types)
type_labels = ['功能', '治理', '技术债务', '文档']
issues_with_type = [i for i in issues if any(l.get('name') in type_labels for l in i.get('labels', []))]
type_coverage = len(issues_with_type) / total_issues * 100 if total_issues > 0 else 0

# 2. Title prefix analysis
title_patterns = defaultdict(list)
for issue in issues:
    title = issue.get('title', '')
    # Match patterns like 【P1】【功能】 or [P1][Feature]
    if re.match(r'^【.*?】', title) or re.match(r'^\[.*?\]', title):
        prefix = re.split(r'】|]', title)[0] + ('】' if '【' in title else ']')
        title_patterns[prefix].append(issue['number'])
    else:
        title_patterns['<no-prefix>'].append(issue['number'])

# 3. Assignee coverage
issues_with_assignees = [i for i in issues if i.get('assignees')]
issues_without_assignees = [i for i in issues if not i.get('assignees')]
assignee_coverage = len(issues_with_assignees) / total_issues * 100 if total_issues > 0 else 0

# 4. Milestone coverage
issues_with_milestone = [i for i in issues if i.get('milestone')]
issues_without_milestone = [i for i in issues if not i.get('milestone')]
milestone_coverage = len(issues_with_milestone) / total_issues * 100 if total_issues > 0 else 0

milestones = defaultdict(list)
for issue in issues_with_milestone:
    ms = issue['milestone']['title']
    milestones[ms].append(issue['number'])

# 5. Blocked issues
blocked_label_names = ['已阻塞', 'blocked']
blocked_issues = [i for i in issues if any(l.get('name') in blocked_label_names for l in i.get('labels', []))]

# Parse blocking dependencies
blocked_analysis = []
for issue in blocked_issues:
    body = issue.get('body', '')
    # Find issue references like #N
    deps = re.findall(r'#(\d+)', body)
    blocked_analysis.append({
        'number': issue['number'],
        'title': issue['title'],
        'deps': deps
    })

# 6. PR-Issue linkage
pr_issue_links = []
closes_keywords = ['closes', 'fixes', 'resolves', 'close', 'fix', 'resolve']
refs_keywords = ['refs', 'references', 'supports', 'related', 'ref', 'support', 'relates']

for pr in merged_prs:
    body = pr.get('body', '').lower()
    closes = []
    refs = []

    # Find issue links
    for match in re.finditer(r'(closes|fixes|resolves|close|fix|resolve|refs|references|supports|related|ref|support|relates)\s+#(\d+)', body):
        keyword, issue_num = match.groups()
        if keyword in closes_keywords:
            closes.append(issue_num)
        elif keyword in refs_keywords:
            refs.append(issue_num)

    pr_issue_links.append({
        'number': pr['number'],
        'title': pr['title'],
        'closes': closes,
        'refs': refs,
        'has_link': bool(closes or refs)
    })

# Write summary
print(f"- **Total Open Issues**: {total_issues}")
print(f"- **Label Coverage**: {label_coverage:.1f}% ({len(issues_with_labels)}/{total_issues})")
print(f"- **Priority Label Coverage**: {priority_coverage:.1f}% ({len(issues_with_priority)}/{total_issues})")
print(f"- **Type Label Coverage**: {type_coverage:.1f}% ({len(issues_with_type)}/{total_issues})")
print(f"- **Assignee Coverage**: {assignee_coverage:.1f}% ({len(issues_with_assignees)}/{total_issues})")
print(f"- **Milestone Coverage**: {milestone_coverage:.1f}% ({len(issues_with_milestone)}/{total_issues})")
print(f"- **Blocked Issues**: {len(blocked_issues)}")
print(f"- **Issues Without Labels**: {len(issues_without_labels)}")
print(f"- **Issues Without Assignees**: {len(issues_without_assignees)}")
print()

# Detailed sections
print("---\n")
print("## 1. Label Analysis\n")
print(f"### Coverage\n")
print(f"- **Total issues with any label**: {len(issues_with_labels)} ({label_coverage:.1f}%)")
print(f"- **Issues with priority labels** (P0/P1/P2/P3): {len(issues_with_priority)} ({priority_coverage:.1f}%)")
print(f"- **Issues with type labels**: {len(issues_with_type)} ({type_coverage:.1f}%)")
print()
print("### Issues Without Any Labels\n")
if issues_without_labels:
    for issue in issues_without_labels:
        print(f"- #{issue['number']}: {issue['title']}")
else:
    print("✅ All issues have at least one label")
print()

print("---\n")
print("## 2. Title Prefix Analysis\n")
print("### Prefix Distribution\n")
for prefix, issue_nums in sorted(title_patterns.items(), key=lambda x: -len(x[1])):
    print(f"- **{prefix}**: {len(issue_nums)} issues - {', '.join(f'#{n}' for n in sorted(issue_nums)[:5])}{'...' if len(issue_nums) > 5 else ''}")
print()

print("---\n")
print("## 3. Assignee Analysis\n")
print(f"### Coverage: {assignee_coverage:.1f}%\n")
print(f"- **Assigned**: {len(issues_with_assignees)}")
print(f"- **Unassigned**: {len(issues_without_assignees)}")
print()
print("### Unassigned Issues\n")
if issues_without_assignees:
    for issue in issues_without_assignees[:20]:
        print(f"- #{issue['number']}: {issue['title']}")
    if len(issues_without_assignees) > 20:
        print(f"- ... and {len(issues_without_assignees) - 20} more")
else:
    print("✅ All issues are assigned")
print()

print("---\n")
print("## 4. Milestone Analysis\n")
print(f"### Coverage: {milestone_coverage:.1f}%\n")
print("### Milestones\n")
for ms, issue_nums in sorted(milestones.items()):
    print(f"- **{ms}**: {len(issue_nums)} issues")
print()
print("### Issues Without Milestone\n")
if issues_without_milestone:
    for issue in issues_without_milestone[:20]:
        print(f"- #{issue['number']}: {issue['title']}")
    if len(issues_without_milestone) > 20:
        print(f"- ... and {len(issues_without_milestone) - 20} more")
else:
    print("✅ All issues have milestones")
print()

print("---\n")
print("## 5. Blocked Issues Analysis\n")
print(f"### Total Blocked: {len(blocked_issues)}\n")
for blocked in blocked_analysis:
    print(f"### #{blocked['number']}: {blocked['title']}\n")
    print(f"- **Referenced issues in body**: {', '.join(f'#{d}' for d in blocked['deps']) if blocked['deps'] else 'None found'}")
    print()

print("---\n")
print("## 6. PR-Issue Linkage (Last 10 Merged PRs)\n")
for pr in pr_issue_links:
    print(f"### PR #{pr['number']}: {pr['title']}\n")
    if pr['closes']:
        print(f"- **Auto-closes** (Closes/Fixes/Resolves): {', '.join(f'#{i}' for i in pr['closes'])}")
    if pr['refs']:
        print(f"- **References** (Refs/Supports/Related): {', '.join(f'#{i}' for i in pr['refs'])}")
    if not pr['has_link']:
        print("- ⚠️ **No issue reference found**")
    print()

print("---\n")
print("## Data Limitations\n")
print("- Issue Form field compliance requires manual review of issue templates")
print("- Blocked issue duration not available via API (would require webhook/action)")
print("- Circular dependency detection is pattern-based, not graph-validated")
print("- This tool is read-only and makes no modifications to GitHub state")
print()
print("## Recommendations\n")
print(f"1. Add labels to {len(issues_without_labels)} unlabeled issues")
print(f"2. Assign {len(issues_without_assignees)} unassigned issues")
print(f"3. Review {len(blocked_issues)} blocked issues for stale dependencies")
print(f"4. Consider milestones for {len(issues_without_milestone)} issues")

PYTHON_SCRIPT
} > "$OUTPUT_FILE"

echo ""
echo -e "${GREEN}✅ Report generated: $OUTPUT_FILE${NC}"
echo ""
echo "View with: cat $OUTPUT_FILE"
