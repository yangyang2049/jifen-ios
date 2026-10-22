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
- `SportOptionView.iconSizeProvider`：闭包按卡片边长给出图标边长。
- `Theme.quickStartGridIconSize(cardSide:)`：双锚点线性插值
  iPhone 卡片 84pt → 图标 28pt（保持上一轮确认值），
  宽窗口卡片 128pt → 图标 45pt（可见图形 32pt）。
  纯比例会让 iPhone 涨到 29.6pt，故意不用。
- `QuickStartEditView.slotCard`：卡内所有元素按 `geo.size.height / 87` 缩放（上限 1.5）。

> 注：表里"图标"是 3D 素材的**可见图形直径**，图标框另有约 28% 透明留白。
> 32pt 可见 ⇒ 图标框 45pt。

## 实测（模拟器截图量像素）
| | 卡片高 | 图标可见直径 | 图标/卡片 |
|---|---|---|---|
| iPhone 改前 | 139.3pt | 19.7pt | 14.1% |
| iPhone 改后 | 139.3pt | 20.0pt | 14.4%（未变） |
| iPad 改前 | 150.5pt | 19.5pt | 13.0% |
| iPad 改后（比例缩放） | 150.5pt | 30.5pt | 20.3%（+56%） |
| iPad 终版（双锚点 45pt 框） | 128.0pt | **32.0pt** | 25.0% |

截图：
- `iphone_quick_start_edit_before.png` / `iphone_quick_start_edit_28pt_proportional.png` / `iphone_quick_start_edit_final.png`
- `ipad_quick_start_edit_before.png` / `ipad_quick_start_edit_proportional.png` / `ipad_quick_start_edit_32pt_visible.png`
