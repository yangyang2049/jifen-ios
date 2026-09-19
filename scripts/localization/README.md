# zh-Hant 语料流水线

`gen_zh_hant.mjs` 从三个输入生成 `zh-Hant.lproj/Localizable.strings` 草稿与复核报告：

- iOS `jifen/Resources/zh-Hans.lproj/Localizable.strings`（骨架：分节注释与 key 顺序原样保留）
- 安卓 `values-zh-rCN/strings.xml` + `values-zh-rTW/strings.xml`（语料源）

## 分档

1. **tier1 直抄**：key 相同且 iOS 简值 == 安卓简值 → 抄安卓繁值
2. **tier2 值锚定**：iOS 简值在安卓简值集合唯一命中 → 抄其繁值（占位符集合必须全等，否则降 tier3）
3. **tier3 简转繁**：opencc-js `cn→tw`（复用 `jifenqi-website/node_modules`，`--converter identity` 可降级）

三档之后统一过 `zh-Hant-terms.json` 词表（螢幕/預設/連線/資料/裝置/回饋/使用者…+ 引号「」化）。**平台专属 key**（cast_/airplay/share_/account_/apple_/login）禁用安卓措辞、强制人工 override。

## 复核闭环

人工**只编辑** `zh-Hant-overrides.json`（`{key:{value,note,reviewer,date}}`），优先级 overrides > tier1/2 > tier3，重跑幂等。报告四段：① tier 分布 ② 术语命中（参考）③ 平台专属 ④ 可疑条目（繁简同值含可转字/长度膨胀/您你混用/简体残字）。

```bash
# 生成
node scripts/localization/gen_zh_hant.mjs
# 门禁（③④ 未覆盖 override 或占位符不一致 → exit 1）
node scripts/localization/gen_zh_hant.mjs --check
# 通过后
mkdir -p jifen/Resources/zh-Hant.lproj
cp build/zh-Hant.draft.lproj/Localizable.strings jifen/Resources/zh-Hant.lproj/
```

默认从 `jifen-ios` 同级的 `jifen-android` 和 `jifenqi-website` 读取安卓语料与
`opencc-js`。如果本机目录布局不同，可通过 `--android-cn`、`--android-tw` 和
`--website-root` 显式指定路径。

后续 en/zh-Hans 新增 key 时重跑本脚本补齐 zh-Hant（报告头带基线 commit + 输入 sha256，可追溯）。
