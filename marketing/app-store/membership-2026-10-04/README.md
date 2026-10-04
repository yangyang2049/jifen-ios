# App Store Connect 内购与会员本地化 · 2026-10-04

目标应用：`6759768784` · `com.douhua.jifen.ios`。

2026-10-04 13:32（北京时间）已通过 App Store Connect API 完成三个商品和订阅组的 50 语言／地区本地化，350 个文本字段回读一致。三张推广图均为 `COMPLETE`；原有已审核版本的文案、图片和商品配置对照一致。全部内容保存于 `PREPARE_FOR_SUBMISSION` 元数据草稿，没有提审或发布。

随后读取 Apple 图片资源及每个草稿当前选中的图片，并下载 Apple CDN 的 1024 × 1024 PNG，和本地最终图逐像素比较，三张图片的 RGB 像素均完全一致。见 [图片回读核验](../../../artifacts/app-store-membership-20261004/image-verification.json)。

## 商品和素材

| 商品 | Product ID | 推广图 |
| --- | --- | --- |
| 月会员 | `iscoreboard_monthly_vip` | [蓝色皇冠＋日历](images/monthly.png) |
| 年会员 | `iscoreboard_yearly_vip` | [紫色皇冠＋12 格年度日历](images/yearly.png) |
| 终身买断 | `iscoreboard_lifetime_vip` | [金色皇冠＋无限符号](images/lifetime.png) |

三个商品各包含 50 个商店语言／地区的名称和描述；`iscoreboard` 订阅组另有 50 个本地化名称。标题优先复用应用内已审校资源，短描述围绕实际 VIP 权益、续订周期和买断属性撰写。新增短描述尚未经母语人员复核。

名称以 30 字符、描述以 45 字符上限校验，按 UTF-16 计数。源数据在 [metadata.json](metadata.json)，便于审阅的完整对照在 [copy-review.md](copy-review.md)。[prepare.py](prepare.py) 从已审校的应用资源和明确的商店短文案生成材料，没有修改应用内文案。

推广图使用内置 `image_gen.imagegen` 生成，均为 1024 × 1024 不透明 RGB PNG。三张图片无文字、数字、价格和品牌字样，可跨语言复用。见 [图片校验清单](image-manifest.json) 和 [最终提示词](image-prompts.md)。原始生成图片保留，最终图另行导出至 `images/`。

## 上传和验证

使用 [scripts/app_store_membership.py](../../../scripts/app_store_membership.py) 和项目已有的 Admin API 配置。按 Apple 新的版本模型为商品及订阅组创建／复用 `PREPARE_FOR_SUBMISSION` 元数据草稿，向 v2 本地化和图片端点写入；图片通过预留、上传、提交三步完成。

运行入口：

```sh
python3 marketing/app-store/membership-2026-10-04/prepare.py
python3 scripts/app_store_membership.py \
  --config /Users/yangyang/Documents/CERTIFICATES/AppStoreConnect_iScoreboard-localization.json \
  --metadata marketing/app-store/membership-2026-10-04/metadata.json \
  --out-dir artifacts/app-store-membership-20261004 \
  --apply --images
```

省略 `--apply` 时仅导出只读清单。备份和 [上传核对报告](../../../artifacts/app-store-membership-20261004/upload-report.json) 在 `artifacts/app-store-membership-20261004/`；最终状态以报告的 `verified`、语言数、图片 `COMPLETE` 状态、文件标识和大小回读结果为准。图片文件名含本地 MD5 前缀，完整 MD5 记录在本地清单；Apple 新的 v2 图片资源不提供校验和字段。

程序校验应用 Bundle ID、三个商品 Product ID、订阅周期和买断类型；回读核对 300 个商品文本字段、50 个订阅组名称及图片文件标识、大小和处理状态，并对照原有已审核元数据和商品配置。上传的是推广图，而非审核用的应用截图。

[verify_images.py](verify_images.py) 对已完成的上传执行图片回读检查；Apple 保存的原图另备份于 `artifacts/app-store-membership-20261004/apple-processed-images/`。

本任务只编辑元数据草稿，不提交审核、不更改内购推广开关或排序，不更改定价、销售地区、共享设置或应用构建。内购推广图和新语言在通过 Apple 审核后方可成为正式元数据；App Store 展示推广项目还取决于推广配置。

## 官方依据

- [推广图与文案规格](https://developer.apple.com/app-store/promoting-in-app-purchases/)
- [元数据迁移到 v2](https://developer.apple.com/documentation/appstoreconnectapi/migrating-in-app-purchase-metadata-to-v2)
- [内购元数据版本](https://developer.apple.com/documentation/appstoreconnectapi/working-with-in-app-purchase-versions)
- [订阅元数据版本](https://developer.apple.com/documentation/appstoreconnectapi/working-with-subscription-versions)
- [订阅组元数据版本](https://developer.apple.com/documentation/appstoreconnectapi/working-with-subscription-group-versions)
