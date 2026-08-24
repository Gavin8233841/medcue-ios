#!/usr/bin/env python3
"""
GitHub Issue 健康度审计工具

只读工具，用于审计 GitHub Issue 的健康度状态。
不会修改任何 GitHub 远端状态。

使用方法:
    python tools/audit-github-issues.py --repo owner/name

要求:
    - Python 3.7+
    - gh CLI 已认证
    - 仓库读取权限

输出:
    结构化 Markdown 报告到 stdout
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Set, Tuple
from collections import defaultdict
import re


class AuditError(Exception):
    """审计过程中的错误"""
    pass


class GitHubAPIClient:
    """GitHub API 客户端（通过 gh CLI）"""

    def __init__(self, repo: str):
        self.repo = repo
        self._verify_gh_cli()

    def _verify_gh_cli(self) -> None:
        """验证 gh CLI 可用且已认证"""
        try:
            result = subprocess.run(
                ["gh", "auth", "status"],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode != 0:
                raise AuditError("gh CLI 未认证。请运行: gh auth login")
        except FileNotFoundError:
            raise AuditError("gh CLI 未安装。请从 https://cli.github.com/ 安装")
        except subprocess.TimeoutExpired:
            raise AuditError("gh CLI 响应超时")

    def api_call(self, endpoint: str, paginate: bool = False) -> Any:
        """调用 GitHub API"""
        cmd = ["gh", "api"]
        if paginate:
            cmd.append("--paginate")
        cmd.append(endpoint)

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=60,
                check=True
            )
            return json.loads(result.stdout)
        except subprocess.CalledProcessError as e:
            raise AuditError(f"API 调用失败 {endpoint}: {e.stderr}")
        except subprocess.TimeoutExpired:
            raise AuditError(f"API 调用超时 {endpoint}")
        except json.JSONDecodeError as e:
            raise AuditError(f"API 响应解析失败 {endpoint}: {e}")

    def get_open_issues(self) -> List[Dict]:
        """获取所有 Open Issues（不包括 PR）"""
        issues = self.api_call(f"/repos/{self.repo}/issues?state=open&per_page=100", paginate=True)
        # 过滤掉 Pull Requests
        return [issue for issue in issues if 'pull_request' not in issue]

    def get_recent_merged_prs(self, limit: int = 10) -> List[Dict]:
        """获取最近合并的 PR"""
        # 获取已关闭的 PR，按更新时间排序
        prs = self.api_call(
            f"/repos/{self.repo}/pulls?state=closed&sort=updated&direction=desc&per_page=100",
            paginate=False
        )
        # 过滤出已合并的 PR
        merged_prs = [pr for pr in prs if pr.get('merged_at')]
        # 按合并时间排序
        merged_prs.sort(key=lambda pr: pr['merged_at'], reverse=True)
        return merged_prs[:limit]

    def get_labels(self) -> List[Dict]:
        """获取仓库所有标签"""
        return self.api_call(f"/repos/{self.repo}/labels?per_page=100", paginate=True)

    def get_milestones(self) -> List[Dict]:
        """获取仓库所有 Milestones"""
        return self.api_call(f"/repos/{self.repo}/milestones?state=all&per_page=100", paginate=True)


class IssueAuditor:
    """Issue 审计器"""

    # 优先级标签前缀
    PRIORITY_PREFIXES = ['priority:', 'P0', 'P1', 'P2', 'P3']

    # 类型标签
    TYPE_LABELS = [
        'type:bug', 'type:feature', 'type:enhancement', 'type:documentation',
        'type:refactor', 'type:test', 'type:chore', 'governance', 'privacy',
        'security', 'performance', 'accessibility'
    ]

    # 自动关闭关键词
    AUTO_CLOSE_KEYWORDS = ['closes', 'close', 'closed', 'fix', 'fixes', 'fixed', 'resolve', 'resolves', 'resolved']

    # 普通关联关键词
    REFERENCE_KEYWORDS = ['refs', 'ref', 'references', 'related', 'supports', 'support', 'see']

    # 阻塞标签
    BLOCKED_LABEL = 'state:blocked'

    def __init__(self, client: GitHubAPIClient):
        self.client = client
        self.issues: List[Dict] = []
        self.labels: List[Dict] = []
        self.milestones: List[Dict] = []
        self.recent_prs: List[Dict] = []

    def fetch_data(self) -> None:
        """获取所有需要的数据"""
        print("正在获取 Issues...", file=sys.stderr)
        self.issues = self.client.get_open_issues()

        print("正在获取标签...", file=sys.stderr)
        self.labels = self.client.get_labels()

        print("正在获取 Milestones...", file=sys.stderr)
        self.milestones = self.client.get_milestones()

        print("正在获取最近合并的 PR...", file=sys.stderr)
        self.recent_prs = self.client.get_recent_merged_prs(10)

        print(f"数据获取完成: {len(self.issues)} 个 Open Issues", file=sys.stderr)

    def audit_labels(self) -> Dict[str, Any]:
        """审计标签覆盖率"""
        total = len(self.issues)
        with_any_label = []
        without_label = []
        with_priority = []
        with_type = []

        for issue in self.issues:
            issue_labels = [label['name'] for label in issue.get('labels', [])]
            issue_num = issue['number']

            if issue_labels:
                with_any_label.append(issue_num)
            else:
                without_label.append(issue_num)

            # 检查优先级标签
            if any(any(label.startswith(prefix) for prefix in self.PRIORITY_PREFIXES)
                   for label in issue_labels):
                with_priority.append(issue_num)

            # 检查类型标签
            if any(label in self.TYPE_LABELS or label.startswith('type:')
                   for label in issue_labels):
                with_type.append(issue_num)

        return {
            'total': total,
            'with_any_label': len(with_any_label),
            'without_label': without_label,
            'with_priority': len(with_priority),
            'with_type': len(with_type),
        }

    def audit_titles(self) -> Dict[str, List[int]]:
        """审计标题前缀"""
        # 提取所有标题前缀模式
        prefix_pattern = re.compile(r'^(\[.+?\]|\【.+?】|[A-Z][a-z]+:)')

        categories = defaultdict(list)

        for issue in self.issues:
            title = issue['title']
            match = prefix_pattern.match(title)

            if match:
                prefix = match.group(1)
                categories[prefix].append(issue['number'])
            else:
                categories['无前缀'].append(issue['number'])

        return dict(categories)

    def audit_assignees(self) -> Dict[str, Any]:
        """审计负责人覆盖率"""
        total = len(self.issues)
        with_assignee = []
        without_assignee = []

        for issue in self.issues:
            if issue.get('assignees'):
                with_assignee.append(issue['number'])
            else:
                without_assignee.append(issue['number'])

        return {
            'total': total,
            'with_assignee': len(with_assignee),
            'without_assignee': without_assignee,
        }

    def audit_pr_references(self) -> List[Dict[str, Any]]:
        """审计 PR 的 Issue 引用"""
        results = []

        for pr in self.recent_prs:
            pr_num = pr['number']
            pr_title = pr['title']
            pr_body = pr.get('body') or ''
            merged_at = pr['merged_at']

            # 组合标题和正文搜索 Issue 引用
            text = f"{pr_title}\n{pr_body}"

            auto_close_refs = self._extract_issue_refs(text, self.AUTO_CLOSE_KEYWORDS)
            reference_refs = self._extract_issue_refs(text, self.REFERENCE_KEYWORDS)

            has_any_ref = bool(auto_close_refs or reference_refs)

            results.append({
                'number': pr_num,
                'title': pr_title,
                'merged_at': merged_at,
                'has_reference': has_any_ref,
                'auto_close': sorted(auto_close_refs),
                'reference_only': sorted(reference_refs),
            })

        return results

    def _extract_issue_refs(self, text: str, keywords: List[str]) -> Set[int]:
        """从文本中提取 Issue 引用"""
        refs = set()

        for keyword in keywords:
            # 匹配 "keyword #123" 或 "keyword: #123" 或 "keyword ... #123"（最多5个词）
            pattern = re.compile(
                rf'\b{keyword}\s*:?\s*(?:\w+\s+){{0,5}}#(\d+)',
                re.IGNORECASE
            )
            for match in pattern.finditer(text):
                refs.add(int(match.group(1)))

        return refs

    def audit_blocked_issues(self) -> Dict[str, Any]:
        """审计阻塞的 Issues"""
        blocked_issues = []

        for issue in self.issues:
            labels = [label['name'] for label in issue.get('labels', [])]

            if self.BLOCKED_LABEL in labels:
                body = issue.get('body') or ''
                dependencies = self._extract_blocking_dependencies(body)

                # 检查已关闭的依赖
                closed_deps = []
                for dep in dependencies:
                    if self._is_issue_closed(dep):
                        closed_deps.append(dep)

                blocked_issues.append({
                    'number': issue['number'],
                    'title': issue['title'],
                    'dependencies': dependencies,
                    'closed_dependencies': closed_deps,
                    'missing_dependency_info': len(dependencies) == 0,
                })

        # 检测循环依赖
        cycles = self._detect_dependency_cycles(blocked_issues)

        return {
            'total_blocked': len(blocked_issues),
            'issues': blocked_issues,
            'cycles': cycles,
            'limitation': '无法从 API 获取"阻塞标签首次添加时间"，无法计算精确阻塞时长',
        }

    def _extract_blocking_dependencies(self, body: str) -> List[int]:
        """从 Issue 正文提取阻塞依赖"""
        dependencies = []

        # 匹配 "blocked by #123" 或 "depends on #123" 等模式
        patterns = [
            r'blocked\s+by\s+#(\d+)',
            r'depends\s+on\s+#(\d+)',
            r'waiting\s+for\s+#(\d+)',
            r'阻塞.*?#(\d+)',
            r'依赖.*?#(\d+)',
            r'等待.*?#(\d+)',
        ]

        for pattern in patterns:
            for match in re.finditer(pattern, body, re.IGNORECASE):
                dependencies.append(int(match.group(1)))

        return list(set(dependencies))  # 去重

    def _is_issue_closed(self, issue_num: int) -> bool:
        """检查 Issue 是否已关闭"""
        try:
            issue = self.client.api_call(f"/repos/{self.client.repo}/issues/{issue_num}")
            return issue['state'] == 'closed'
        except AuditError:
            return False

    def _detect_dependency_cycles(self, blocked_issues: List[Dict]) -> List[List[int]]:
        """检测循环依赖"""
        # 构建依赖图
        graph = {}
        for issue in blocked_issues:
            graph[issue['number']] = issue['dependencies']

        cycles = []
        visited = set()
        rec_stack = set()

        def dfs(node: int, path: List[int]) -> None:
            if node in rec_stack:
                # 找到循环
                cycle_start = path.index(node)
                cycle = path[cycle_start:] + [node]
                cycles.append(cycle)
                return

            if node in visited:
                return

            visited.add(node)
            rec_stack.add(node)
            path.append(node)

            for dep in graph.get(node, []):
                dfs(dep, path[:])

            rec_stack.remove(node)

        for issue_num in graph.keys():
            if issue_num not in visited:
                dfs(issue_num, [])

        return cycles

    def audit_milestones(self) -> Dict[str, Any]:
        """审计 Milestone 覆盖率"""
        total = len(self.issues)
        milestone_stats = defaultdict(int)
        without_milestone = []

        for issue in self.issues:
            milestone = issue.get('milestone')
            if milestone:
                milestone_name = milestone['title']
                milestone_stats[milestone_name] += 1
            else:
                without_milestone.append(issue['number'])

        return {
            'total': total,
            'with_milestone': total - len(without_milestone),
            'without_milestone': without_milestone,
            'milestone_breakdown': dict(milestone_stats),
        }

    def generate_report(self) -> str:
        """生成审计报告"""
        report_lines = []

        # 报告头部
        report_lines.append("# GitHub Issue 健康度审计报告")
        report_lines.append("")
        report_lines.append(f"**生成时间**: {datetime.now(timezone.utc).isoformat()}")
        report_lines.append(f"**仓库**: {self.client.repo}")
        report_lines.append(f"**Open Issues 总数**: {len(self.issues)}")
        report_lines.append("")
        report_lines.append("---")
        report_lines.append("")

        # 标签审计
        label_audit = self.audit_labels()
        report_lines.append("## 📋 标签覆盖率")
        report_lines.append("")
        report_lines.append(f"- **任意标签覆盖率**: {label_audit['with_any_label']}/{label_audit['total']} "
                          f"({label_audit['with_any_label']/label_audit['total']*100:.1f}%)")
        report_lines.append(f"- **优先级标签覆盖率**: {label_audit['with_priority']}/{label_audit['total']} "
                          f"({label_audit['with_priority']/label_audit['total']*100:.1f}%)")
        report_lines.append(f"- **类型标签覆盖率**: {label_audit['with_type']}/{label_audit['total']} "
                          f"({label_audit['with_type']/label_audit['total']*100:.1f}%)")
        report_lines.append("")

        if label_audit['without_label']:
            report_lines.append(f"**无标签 Issues** ({len(label_audit['without_label'])} 个):")
            report_lines.append(f"#{', #'.join(map(str, label_audit['without_label']))}")
            report_lines.append("")

        report_lines.append("**说明**: 优先级和类型标签是分类完整性的关键指标，\"有任意标签\"不等于\"分类完整\"。")
        report_lines.append("")
        report_lines.append("---")
        report_lines.append("")

        # 标题前缀审计
        title_audit = self.audit_titles()
        report_lines.append("## 📝 标题前缀分类")
        report_lines.append("")
        for prefix, issues in sorted(title_audit.items(), key=lambda x: -len(x[1])):
            report_lines.append(f"- **{prefix}**: {len(issues)} 个")
            report_lines.append(f"  - #{', #'.join(map(str, issues[:10]))}" +
                              (f" ..." if len(issues) > 10 else ""))
        report_lines.append("")
        report_lines.append("---")
        report_lines.append("")

        # 负责人审计
        assignee_audit = self.audit_assignees()
        report_lines.append("## 👤 负责人覆盖率")
        report_lines.append("")
        report_lines.append(f"- **已指派负责人**: {assignee_audit['with_assignee']}/{assignee_audit['total']} "
                          f"({assignee_audit['with_assignee']/assignee_audit['total']*100:.1f}%)")
        report_lines.append("")

        if assignee_audit['without_assignee']:
            report_lines.append(f"**未指派负责人的 Issues** ({len(assignee_audit['without_assignee'])} 个):")
            unassigned_list = assignee_audit['without_assignee'][:20]
            report_lines.append(f"#{', #'.join(map(str, unassigned_list))}" +
                              (f" ... (共 {len(assignee_audit['without_assignee'])} 个)"
                               if len(assignee_audit['without_assignee']) > 20 else ""))
            report_lines.append("")

        report_lines.append("**说明**: \"已阻塞\"标签不是负责人机制的替代。")
        report_lines.append("")
        report_lines.append("---")
        report_lines.append("")

        # PR 引用审计
        pr_audit = self.audit_pr_references()
        report_lines.append("## 🔗 最近 10 个已合并 PR 的 Issue 引用")
        report_lines.append("")
        report_lines.append("按 GitHub 合并时间排序：")
        report_lines.append("")

        for pr in pr_audit:
            report_lines.append(f"### PR #{pr['number']}: {pr['title']}")
            report_lines.append(f"- **合并时间**: {pr['merged_at']}")
            report_lines.append(f"- **有 Issue 引用**: {'✅' if pr['has_reference'] else '❌'}")

            if pr['auto_close']:
                report_lines.append(f"- **自动关闭** (Closes/Fixes/Resolves): #{', #'.join(map(str, pr['auto_close']))}")

            if pr['reference_only']:
                report_lines.append(f"- **普通关联** (Refs/Supports/Related): #{', #'.join(map(str, pr['reference_only']))}")

            report_lines.append("")

        report_lines.append("**说明**: `Closes/Fixes/Resolves` 会自动关闭 Issue，`Refs/Supports/Related` 仅做关联。")
        report_lines.append("")
        report_lines.append("---")
        report_lines.append("")

        # 阻塞依赖审计
        blocked_audit = self.audit_blocked_issues()
        report_lines.append("## 🚧 阻塞依赖分析")
        report_lines.append("")
        report_lines.append(f"- **带\"已阻塞\"标签的 Issues**: {blocked_audit['total_blocked']} 个")
        report_lines.append("")

        if blocked_audit['issues']:
            for issue in blocked_audit['issues']:
                report_lines.append(f"### Issue #{issue['number']}: {issue['title']}")

                if issue['missing_dependency_info']:
                    report_lines.append("- ⚠️ **未命名阻塞原因**（正文中未找到依赖说明）")
                else:
                    report_lines.append(f"- **依赖**: #{', #'.join(map(str, issue['dependencies']))}")

                if issue['closed_dependencies']:
                    report_lines.append(f"- ⚠️ **已关闭的依赖**: #{', #'.join(map(str, issue['closed_dependencies']))}")

                report_lines.append("")

        if blocked_audit['cycles']:
            report_lines.append("### ⚠️ 检测到循环依赖")
            for cycle in blocked_audit['cycles']:
                report_lines.append(f"- {' → '.join(f'#{n}' for n in cycle)}")
            report_lines.append("")

        report_lines.append(f"**限制**: {blocked_audit['limitation']}")
        report_lines.append("")
        report_lines.append("---")
        report_lines.append("")

        # Milestone 审计
        milestone_audit = self.audit_milestones()
        report_lines.append("## 🎯 Milestone 覆盖率")
        report_lines.append("")
        report_lines.append(f"- **已纳入 Milestone**: {milestone_audit['with_milestone']}/{milestone_audit['total']} "
                          f"({milestone_audit['with_milestone']/milestone_audit['total']*100:.1f}%)")
        report_lines.append("")

        if milestone_audit['milestone_breakdown']:
            report_lines.append("**Milestone 分布**:")
            for milestone, count in sorted(milestone_audit['milestone_breakdown'].items()):
                report_lines.append(f"- **{milestone}**: {count} 个")
            report_lines.append("")

        if milestone_audit['without_milestone']:
            report_lines.append(f"**未纳入 Milestone 的 Issues** ({len(milestone_audit['without_milestone'])} 个):")
            unassigned_list = milestone_audit['without_milestone'][:20]
            report_lines.append(f"#{', #'.join(map(str, unassigned_list))}" +
                              (f" ... (共 {len(milestone_audit['without_milestone'])} 个)"
                               if len(milestone_audit['without_milestone']) > 20 else ""))
            report_lines.append("")

        report_lines.append("**说明**: Milestone 用于版本规划，不是永久分类标签。")
        report_lines.append("")

        return "\n".join(report_lines)


def main():
    parser = argparse.ArgumentParser(
        description="GitHub Issue 健康度审计工具（只读）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
    python tools/audit-github-issues.py --repo Gavin8233841/medcue-ios

认证:
    需要 gh CLI 已认证 (gh auth login)
    需要仓库读取权限

失败行为:
    网络、权限、解析错误时立即报告并退出
    不会生成不完整但看似正常的统计
        """
    )

    parser.add_argument(
        '--repo',
        required=True,
        help='仓库名称（格式: owner/name）'
    )

    args = parser.parse_args()

    try:
        # 创建 API 客户端
        client = GitHubAPIClient(args.repo)

        # 创建审计器
        auditor = IssueAuditor(client)

        # 获取数据
        auditor.fetch_data()

        # 生成报告
        report = auditor.generate_report()

        # 输出报告
        print(report)

    except AuditError as e:
        print(f"❌ 审计失败: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n⚠️ 用户中断", file=sys.stderr)
        sys.exit(130)
    except Exception as e:
        print(f"❌ 未预期错误: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
