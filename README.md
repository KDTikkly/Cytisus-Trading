# Cytisus-Trading

<p align="center">
  <img src="Resources/ProductLogo.png" width="180" alt="Cytisus-Trading Logo">
</p>

Cytisus-Trading 是一款面向量化研究展示与因子治理评审的 macOS 离线演示应用。它用清晰的可视化流程说明一个因子如何从候选、影子观察、正式启用，最终进入降级、淘汰或隔离状态。

应用采用液态玻璃风格，所有内容均为内置脱敏样例。它不会连接券商、读取账户、查询真实行情或提交订单，适合产品演示、规则讨论和界面原型评审。

## 主要功能

- **概览**：查看活跃因子、加权覆盖率、影子队列和样本策略轨迹。
- **因子生命周期**：观察 IC、IR、覆盖率、权重和 OOS 证据窗口，并模拟因子晋升与淘汰。
- **策略实验室**：调整风险预算、最低覆盖率和单因子权重上限。
- **隐私与脱敏**：检查演示包的数据边界和离线声明。
- **本地状态机**：所有变化只保存在内存中，重新启动后恢复初始样例。

> 本项目不提供真实交易能力，不构成投资建议，也不承诺任何收益。

## 普通用户使用教程

### 1. 安装

1. 获取 `Cytisus-Trading-1.0.0-universal.dmg`。
2. 双击打开 DMG。
3. 将 `Cytisus-Trading.app` 拖入“应用程序”文件夹。
4. 在“应用程序”中打开 Cytisus-Trading。

当前公开构建采用本地临时代码签名且未经过 Apple 公证。如果 macOS 阻止首次打开，请前往 **系统设置 → 隐私与安全性**，确认应用来源后选择“仍要打开”。仅运行你信任来源的构建。

### 2. 认识主界面

左侧有四个区域：

1. **概览**：确认当前为“离线”模式，并查看总体治理状态。
2. **因子生命周期**：查看每个因子的状态、指标和评审原因。
3. **策略实验室**：拖动滑杆，模拟不同治理门槛。
4. **隐私与脱敏**：确认应用不包含账户、密钥、持仓或订单数据。

### 3. 运行一次因子评审演示

1. 进入“因子生命周期”。
2. 点击一次“生成评审提案”，观察候选因子进入影子观察、弱因子进入降级流程。
3. 再点击一次，观察满足连续 OOS 证据要求的因子晋升，以及连续失败因子的淘汰。
4. 点击“重置”即可恢复初始演示数据。

### 4. 调整治理参数

进入“策略实验室”，调整以下参数：

- 单笔风险预算
- 最低数据覆盖率
- 单因子权重上限

底部的“当前参数提案”会即时更新。此操作仅演示治理规则，不会触发交易。

## 系统要求

- macOS 14 或更高版本
- Apple Silicon 或 Intel Mac（Universal 2）
- 不需要网络、账户或 API 密钥

## 从源码构建

需要安装 Xcode Command Line Tools。在项目目录运行：

```bash
chmod +x tools/build_dmg.sh
tools/build_dmg.sh
```

构建产物位于：

```text
dist/Cytisus-Trading-1.0.0-universal.dmg
```

## 正式签名与 Apple 公证

在登录钥匙串中安装有效的 `Developer ID Application` 证书，并保存 `notarytool` 公证配置。不要将密码、令牌或 `.p8` 私钥提交到仓库。

```bash
DEVELOPER_ID_APPLICATION_IDENTITY="Developer ID Application: Organization (TEAMID)" \
NOTARY_PROFILE="sentinel-notary" \
tools/build_dmg.sh
```

启用后，构建脚本会使用 Hardened Runtime 和安全时间戳签名应用与 DMG，等待 Apple 公证结果，随后装订并验证公证票据。

## 隐私与安全

- 无网络请求
- 无身份信息
- 无账户、持仓、订单或盈亏数据
- 无令牌、证书或环境变量
- 默认不保存演示状态

详细说明见 [PRIVACY.md](PRIVACY.md) 与 [SANITIZATION.json](SANITIZATION.json)。
