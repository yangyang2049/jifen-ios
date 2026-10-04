# 魔方计时器手掌轮廓

原 PNG 存在白色抠图残边、零散像素和不平滑轮廓。内置 image_gen 的两次生成也有透明边缘碎点，未采用；最终重新绘制成原生 SwiftUI Shape，保持原有平面剪影风格。

第二版按用户选定的 [参考图](reference-selected.png) 重新描绘，手指和掌部更饱满，掌根底部接成同方向的水平切线，消除上一版的两个小折点。当前 SVG 和 App 均使用第二版轮廓。

- [第二版布局预览](preview-v2.png)，非模拟器截图
- [第二版左手大图](hand-left-v2.png)
- [第二版轮廓数据](outline-v2.json)

- [左手 SVG](hand-left.svg)
- [右手 SVG](hand-right.svg)
- [左手按下 SVG](hand-left-touched.svg)
- [右手按下 SVG](hand-right-touched.svg)
- [200pt / 400pt 布局预览](preview.html)，非模拟器截图
- [未采用的生成提示词](generation-attempts.json)

App 使用同一条连续贝塞尔轮廓：右手水平镜像，未按下为原图主色 #464646，按下为原图主色 #00A704。保留手机 200pt、二合一 380pt、iPad 400pt 的图标框尺寸。原始图片保留，页面不再使用它们。

验证：iOS Debug 模拟器编译通过；200pt / 400pt 的 HTML 矢量预览检查通过；目标文件 diff 格式检查通过；计时与触碰状态处理与修改前一致。未执行原生模拟器页面视觉回归。
