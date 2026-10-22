# iScoreboard App Store 无文字头图

日期：2026-10-22

四个独立备选方案，均由内置 image_gen 工具生成；不含文字、数字或品牌标志。沿用现有图标红蓝双方的色彩线索。后续选定并上传的是第二方案舒展版 v3，详见下文。

| 方案 | 文件 | 方向 |
| --- | --- | --- |
| 01 | 01-minimal-courts.png | 极简运动 |
| 02 | 02-sculpted-sports.png | 立体器材 |
| 03 | 03-arena-atmosphere.png | 赛场氛围 |
| 04 | 04-abstract-rivalry.png | 抽象竞技 |

导出文件：3840 × 1646，RGB PNG，无透明通道。originals/ 保留生成器原始输出。导出尺寸通过重采样获得，不代表原生 4K 细节。

Apple 官方规格：https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications
Apple 构图指南：https://developer.apple.com/app-store/asset-best-practices/

主体采用居中构图；选定后仍应使用 App Store Connect Preview 检查各设备的实际裁切。

完整生成提示词见 prompts.json。

## 第二方案修订版

`02-sculpted-sports-v2-ball-and-card.png`：在第二方案基础上去掉红蓝抽象弧面，新增足球、排球、无号码台球、仅花色扑克牌和仅图案麻将。保留浅蓝背景和立体器材质感，不含文字、字母或数字。

内置 image_gen 编辑生成；原始输出保存在 originals/ 同名文件，3840 × 1646 导出由重采样获得。完整编辑提示词见 `02-sculpted-sports-v2-ball-and-card-prompt.json`。

## 第二方案舒展版

`02-sculpted-sports-v3-relaxed.png`：在 v2 基础上降低篮球、乒乓球拍和羽毛球的视觉占比，拉开物件距离，牌类略向中央收拢。保留相同元素、浅蓝背景和立体材质，无文字或数字。原始输出在 originals/；3840 × 1646 导出为重采样版本。完整提示词见 `02-sculpted-sports-v3-relaxed-prompt.json`。

## App Store Connect 上传完成（2026-10-22）

用户选定 v3 并授权直接上传后，已通过官方 API 上传至 iScoreboard（6759768784 / com.douhua.jifen.ios）的 CREATIVE_ASSETS 素材库。Apple 处理成功，回读尺寸为 3840 × 1646，匹配专用头图规格；素材 ID 为 `45000019-2e9e-82d0-8030-9d03679950ff`。

已绑定 iOS 3.3 草稿的全部 50 个语言地区，每个均为 PRODUCT_PAGE_HEADER_ASSET / DEFAULT_PROFILE，并逐项回读素材关联一致。未替换原有其他头图（上传前全部为空），没有修改截图或搜索结果素材。版本仍为 PREPARE_FOR_SUBMISSION，素材为 PREPARE_FOR_SUBMISSION；本次未提审或发布，不代表已在商店展示。

执行程序：`upload_header.py`。上传计划、空槽备份、逐项结果及最终核验在 `upload/`，最终报告为 `upload/upload-report.json`。程序可回读现有同哈希素材继续执行，不重复上传或替换其他头图。

