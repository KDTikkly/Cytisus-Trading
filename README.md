# Cytisus-Trading DMG

脱敏、离线、自包含的 macOS 因子治理演示应用。界面采用半透明材质、动态色彩光斑、镜面描边和圆角层级，参考液态玻璃设计语言。

## 构建

```bash
chmod +x tools/build_dmg.sh
tools/build_dmg.sh
```

产物：`dist/Cytisus-Trading-1.0.0-universal.dmg`

应用为 Universal 2（Apple Silicon + Intel），最低 macOS 14，采用临时代码签名且未公证。

## 正式签名与 Apple 公证

先在登录钥匙串中安装有效的 `Developer ID Application` 证书，并将公证凭据保存为 `notarytool` 钥匙串配置。不要把密码或 `.p8` 私钥写入项目。

```bash
DEVELOPER_ID_APPLICATION_IDENTITY="Developer ID Application: Organization (TEAMID)" \
NOTARY_PROFILE="sentinel-notary" \
tools/build_dmg.sh
```

启用后，构建脚本会使用 Hardened Runtime 和安全时间戳签名应用与 DMG，等待 Apple 公证结果，随后装订并验证公证票据。缺少正式签名时脚本会拒绝公证。
