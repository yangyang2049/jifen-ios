# 快捷入口编辑弹窗图标尺寸：iPhone / iPad / Duo 适配

## 问题
网格图标原来固定 28pt、上方槽位卡片图标固定 16pt、卡内文字固定 12/16pt。
iPhone 卡片 84pt 时尚可，iPad / Duo 展开内屏卡片涨到 129pt，
固定尺寸的图标和文字就显得很小（图标占卡片从 33% 掉到 22%）。

## 改法
改为按卡片边长比例缩放，iPhone 保持原值不变：

| 元素 | iPhone | iPad / Duo 展开 |
|---|---|---|
| 网格卡片 | 84.7pt | 129pt |
| 网格图标 | 28pt（28/84 比例） | ≈43pt（同比例） |
| 槽位卡片 | 174 × 87pt | 264 × 132pt |
| 槽位图标 | 16pt | ≈24pt（卡内整体 ×1.52） |
| 槽位徽标/文字 | 20pt / 12pt / 16pt | 同比例放大 |

实现：
- `SportOptionView.iconRatio`：图标 = 卡片边长 × 比例。
- `QuickStartEditView.slotCard`：卡内所有元素按 `geo.size.height / 87` 缩放（上限 1.5）。

## 实测（模拟器截图量像素）
| | 卡片高 | 图标可见直径 | 图标/卡片 |
|---|---|---|---|
| iPhone 改前 | 139.3pt | 19.7pt | 14.1% |
| iPhone 改后 | 139.3pt | 20.0pt | 14.4%（未变） |
| iPad 改前 | 150.5pt | 19.5pt | 13.0% |
| iPad 改后 | 150.5pt | 30.5pt | 20.3%（+56%） |

截图：
- `iphone_quick_start_edit_before.png` / `iphone_quick_start_edit_28pt_proportional.png`
- `ipad_quick_start_edit_before.png` / `ipad_quick_start_edit_proportional.png`
