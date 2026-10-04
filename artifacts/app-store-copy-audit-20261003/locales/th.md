# th — Thai 文案审校

审校日期：2026-10-03。结论：有优化建议。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/th.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 有优化建议 |
| Slogan（首图标题） | 未见问题 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，869 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，30 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### th-1 · 可选优化 · description

置信度：高。ลูกบาศก์是泛指立方体；本功能实际计时魔方速拧，WCA泰国赛事原文使用รูบิค。可进一步明确对象；不把原几何名词直接判成拼写错误。

原文／实际排版：

```text
ตัวจับเวลาลูกบาศก์
```

建议文案／目标排版：

```text
ตัวจับเวลารูบิค
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/th.json)

[术语或排版依据](https://www.worldcubeassociation.org/competitions/ThailandChampionship2018)

## Description 原文

```text
ทุกคะแนนมีความหมาย เปลี่ยน iPhone หรือ iPad ให้เป็นกระดานคะแนนที่ชัดเจนและใช้ง่าย สำหรับการแข่งขัน การฝึกซ้อม และการเล่นกับเพื่อน

บันทึกคะแนนสำหรับกีฬาและเกมกว่า 26 ประเภท ทั้งเทนนิส พิกเคิลบอล แบดมินตัน ปิงปอง บาสเกตบอล ฟุตบอล วอลเลย์บอล และบิลเลียด ปรับกติกาการนับคะแนน รูปแบบการแข่งขัน และลำดับเสิร์ฟประเภทคู่สำหรับกีฬาที่รองรับ

บันทึกการแข่งขันแล้วดูแนวโน้มคะแนน ลำดับเหตุการณ์ และบันทึกเสียง ใช้นาฬิกาหมากรุกและโกะ ตัวจับเวลาลูกบาศก์ และนาฬิกาจับเวลา แสดงกระดานคะแนนบนหน้าจอใหญ่ และแชร์รหัสการแข่งขันให้เพื่อนติดตามคะแนนจากระยะไกล

เครื่องมือโยนเหรียญ สุ่มแบ่งทีม ใบแดงและใบเหลือง รวมถึงหารค่าใช้จ่าย อยู่ในแอปเดียว ใช้เวลานับคะแนนน้อยลงและสนุกกับเกมมากขึ้น

เงื่อนไขการใช้งาน:
https://jifenqi.com/terms

นโยบายความเป็นส่วนตัว:
https://jifenqi.com/privacy

ข้อตกลงสิทธิ์การใช้งานมาตรฐานของ Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：คะแนน เวลา และบันทึกการแข่งขัน

JSON 中的 Slogan：

```text
ทุกคะแนน
มีความหมาย
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
ทุกคะแนน
มีความหมาย
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/th/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | ทุกคะแนน<br>มีความหมาย | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/th/01-slogan.png) |
| 02 | score | เห็นทุกคะแนน<br>ได้ในพริบตา | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/th/02-score.png) |
| 03 | catalog | กระดานเดียว<br>สำหรับกีฬากว่า 26 ประเภท | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/th/03-catalog.png) |
| 04 | recap | ย้อนดู<br>ทุกการแข่งขัน | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/th/04-recap.png) |
| 05 | setup | กติกาของคุณ<br>เล่นในแบบของคุณ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/th/05-setup.png) |
| 06 | multiplayer | เกมหลายผู้เล่น<br>และบอร์ดเกม | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/th/06-multiplayer.png) |
| 07 | cast | กระดานคะแนน<br>บนหน้าจอใหญ่ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/th/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | ทุกคะแนน<br>มีความหมาย |
| score | เห็นทุกคะแนน<br>ได้ในพริบตา |
| catalog | กระดานเดียว<br>สำหรับกีฬากว่า 26 ประเภท |
| recap | ย้อนดู<br>ทุกการแข่งขัน |
| setup | กติกาของคุณ<br>เล่นในแบบของคุณ |
| timer | มากกว่า<br>กีฬาที่ใช้ลูกบอล |
| cast | กระดานคะแนน<br>บนหน้าจอใหญ่ |
| tools | เครื่องมือผู้ตัดสิน<br>ครบในแอปเดียว |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`b210b147d11c9d631f13d2730756e586967af09bee2d8c91329d5d701df8cb84`。
