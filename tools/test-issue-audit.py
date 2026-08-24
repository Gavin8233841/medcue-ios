#!/usr/bin/env python3
"""
GitHub Issue 审计工具的测试

使用合成 fixture 测试工具的各个功能，不依赖在线 GitHub 状态。
"""

import json
import sys
import unittest
from unittest.mock import Mock, patch, MagicMock
from io import StringIO
import os

# 添加 tools 目录到路径
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# 导入被测试的模块 - 需要使用文件名（去掉 .py 扩展）
import importlib.util
spec = importlib.util.spec_from_file_location(
    "audit_github_issues",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "audit-github-issues.py")
)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class TestIssueAuditor(unittest.TestCase):
    """测试 IssueAuditor 类"""

    def setUp(self):
        """设置测试 fixture"""
        self.mock_client = Mock(spec=audit.GitHubAPIClient)
        self.mock_client.repo = "test/repo"
        self.auditor = audit.IssueAuditor(self.mock_client)

    def test_audit_labels_with_complete_coverage(self):
        """测试完全覆盖的标签审计"""
        self.auditor.issues = [
            {
                'number': 1,
                'labels': [
                    {'name': 'P1'},
                    {'name': 'type:bug'}
                ]
            },
            {
                'number': 2,
                'labels': [
                    {'name': 'P2'},
                    {'name': 'type:feature'}
                ]
            }
        ]

        result = self.auditor.audit_labels()

        self.assertEqual(result['total'], 2)
        self.assertEqual(result['with_any_label'], 2)
        self.assertEqual(result['without_label'], [])
        self.assertEqual(result['with_priority'], 2)
        self.assertEqual(result['with_type'], 2)

    def test_audit_labels_with_missing_labels(self):
        """测试缺少标签的情况"""
        self.auditor.issues = [
            {
                'number': 1,
                'labels': [{'name': 'P1'}]
            },
            {
                'number': 2,
                'labels': [{'name': 'type:bug'}]
            },
            {
                'number': 3,
                'labels': []
            }
        ]

        result = self.auditor.audit_labels()

        self.assertEqual(result['total'], 3)
        self.assertEqual(result['with_any_label'], 2)
        self.assertEqual(result['without_label'], [3])
        self.assertEqual(result['with_priority'], 1)
        self.assertEqual(result['with_type'], 1)

    def test_audit_labels_distinguishes_priority_and_type(self):
        """测试区分优先级和类型标签"""
        self.auditor.issues = [
            {
                'number': 1,
                'labels': [{'name': 'documentation'}]  # 有标签，但既不是优先级也不是明确的类型
            }
        ]

        result = self.auditor.audit_labels()

        self.assertEqual(result['with_any_label'], 1)
        self.assertEqual(result['with_priority'], 0)
        self.assertEqual(result['with_type'], 0)

    def test_audit_titles_with_various_prefixes(self):
        """测试各种标题前缀"""
        self.auditor.issues = [
            {'number': 1, 'title': '[P1][Bug] Fix crash'},
            {'number': 2, 'title': '【P2】【功能】添加搜索'},
            {'number': 3, 'title': 'Feature: Add search'},
            {'number': 4, 'title': 'No prefix title'},
        ]

        result = self.auditor.audit_titles()

        self.assertIn('[P1]', result)
        self.assertIn('【P2】', result)
        self.assertIn('Feature:', result)
        self.assertIn('无前缀', result)
        self.assertEqual(result['无前缀'], [4])

    def test_audit_assignees(self):
        """测试负责人审计"""
        self.auditor.issues = [
            {
                'number': 1,
                'assignees': [{'login': 'user1'}]
            },
            {
                'number': 2,
                'assignees': []
            },
            {
                'number': 3,
                'assignees': None
            }
        ]

        result = self.auditor.audit_assignees()

        self.assertEqual(result['total'], 3)
        self.assertEqual(result['with_assignee'], 1)
        self.assertIn(2, result['without_assignee'])
        self.assertIn(3, result['without_assignee'])

    def test_extract_issue_refs_auto_close(self):
        """测试提取自动关闭的 Issue 引用"""
        text = """
        This PR fixes #123 and closes #456.
        Also resolves #789.
        """

        refs = self.auditor._extract_issue_refs(text, audit.IssueAuditor.AUTO_CLOSE_KEYWORDS)

        self.assertEqual(refs, {123, 456, 789})

    def test_extract_issue_refs_reference_only(self):
        """测试提取普通关联的 Issue 引用"""
        text = """
        This PR refs #111 and is related to #222.
        See also #333.
        """

        refs = self.auditor._extract_issue_refs(text, audit.IssueAuditor.REFERENCE_KEYWORDS)

        self.assertEqual(refs, {111, 222, 333})

    def test_extract_issue_refs_case_insensitive(self):
        """测试大小写不敏感的引用提取"""
        text = "FIXES #100, Closes #200, closes: #300"

        refs = self.auditor._extract_issue_refs(text, audit.IssueAuditor.AUTO_CLOSE_KEYWORDS)

        self.assertEqual(refs, {100, 200, 300})

    def test_audit_pr_references(self):
        """测试 PR 引用审计"""
        self.auditor.recent_prs = [
            {
                'number': 1,
                'title': 'Fix bug',
                'body': 'Fixes #10\nRefs #20',
                'merged_at': '2026-01-01T00:00:00Z'
            },
            {
                'number': 2,
                'title': 'Add feature',
                'body': None,
                'merged_at': '2026-01-02T00:00:00Z'
            }
        ]

        result = self.auditor.audit_pr_references()

        self.assertEqual(len(result), 2)
        self.assertTrue(result[0]['has_reference'])
        self.assertEqual(result[0]['auto_close'], [10])
        self.assertEqual(result[0]['reference_only'], [20])
        self.assertFalse(result[1]['has_reference'])

    def test_extract_blocking_dependencies(self):
        """测试提取阻塞依赖"""
        body = """
        This issue is blocked by #10 and depends on #20.
        Waiting for #30.
        阻塞于 #40
        依赖 #50
        """

        deps = self.auditor._extract_blocking_dependencies(body)

        self.assertEqual(set(deps), {10, 20, 30, 40, 50})

    def test_audit_blocked_issues(self):
        """测试阻塞 Issue 审计"""
        self.auditor.issues = [
            {
                'number': 1,
                'title': 'Blocked issue',
                'labels': [{'name': 'state:blocked'}],
                'body': 'Blocked by #10'
            },
            {
                'number': 2,
                'title': 'Blocked without deps',
                'labels': [{'name': 'state:blocked'}],
                'body': 'This is blocked but no deps mentioned'
            },
            {
                'number': 3,
                'title': 'Not blocked',
                'labels': [],
                'body': 'Regular issue'
            }
        ]

        # Mock _is_issue_closed
        self.auditor._is_issue_closed = Mock(return_value=True)

        result = self.auditor.audit_blocked_issues()

        self.assertEqual(result['total_blocked'], 2)
        self.assertEqual(len(result['issues']), 2)
        self.assertEqual(result['issues'][0]['dependencies'], [10])
        self.assertTrue(result['issues'][1]['missing_dependency_info'])

    def test_detect_dependency_cycles(self):
        """测试循环依赖检测"""
        blocked_issues = [
            {'number': 1, 'dependencies': [2]},
            {'number': 2, 'dependencies': [3]},
            {'number': 3, 'dependencies': [1]},  # 循环: 1 -> 2 -> 3 -> 1
            {'number': 4, 'dependencies': []},
        ]

        cycles = self.auditor._detect_dependency_cycles(blocked_issues)

        self.assertEqual(len(cycles), 1)
        # 循环应该包含 1, 2, 3
        cycle = cycles[0]
        self.assertIn(1, cycle)
        self.assertIn(2, cycle)
        self.assertIn(3, cycle)

    def test_audit_milestones(self):
        """测试 Milestone 审计"""
        self.auditor.issues = [
            {
                'number': 1,
                'milestone': {'title': 'v1.0'}
            },
            {
                'number': 2,
                'milestone': {'title': 'v1.0'}
            },
            {
                'number': 3,
                'milestone': {'title': 'v2.0'}
            },
            {
                'number': 4,
                'milestone': None
            }
        ]

        result = self.auditor.audit_milestones()

        self.assertEqual(result['total'], 4)
        self.assertEqual(result['with_milestone'], 3)
        self.assertEqual(result['without_milestone'], [4])
        self.assertEqual(result['milestone_breakdown']['v1.0'], 2)
        self.assertEqual(result['milestone_breakdown']['v2.0'], 1)


class TestGitHubAPIClient(unittest.TestCase):
    """测试 GitHubAPIClient 类"""

    @patch('audit_github_issues.subprocess.run')
    def test_verify_gh_cli_success(self, mock_run):
        """测试 gh CLI 验证成功"""
        mock_run.return_value = Mock(returncode=0)

        client = audit.GitHubAPIClient("test/repo")

        mock_run.assert_called_once()
        self.assertEqual(client.repo, "test/repo")

    @patch('audit_github_issues.subprocess.run')
    def test_verify_gh_cli_not_authenticated(self, mock_run):
        """测试 gh CLI 未认证"""
        mock_run.return_value = Mock(returncode=1)

        with self.assertRaises(audit.AuditError) as cm:
            audit.GitHubAPIClient("test/repo")

        self.assertIn("未认证", str(cm.exception))

    @patch('audit_github_issues.subprocess.run')
    def test_api_call_success(self, mock_run):
        """测试成功的 API 调用"""
        # Mock gh auth status
        mock_run.return_value = Mock(returncode=0, stdout='', stderr='')

        client = audit.GitHubAPIClient("test/repo")

        # Mock gh api call
        mock_run.return_value = Mock(
            returncode=0,
            stdout='{"test": "data"}'
        )

        result = client.api_call("/test/endpoint")

        self.assertEqual(result, {"test": "data"})

    @patch('audit_github_issues.subprocess.run')
    def test_api_call_failure(self, mock_run):
        """测试失败的 API 调用"""
        # Mock gh auth status
        mock_run.return_value = Mock(returncode=0, stdout='', stderr='')

        client = audit.GitHubAPIClient("test/repo")

        # Mock gh api call failure
        from subprocess import CalledProcessError
        mock_run.side_effect = CalledProcessError(1, 'gh', stderr='API error')

        with self.assertRaises(audit.AuditError) as cm:
            client.api_call("/test/endpoint")

        self.assertIn("API 调用失败", str(cm.exception))


class TestReportGeneration(unittest.TestCase):
    """测试报告生成"""

    def setUp(self):
        """设置测试"""
        self.mock_client = Mock(spec=audit.GitHubAPIClient)
        self.mock_client.repo = "test/repo"
        self.auditor = audit.IssueAuditor(self.mock_client)

    def test_generate_report_contains_sections(self):
        """测试报告包含所有必要的部分"""
        # 准备最小数据集
        self.auditor.issues = [
            {
                'number': 1,
                'title': '[P1] Test issue',
                'labels': [{'name': 'P1'}, {'name': 'type:bug'}],
                'assignees': [{'login': 'user1'}],
                'milestone': {'title': 'v1.0'},
                'body': ''
            }
        ]
        self.auditor.recent_prs = []

        report = self.auditor.generate_report()

        # 检查报告包含关键部分
        self.assertIn("GitHub Issue 健康度审计报告", report)
        self.assertIn("标签覆盖率", report)
        self.assertIn("标题前缀分类", report)
        self.assertIn("负责人覆盖率", report)
        self.assertIn("最近 10 个已合并 PR", report)
        self.assertIn("阻塞依赖分析", report)
        self.assertIn("Milestone 覆盖率", report)
        self.assertIn("test/repo", report)


def run_tests():
    """运行所有测试"""
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(run_tests())
