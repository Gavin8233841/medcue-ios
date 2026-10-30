# 赛事 iPhone 离线模型导入

先安装支持 MiniCPM5-2B 的新版 MedCue，连接并解锁赛事 iPhone，保持亮屏，确认信任 Mac 和开发者模式。重装 App 后需要重新导入模型；App 版本号 1.0(1) 不能区分新旧构建，需核对源码提交号。

固定信息：

- Bundle：`com.gwyy.appcontest2026.medicationadherence`
- 模型：`MiniCPM5-2B-Q4_K_M.gguf`，1,561,318,368 字节。
- SHA-256：`ec2d5801640099e97d8d7e8003ad4d81f336e757811f03a26173dddf386602fd`
- Mac 常用位置：仓库根目录 `.codex-local/models/MiniCPM5-2B-Q4_K_M.gguf`。
- App 容器内目标：`Library/Application Support/Models/MiniCPM5-2B/MiniCPM5-2B-Q4_K_M.gguf`。
- 官方固定模型版本及清单见 `LocalAIModelManifest.miniCPM5`；不能混用旧 MiniCPM4 路径和大小检查。

在仓库根目录运行以下代码；它要求恰好一台有线连接设备，校验模型，再复制到已安装 App 的数据容器，不会重装、清库或播种数据：

```sh
python3 - <<'PY'
from pathlib import Path
import hashlib, json, subprocess
model = Path('.codex-local/models/MiniCPM5-2B-Q4_K_M.gguf')
assert model.stat().st_size == 1561318368, '模型大小错误'
h = hashlib.sha256()
with model.open('rb') as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        h.update(chunk)
assert h.hexdigest() == 'ec2d5801640099e97d8d7e8003ad4d81f336e757811f03a26173dddf386602fd', '模型校验失败'
data = json.loads(subprocess.check_output(['xcrun', 'devicectl', 'list', 'devices', '--json-output', '-'], stderr=subprocess.DEVNULL))
devices = [d for d in data['result']['devices'] if d.get('connectionProperties', {}).get('transportType') == 'wired' and d.get('connectionProperties', {}).get('tunnelState') == 'connected']
assert len(devices) == 1, '请确认恰好一台目标 iPhone 有线连接'
target = devices[0]['identifier']
result = subprocess.run(['xcrun', 'devicectl', 'device', 'copy', 'to', '--device', target, '--domain-type', 'appDataContainer', '--domain-identifier', 'com.gwyy.appcontest2026.medicationadherence', '--source', str(model.resolve()), '--destination', 'Library/Application Support/Models/MiniCPM5-2B/' + model.name, '--quiet', '--timeout', '180'], capture_output=True, text=True)
print('导入返回码：', result.returncode)
if result.returncode:
    print((result.stdout + result.stderr).replace(target, '[device]'))
    raise SystemExit(result.returncode)
PY
```

打开 App → 智能体 → 设备端模式，确认模型可用并问一条普通问题。复制返回 0 仅证明传输成功，不证明推理成功；必要时退出 App 再打开刷新状态。录制中不要运行会退出 App 的 DEBUG smoke。

失败时只查以下几项：

- `Locked`：解锁并保持亮屏，不要因此重装 App。
- 找不到 App/container：核对安装包 bundle，不要猜其他标识或换目标设备。
- Mac 找不到模型：优先复用已有文件，勿直接重下 1.56GB。
- 复制失败：保留实际错误，核对 `appDataContainer` 和完整相对路径。失败不能报成功，查明原因后再重试。
- 复制成功但仍要求下载：检查是否安装了旧 MiniCPM4 构建，核对源码 SHA 和模型清单。

不要删除普通数据库、现有模型和演示记录；GGUF、设备标识和原始日志不得入 Git。
