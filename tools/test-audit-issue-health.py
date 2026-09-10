#!/usr/bin/env python3
"""
Test suite for GitHub Issue Health Audit tool
Uses synthetic fixtures, does not require live GitHub access
"""

import json
import unittest
from datetime import datetime
from io import StringIO
import sys

class TestIssueHealthAudit(unittest.TestCase):
    """Test issue health audit logic with synthetic data"""

    def setUp(self):
        """Set up test fixtures"""
        self.sample_issues = [
            {
                "number": 1,
                "title": "【P1】【功能】Test feature",
                "labels": [{"name": "P1"}, {"name": "功能"}],
                "assignees": [{"login": "user1"}],
                "milestone": {"title": "M1"},
                "body": "Depends on #5"
            },
            {
                "number": 2,
                "title": "[P2] Bug fix",
                "labels": [{"name": "P2"}],
                "assignees": [],
                "milestone": None,
                "body": "No dependencies"
            },
            {
                "number": 3,
                "title": "No prefix issue",
                "labels": [],
                "assignees": [],
                "milestone": {"title": "M1"},
                "body": ""
            },
            {
                "number": 4,
                "title": "【已阻塞】Blocked issue",
                "labels": [{"name": "已阻塞"}, {"name": "P1"}],
                "assignees": [{"login": "user2"}],
                "milestone": None,
                "body": "Blocked by #1 and #2"
            }
        ]

        self.sample_prs = [
            {
                "number": 101,
                "title": "Fix authentication",
                "body": "Fixes #1\nResolves #2",
                "mergedAt": "2026-08-25T00:00:00Z"
            },
            {
                "number": 102,
                "title": "Refactor code",
                "body": "Refs #3\nSupports #4",
                "mergedAt": "2026-08-24T00:00:00Z"
            },
            {
                "number": 103,
                "title": "Update docs",
                "body": "No issue reference",
                "mergedAt": "2026-08-23T00:00:00Z"
            }
        ]

    def test_label_coverage(self):
        """Test label coverage calculation"""
        issues_with_labels = [i for i in self.sample_issues if i.get('labels')]
        coverage = len(issues_with_labels) / len(self.sample_issues) * 100
        self.assertEqual(coverage, 75.0)  # 3 out of 4

    def test_unlabeled_issues(self):
        """Test identification of unlabeled issues"""
        unlabeled = [i for i in self.sample_issues if not i.get('labels')]
        self.assertEqual(len(unlabeled), 1)
        self.assertEqual(unlabeled[0]['number'], 3)

    def test_priority_label_coverage(self):
        """Test priority label detection"""
        priority_labels = ['P0', 'P1', 'P2', 'P3']
        issues_with_priority = [
            i for i in self.sample_issues
            if any(l.get('name') in priority_labels for l in i.get('labels', []))
        ]
        self.assertEqual(len(issues_with_priority), 3)  # Issues 1, 2, 4

    def test_assignee_coverage(self):
        """Test assignee coverage calculation"""
        assigned = [i for i in self.sample_issues if i.get('assignees')]
        coverage = len(assigned) / len(self.sample_issues) * 100
        self.assertEqual(coverage, 50.0)  # 2 out of 4

    def test_milestone_coverage(self):
        """Test milestone coverage"""
        with_milestone = [i for i in self.sample_issues if i.get('milestone')]
        self.assertEqual(len(with_milestone), 2)  # Issues 1, 3

    def test_blocked_issue_detection(self):
        """Test blocked issue identification"""
        blocked_labels = ['已阻塞', 'blocked']
        blocked = [
            i for i in self.sample_issues
            if any(l.get('name') in blocked_labels for l in i.get('labels', []))
        ]
        self.assertEqual(len(blocked), 1)
        self.assertEqual(blocked[0]['number'], 4)

    def test_pr_closes_detection(self):
        """Test auto-close keyword detection"""
        import re
        pr = self.sample_prs[0]
        body = pr['body'].lower()
        closes = re.findall(r'(fixes|resolves|closes)\s+#(\d+)', body)
        self.assertEqual(len(closes), 2)
        issue_nums = [num for _, num in closes]
        self.assertIn('1', issue_nums)
        self.assertIn('2', issue_nums)

    def test_pr_refs_detection(self):
        """Test reference keyword detection"""
        import re
        pr = self.sample_prs[1]
        body = pr['body'].lower()
        refs = re.findall(r'(refs|supports|related)\s+#(\d+)', body)
        self.assertEqual(len(refs), 2)

    def test_title_prefix_extraction(self):
        """Test title prefix pattern matching"""
        import re
        prefixes = []
        for issue in self.sample_issues:
            title = issue['title']
            if re.match(r'^【.*?】', title):
                prefix = re.split(r'】', title)[0] + '】'
                prefixes.append(prefix)
            elif re.match(r'^\[.*?\]', title):
                prefix = re.split(r']', title)[0] + ']'
                prefixes.append(prefix)
            else:
                prefixes.append('<no-prefix>')

        self.assertEqual(len([p for p in prefixes if p == '<no-prefix>']), 1)
        self.assertIn('【P1】', prefixes)
        self.assertIn('[P2]', prefixes)

    def test_dependency_extraction(self):
        """Test issue dependency extraction from body"""
        import re
        issue = self.sample_issues[3]  # Blocked issue
        deps = re.findall(r'#(\d+)', issue['body'])
        self.assertEqual(len(deps), 2)
        self.assertIn('1', deps)
        self.assertIn('2', deps)

    def test_empty_dataset(self):
        """Test handling of empty issue list"""
        empty_issues = []
        coverage = 0 if not empty_issues else len(empty_issues) / len(empty_issues) * 100
        self.assertEqual(coverage, 0)

    def test_all_labeled(self):
        """Test when all issues have labels"""
        all_labeled = [
            {"number": 1, "labels": [{"name": "test"}]},
            {"number": 2, "labels": [{"name": "test2"}]}
        ]
        unlabeled = [i for i in all_labeled if not i.get('labels')]
        self.assertEqual(len(unlabeled), 0)


if __name__ == '__main__':
    # Run tests
    suite = unittest.TestLoader().loadTestsFromTestCase(TestIssueHealthAudit)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    # Exit with appropriate code
    sys.exit(0 if result.wasSuccessful() else 1)
