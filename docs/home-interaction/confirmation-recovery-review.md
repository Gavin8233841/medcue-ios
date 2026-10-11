# 首页确认失效 Required 的独立修复

> Historical implementation/design record, 2026-10-10. Stage labels identify evidence boundaries, not ancestors of this public-preparation branch. Original source/evidence mappings are retained separately. Current acceptance and publication status are in [plan.md](plan.md); no historical result proves this public revision passed.

基于已保存首页 `implementation-stage-04`。原始快照与验收记录保留，不改demo或宏测试；此修复必须单独提交与独审。

## 问题与授权边界

原候选把确认目标缺失当已知边界，实际会锁死：selectedTask=nil时左右都锁，唯一取消随动作区消失。目标仍在但key变化、外部已处理/归档同样失效；宽屏拒接同key新UUID后切单栏，旧单栏按key挂确认可能交给替代记录。独审将其定为Required，协调者明确拒绝接受该边界并授权最小恢复。

完整模式两种呈现共用task UUID＋medication UUID＋当前logical key＋可操作/未归档判断。失效时保留明确的「取消原来的用药确认」入口；窄屏放在任务区上方，宽屏放MissingSelection。取消不依赖旧StoredDoseTask。

唯一Today owner新增按预期pending key取消回调，调用时核对当前仍是同key，沿用原减少动态/0.16秒动画，仅赋值pending。原task取消委托该方法。没有cleanup调用、inFlight写入、保存/日志/提醒调用；旧key回调不清新key。UI在相同key保存中禁用取消；inFlight-only等待，不宣称能取消保存。

单列不再按key单独挂卡；与宽屏共用resolve。无效pending期间其他行的三动作禁用，避免对替代记录请求或提交；原确认回调还核对有效UUID。取消后解锁浏览/原动作。

## 精确范围

| 文件 | 改动与边界 |
| --- | --- |
| TodayTaskWorkspaceView.swift | 引用增加只读isActionable；pending的共同匹配；纯key取消策略；失效页独立按钮 |
| TodayScreen.swift | 窄/宽共用匹配；窄屏恢复入口、无效确认不挂替代行及其他行禁用；适老尾段/lifecycle不变 |
| TodayView.swift | 唯一owner新增窄key取消及原method委托；完整模式actions接线；一个Simulator显式fixture注入观察点。此次明确授权例外仅这两个取消函数，其余原剂量/cleanup/事务函数不变 |
| AppRootView.swift | 仅Simulator DEBUG/MEDCUE_DEMO fixture：future-multiple、显式失效注入与只读live计数。标准初始化/维修/迁移/通知函数不变 |
| 新 TodayPendingConfirmationRecoveryTests.swift | 4项纯策略：旧key、新key/幂等、inFlight保持、共同失效/尺寸选择 |
| 新 TodayPendingConfirmationRecoveryUITests.swift | 宽屏与AX各5种场景：缺失、key变化、已处理、归档、替代UUID；取消可点、旧confirm不存在、恢复可操作、前后实际task/log/save/schedule可观察证据相同 |

注入只在`--elder-ui-invalidate-confirmation <case>`＋既有session隔离factory中工作，且校验ModelContext严格等于其owned mainContext。它模拟外部状态变化，直接保存synthetic任务变更；此保存不伪装为取消行为。只读live面板让UI在注入完成之后、取消之前采样，再与取消后比较，避免重启维修/再生成任务混入证据。没有写真实库、旧fixture store覆盖或五药导入。未知fixture或非同context不执行注入。

## 验收与停止条件

云端仅做源码范围/空白/1400行检查；没有Swift/Xcode，新增hosted/UI测试尚未编译执行。两种字体分别运行不等于真正开合；运行中宽窄转换、原生AX可达与VOICEOVER仍需Mac。旧宏文件保持adaptive-home-stage/mode-navigation-test-stage不变，等待原生验证负责人修复，不以本切片掩盖上游exit65/零测试。

必须独审核准新的窄取消契约和共同目标匹配；测试fault injection与真实UI可达证据不可互相代替。若编译/原生暴露新失败，保留结果后小提交修；不扩timeout、不删除断言、不改CI。

停止扩大：必须改#138状态文件、cleanup/保存/通知事务、适老模式、schema/迁移、真实库或外部调用时交接精确冲突。本切片不承诺收口未验证的全部生命周期。

低成本UI完善：宽屏专项现在读取显式fixture提供的实际GeometryReader宽高（668×360），避免只看窗口宽而误判横屏iPhone；无效或未知测量直接断言失败。两药/future身份断言核1片/1滴及11:55/11:58/18:00，不只核字段标题。测量值只在Simulator隔离fixture提供，不向普通用户朗读工程数据。
