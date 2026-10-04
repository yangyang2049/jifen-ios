# vi — Vietnamese 文案审校

审校日期：2026-10-03。结论：有优化建议。源文案及 App Store 均未修改。

[返回总报告](/Users/yangyang/Desktop/jifenqi/jifen-ios/artifacts/app-store-copy-audit-20261003/audit-report.md) · [语言源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/vi.json)

## 检查范围与结论

| 项目 | 结果 |
| --- | --- |
| Description | 有优化建议 |
| Slogan（首图标题） | 有优化建议 |
| App Store subtitle（副标题） | 未见问题 |
| 其他截图标题 | 未见问题 |

Description 与当前 App Store 3.3 完全一致；7 个段落，994 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \n、异常 CR/tab、段尾空格或多余空段；长度在限制内。

已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，30 个 UTF-16 单元。

实际 PNG 检查范围：七张营销标题；首图原图/总览与 2–7 张标题裁切。

PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。

## 发现与具体建议

### vi-1 · 可选优化 · renderedSlogan

置信度：高。PNG将固定词组ĐIỂM SỐ和QUAN TRỌNG分别拆行，SỐ单独成行。越南语空格分隔音节，不能等同西方单词级拼写错；这是阅读节奏/词组完整性建议。应调整字号/宽度使两组连贯。

原文／实际排版：

```text
MỖI ĐIỂM
SỐ
ĐỀU QUAN
TRỌNG
```

建议文案／目标排版：

```text
MỖI ĐIỂM SỐ
ĐỀU QUAN TRỌNG
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/vi/01-slogan.png)

[查看实际 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/vi/01-slogan.png)

### vi-2 · 可选优化 · description

置信度：高。khối lập phương主要指几何立方体，当前长描述没有点明魔方速拧；建议用当地WCA赛事所用Rubik使功能对象明确。这是专门术语清晰度建议，原文并非拼写错误。

原文／实际排版：

```text
bộ đếm giờ cho khối lập phương
```

建议文案／目标排版：

```text
bộ đếm giờ giải Rubik
```

[定位源文件](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/localization-2026-10-02/locales/vi.json)

[术语或排版依据](https://www.worldcubeassociation.org/competitions/VietnamChampionship2026)

## Description 原文

```text
Mỗi điểm số đều quan trọng. Biến iPhone hoặc iPad thành bảng điểm rõ ràng, dễ dùng cho thi đấu, luyện tập và chơi cùng bạn bè.

Ghi điểm cho hơn 26 môn thể thao và trò chơi, gồm quần vợt, pickleball, cầu lông, bóng bàn, bóng rổ, bóng đá, bóng chuyền và bi-a. Với các môn được hỗ trợ, bạn có thể chỉnh luật tính điểm, thể thức thi đấu và thứ tự giao bóng đôi.

Lưu trận đấu và xem lại diễn biến điểm số, dòng thời gian cùng ghi chú giọng nói. Sử dụng đồng hồ cờ vua và cờ vây, bộ đếm giờ cho khối lập phương và đồng hồ bấm giờ. Hiển thị bảng điểm trên màn hình lớn, chia sẻ mã trận đấu để bạn bè theo dõi điểm số từ xa.

Tung đồng xu, chia đội ngẫu nhiên, thẻ đỏ và thẻ vàng, chia đều chi phí: các công cụ tiện ích đều ở một nơi. Bớt bận tính điểm, thêm thời gian tận hưởng trận đấu.

Điều khoản sử dụng:
https://jifenqi.com/terms

Chính sách quyền riêng tư:
https://jifenqi.com/privacy

Thỏa thuận cấp phép tiêu chuẩn của Apple:
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Subtitle 与 Slogan 原文

Subtitle：Điểm số, thời gian và trận đấu

JSON 中的 Slogan：

```text
Mỗi điểm số
đều quan trọng
```

截图文案源中的 Slogan（PNG 可能另有自动换行）：

```text
MỖI ĐIỂM SỐ
ĐỀU QUAN TRỌNG
```

[首图 PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/vi/01-slogan.png)

## 本批七张截图营销标题

| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |
| --- | --- | --- | --- |
| 01 | slogan | MỖI ĐIỂM SỐ<br>ĐỀU QUAN TRỌNG | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/vi/01-slogan.png) |
| 02 | score | TOÀN BỘ ĐIỂM SỐ<br>CHỈ TRONG MỘT CÁI NHÌN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/vi/02-score.png) |
| 03 | catalog | MỘT BẢNG ĐIỂM<br>CHO HƠN 26 MÔN THỂ THAO | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/vi/03-catalog.png) |
| 04 | recap | XEM LẠI<br>TỪNG TRẬN ĐẤU | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/vi/04-recap.png) |
| 05 | setup | LUẬT CỦA BẠN<br>CÁCH CHƠI CỦA BẠN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/vi/05-setup.png) |
| 06 | multiplayer | TRÒ CHƠI NHIỀU NGƯỜI<br>VÀ TRÒ CHƠI BÀN CỜ | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/vi/06-multiplayer.png) |
| 07 | cast | BẢNG ĐIỂM CỦA BẠN<br>TRÊN MÀN HÌNH LỚN | [PNG](/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/exports/vi/07-cast.png) |

表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。

## JSON 中启用的全部标题

| 标题 ID | 文案 |
| --- | --- |
| slogan | Mỗi điểm số<br>đều quan trọng |
| score | Toàn bộ điểm số<br>chỉ trong một cái nhìn |
| catalog | Một bảng điểm<br>cho hơn 26 môn thể thao |
| recap | Xem lại<br>từng trận đấu |
| setup | Luật của bạn<br>cách chơi của bạn |
| timer | Không chỉ là<br>trò chơi với bóng |
| cast | Bảng điểm của bạn<br>trên màn hình lớn |
| tools | Công cụ trọng tài<br>trong một ứng dụng |

停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。

源文件 SHA-256：`afc2a26f9cedeba263e2fb4e0cc60f0ee8dd424b3c39e848ddaa517dfb9c5cf3`。
