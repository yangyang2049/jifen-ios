# ms — Malay 文案审校

审校日期：2026-10-03。结论：需修正。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/ms.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 有优化建议 |
| Slogan（首图标题） | 需修正 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1033 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，26 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### ms-1 · 需修正 · renderedSlogan

置信度：高。PNG把完整单词BERMAKNA拆成BERMAKN与孤立A；确定词内断行。应缩小字号或加宽框以使BERMAKNA整词同一行。

原文／实际排版：

```text
SETIAP
MATA
BERMAKN
A
```

建议文案／目标排版：

```text
SETIAP
MATA
BERMAKNA
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ms/01-slogan.png)

[查看实际 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ms/01-slogan.png)

### ms-2 · 可选优化 · description

置信度：高。kiub是泛指立方体；可用kiub Rubik说明魔方计时，DBP术语实例使用kiub rubik。属于清晰度建议，原词在魔方语境中可作简称。

原文／实际排版：

```text
pemasa kiub
```

建议文案／目标排版：

```text
pemasa kiub Rubik
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/ms.json)

[术语或排版依据](https://prpm.dbp.gov.my/Cari1?d=371752&keyword=jana)

## Description 原文

```text
Setiap mata bermakna. Jadikan iPhone atau iPad anda papan skor yang jelas dan mudah digunakan untuk perlawanan, latihan dan permainan bersama rakan.

Catat skor untuk lebih 26 sukan dan permainan, termasuk tenis, pickleball, badminton, ping pong, bola keranjang, bola sepak, bola tampar dan biliard. Laraskan peraturan mata, format perlawanan dan urutan servis beregu bagi sukan yang menyokongnya.

Simpan perlawanan dan semak perubahan skor, garis masa serta nota suara. Gunakan jam catur dan go, pemasa kiub dan jam randik. Paparkan papan skor pada skrin besar dan kongsi kod perlawanan supaya rakan boleh mengikuti skor dari jauh.

Lambungan syiling, pembahagian pasukan secara rawak, kad merah dan kuning serta pembahagian belanja — semuanya dalam satu aplikasi. Kurangkan kerja mengira, nikmati permainan dengan lebih lagi.

Syarat penggunaan:
https://jifenqi.com/terms

Dasar privasi:
https://jifenqi.com/privacy

Perjanjian lesen pengguna akhir standard Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Skor, masa dan rekod sukan

JSON 中的 Slogan：

```text
Setiap mata
bermakna
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
SETIAP MATA
BERMAKNA
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ms/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | SETIAP MATA<br>BERMAKNA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ms/01-slogan.png) |
| 02 | score | SEMUA SKOR<br>SEKILAS PANDANG | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ms/02-score.png) |
| 03 | catalog | SATU PAPAN SKOR<br>UNTUK LEBIH 26 SUKAN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ms/03-catalog.png) |
| 04 | recap | SEMAK SEMULA<br>SETIAP PERLAWANAN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ms/04-recap.png) |
| 05 | setup | PERATURAN ANDA<br>CARA PERMAINAN ANDA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ms/05-setup.png) |
| 06 | multiplayer | PERMAINAN BERBILANG PEMAIN<br>DAN PERMAINAN PAPAN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ms/06-multiplayer.png) |
| 07 | cast | PAPAN SKOR ANDA<br>PADA SKRIN BESAR | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/ms/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Setiap mata<br>bermakna |
| score | Semua skor<br>sekilas pandang |
| catalog | Satu papan skor<br>untuk lebih 26 sukan |
| recap | Semak semula<br>setiap perlawanan |
| setup | Peraturan anda<br>cara permainan anda |
| timer | Lebih daripada<br>permainan bola |
| cast | Papan skor anda<br>pada skrin besar |
| tools | Alat pengadil<br>dalam satu aplikasi |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`d1c6d3765a2c8a4a438f848c4fb07607746c3a72965788fa2da2bfbc2e813dc6`。
