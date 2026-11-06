# 本 fork 的来源与修改说明

## 来源

| 项目 | 内容 |
| --- | --- |
| 上游项目 | [angristan/MacThrottle](https://github.com/angristan/MacThrottle) |
| 原作者 | angristan |
| 许可证 | MIT License（见 [LICENSE](LICENSE)，本 fork 同样遵循） |
| 本 fork 基线 | 上游 `main` @ `2d36d4f`（chore(release): 1.9.2） |
| 本 fork 仓库 | bbfootfish/MacThrottle |

除下列修改外，代码均来自上游。本仓库不是官方发布版本，未获上游维护者背书。

## 修改内容（相对上游基线）

### 1. 修正 Apple Silicon M5 的 CPU 温度口径（`MacThrottle/Services/TemperatureReaders.swift`）

问题：上游对 M1–M4 读取固定几个 CPU SMC 键并取最大值；在 M5 上这组键不含实际 CPU 传感器，读数偏低或缺失。

修改：
- 从 `m1Keys` / `mProMaxKeys` / `m2Keys` / `m3Keys` / `m4Keys` 中剔除 GPU 相关键。
- 新增 `m5Keys`，为 M5 上确有返回值的 11 个 CPU 温度键：
  `Tp00 Tp04 Tp0C Tp0G Tp0O Tp0R Tp0X Tp0a Tp0p Tp0u Tp0y`
- `allTemperatureKeys` 追加 `m5Keys` 并去重。
- 多点读数由「取最大值」改为「取有效键的算术平均」，温度来源标注为 `SMC 平均 N 键（最高 K X.X）`；仅命中单键时回退为 `K (SMC)`。

实测依据（M5 / macOS 26.6.2，仅代表本机）：
- 上述 11 键覆盖 super core 1–4 与 performance core 1–8，是本机唯一有真实读数的 CPU 温度键。
- 11 键平均值与单点 `Tp0X` 走势基本重合（峰峰差 7.14 vs 8.10 °C，标准差 2.42 vs 2.75），平均值抗单点抖动。
- 本机空闲 79–81 °C，满载峰值 87 °C。

### 2. 新增 CPU 温度阈值判定（`MacThrottle/Services/ThermalMonitor.swift`）

问题：上游报警只依据系统热压等级（`ProcessInfo.thermalState`）。该系统值在本机长期停在 nominal/moderate，即使 CPU 已到 85 °C 以上也不报警。

修改：
- 新增四个阈值常量：预警 `warningTemperatureThreshold = 90 °C`、预警解除 `warningReleaseTemperatureThreshold = 88 °C`、严重 `criticalTemperatureThreshold = 97 °C`、严重解除 `criticalReleaseTemperatureThreshold = 95 °C`。
- 新增 `nextTemperaturePressure(previous:temperature:)`：维护「温度判定等级」，升级立即生效、降级必须跌破解除阈值（滞回），避免温度在阈值附近抖动时状态来回跳。
- 新增 `resolvedPressure(systemPressure:temperaturePressure:)`：取系统热压等级与温度判定等级中更严重者。
- 采样顺序调整为「先读温度、再算热压」，避免同一轮读到上一轮的旧温度。
- 温度读取抽成 `readTemperature()`，SMC 优先、HID 兜底，行为不变。

阈值理由：本机空闲 79–81 °C，满载峰值 87–100 °C，且无风扇机型温度随负载波动可达 ±5 °C。取 90 °C 预警、97 °C 严重，配合 2 °C 回差，既能给出提前提示，又不会在阈值附近反复跳变。系统热压等级与芯片温度本质不同步（前者随负载立即升降，后者受热惯性滞后），因此两者取更严重者，而不是互相替代。

### 3. 界面文本中文化

涉及 `MacThrottleApp.swift`、`Views/MenuContentView.swift`、`Views/AboutView.swift`、`Views/HistoryViews.swift`、`Services/UpdateChecker.swift`（仅错误文案）。仅替换展示字符串，不改逻辑。

## 构建

```bash
xcodebuild -project MacThrottle.xcodeproj -scheme MacThrottle -configuration Release \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

产物为 ad-hoc 签名的 arm64 应用，未做公证。首次打开需在「系统设置 → 隐私与安全性」中允许。

## 注意

- 温度阈值常量目前为硬编码默认值，不随用户设置在界面中调整。
- 阈值与读数均基于单台 M5 机器的实测，不同机型/环境温度下表现可能不同。
