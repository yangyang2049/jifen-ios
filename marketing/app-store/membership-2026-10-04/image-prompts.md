# 内购推广图生成说明

使用内置 `image_gen.imagegen`，不使用外部 CLI 或项目 API 密钥。原始生成结果保留在本次聊天的 Codex generated_images 目录，最终推广图导出在 `images/`，均为 1024 × 1024 的不透明 RGB PNG。

三张图均无字母、数字、品牌字样或价格；会员标志为统一的 3D 皇冠。米白背景延伸到画布边缘，不预绘制圆角和 Apple 外框。左下角留空给 Apple 附加的应用图标。

## 月会员最终提示

Use case: stylized-concept. Asset type: App Store Connect in-app purchase promotional icon for the MONTHLY VIP membership of a sports scoreboard app. Create ONE standalone 1024x1024 square image with completely opaque edge-to-edge warm ivory background, no rounded outer border, no frame. Main subject: a substantial softly beveled cobalt-blue enamel three-point premium crown, with tasteful pale gold accents, floating slightly above a simple small ivory calendar tile with blue header and a clean blank 4x4 grid of rounded squares. This is a monthly membership emblem, internationally understood, entirely language-free: NO letters, NO numbers, NO words including VIP, NO watermark, NO logos. Style: polished premium friendly 3D app illustration, smooth molded ceramic and brushed metal, studio soft lighting from top left, subtle realistic contact shadows, sparse refined composition, front three-quarter view, bold silhouette legible at 64px. Center subject slightly above center within inner 70 percent of canvas. Calendar is secondary and placed below and slightly to the right of the crown. Keep bottom-left quadrant of the canvas mostly free for Apple's overlay. Only crown and calendar, no sparkle confetti, no extra sports equipment. Output a single finished icon, not a sheet, not a mockup.

月历网格为装饰性符号，最终图包含 4 列 × 3 行，不把格数用作天数承诺。

## 年会员生成提示

Use case: stylized-concept. Asset type: annual VIP membership App Store promotional icon. Input image is the STYLE REFERENCE for a matching three-icon family, not an image to keep verbatim. Generate ONE standalone square opaque image matching the reference's warm ivory edge-to-edge background, premium soft 3D rendering, lighting, size and composition of the crown. For YEARLY membership use a rich violet enamel three-point crown with the same pale gold metallic rim, gold beads and central diamond shape as reference. Replace the monthly calendar with a broader ivory YEAR calendar tile below and slightly right of the crown: gold binding rings, purple header, EXACTLY twelve blank inset purple rounded squares arranged 3 columns by 4 rows, representing twelve months. No text, no letters, no numbers, no VIP, no watermark, no logo, no outer border or rounded corners. Only crown and year-calendar. Bold silhouette readable as a small icon, bottom left open for Apple app icon overlay. A single finished 1024x1024 icon, not a sheet, not a mockup.

### 年会员最终修正提示

Use case: precise-object-edit. This is the edit target for the yearly membership promotional icon. Make ONE targeted correction: replace only the calendar's 3x3 grid of NINE purple squares with a grid of EXACTLY TWELVE purple rounded squares arranged in FOUR horizontal rows with THREE squares per row (3 columns x 4 rows = 12). The FOUR rows must be fully visible. Reduce the square height and vertical gaps slightly to fit all FOUR rows within the existing calendar tile. Keep the entire image, crown, gold trim, ivory background, lighting, shadows, canvas size and calendar shape/composition identical. No numbers, no letters, no words, no logos. Preserve full opacity. The correct icon must depict the 12 months of one year. Do not change anything else.

## 买断最终提示

Use case: stylized-concept. Asset type: LIFETIME VIP one-time purchase App Store promotional icon. Input image is a STYLE REFERENCE for a matching premium three-icon family. Create ONE standalone 1024x1024 square with the same fully opaque warm ivory background, lighting, crown size, composition and bevel style as reference. Main crown: warm champagne-gold three-point crown with brushed gold trim, gold beads at tips and a polished amber diamond at center; distinguish this lifetime icon from blue monthly and purple yearly variants. Change the small calendar to one substantial gold metallic INFINITY symbol, a perfectly legible horizontal mathematical infinity figure-eight with exactly TWO open lobes, floating below and slightly to the right of crown. Symbol should be bold and solid, never a number eight upright. Crown and infinity only. NO letters, NO numbers, NO VIP text, NO words, NO logos, NO watermarks, no sparkles, no extra objects. Keep lower left mostly empty for Apple app overlay. Polished friendly 3D product illustration, soft studio lighting, subtle contact shadows, sparse refined composition, no outer rounded corners or frame, not a mockup or sheet.

## Apple 规范

- [推广内购的图片、名称和描述要求](https://developer.apple.com/app-store/promoting-in-app-purchases/)：推广图片采用 1024 × 1024 PNG/JPEG；每项商品使用独立图片；避免左下角放置关键信息；名称最多 30 字符，描述最多 45 字符。
- [新的元数据版本模型](https://developer.apple.com/documentation/appstoreconnectapi/migrating-in-app-purchase-metadata-to-v2)：本地化和图片关联到新的待审核元数据版本。
