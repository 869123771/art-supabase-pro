# ArtUploadImage

统一图片上传和只读预览。单双值模型通过 `modelValue` / `update:modelValue` 同步；业务视图在渲染组件前负责检查附件查看权限。

- `readonly` 使用独立图片区域，保留预览按钮，不渲染上传、资源选择或删除入口。
- 编辑态复用 Element Plus 上传列表，`disabled`、租户目标、文件数量和文件大小限制沿用上传契约。
- 预览按钮使用 Element Plus 图片查看器，可用 Enter / Space 打开，Esc、关闭按钮或遮罩关闭。图片列表直接从当前模型派生，上传中的无 URL 文件不进入预览。
- `resourceTenantId` 指定资源所属租户，`uploadRequest` 可提供业务上传实现；资源选择结果必须属于目标租户。
- `size` 或 `width` / `height` 控制缩略图尺寸，`previewFit` 控制缩略图裁切。多张图片在可用宽度内换行。

只读展示无需传入资源写入目标。不要为了预览而解除业务表单写权限或启用上传。
- 编辑态上传触发器通过 ElUpload trigger 插槽呈现；资源库使用独立 ArtIconButton，禁止将资源按钮嵌入上传触发器。资源入口在未达到图片上限时可用。
