# id — Indonesian 文案审校

审校日期：2026-10-03。结论：有优化建议。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/id.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 有优化建议 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，1051 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，28 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### id-1 · 可选优化 · description

置信度：高。kubus是泛指立方体；为准确呈现魔方计时可加Rubik，WCA印尼赛事原文使用kubus rubik。属于消除歧义建议，不能认定原文中的kubus作为语境简称是错译。

原文／实际排版：

```text
pewaktu kubus
```

建议文案／目标排版：

```text
pewaktu kubus Rubik
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/id.json)

[术语或排版依据](https://www.worldcubeassociation.org/competitions/GramediaCubeOpenJakarta2024)

## Description 原文

```text
Setiap poin berarti. Ubah iPhone atau iPad menjadi papan skor yang jelas dan mudah digunakan untuk pertandingan, latihan, dan permainan bersama teman.

Catat skor untuk lebih dari 26 olahraga dan permainan, termasuk tenis, pickleball, bulu tangkis, tenis meja, basket, sepak bola, voli, dan biliar. Atur aturan poin, format pertandingan, dan urutan servis ganda pada olahraga yang mendukungnya.

Simpan pertandingan dan tinjau perubahan skor, linimasa, serta catatan suara. Gunakan jam catur dan go, pewaktu kubus, dan stopwatch. Tampilkan papan skor di layar besar dan bagikan kode pertandingan agar teman dapat mengikuti skor dari jauh.

Lempar koin, bagi tim secara acak, tampilkan kartu merah dan kuning, serta bagi biaya dengan alat praktis dalam satu aplikasi. Lebih sedikit repot menghitung, lebih banyak waktu menikmati permainan.

Ketentuan penggunaan:
https://jifenqi.com/terms

Kebijakan privasi:
https://jifenqi.com/privacy

Perjanjian lisensi pengguna akhir standar Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Skor, waktu dan catatan laga

JSON 中的 Slogan：

```text
Setiap poin
berarti
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
SETIAP POIN
BERARTI
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/id/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | SETIAP POIN<br>BERARTI | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/id/01-slogan.png) |
| 02 | score | SEMUA SKOR<br>SEKILAS TERLIHAT | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/id/02-score.png) |
| 03 | catalog | SATU PAPAN SKOR<br>UNTUK 26+ OLAHRAGA | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/id/03-catalog.png) |
| 04 | recap | TINJAU KEMBALI<br>SETIAP PERTANDINGAN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/id/04-recap.png) |
| 05 | setup | ATURANMU<br>CARA BERMAINMU | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/id/05-setup.png) |
| 06 | multiplayer | PERMAINAN MULTIPEMAIN<br>DAN PAPAN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/id/06-multiplayer.png) |
| 07 | cast | PAPAN SKORMU<br>DI LAYAR BESAR | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/id/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Setiap poin<br>berarti |
| score | Semua skor<br>sekilas terlihat |
| catalog | Satu papan skor<br>untuk 26+ olahraga |
| recap | Tinjau kembali<br>setiap pertandingan |
| setup | Aturanmu<br>cara bermainmu |
| timer | Lebih dari sekadar<br>permainan bola |
| cast | Papan skormu<br>di layar besar |
| tools | Peralatan wasit<br>dalam satu aplikasi |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`a24b9b14d5b815f541c643aaddf961fc2250b11169a6c3b21bce66feb89fbf90`。
