# ArtUploadFile

通用文件附件上传组件。统一处理文件大小校验、上传状态、错误提示、附件列表与 URL 模型同步。

```vue
<ArtUploadFile
  v-model="attachmentUrls"
  multiple
  :limit="8"
  accept=".pdf,.doc,.docx,.xls,.xlsx,.zip,image/*"
  tip="支持文档、压缩包和图片，单个文件不超过 20 MB"
/>
```

- 普通文件、文档和压缩包使用本组件。
- 图片预览上传使用 `ArtUploadImage`。
- 结构化 Excel 导入使用 `ArtExcelImport`。
- 仅需要上传事件时可关闭 `show-file-list`，监听 `upload-success` 获取资源信息。
- 附件名称点击后统一进入公共文件预览页；附件行右侧提供下载、查看和删除操作。
- `readonly` 模式不显示上传触发器和删除操作，仅保留附件名称、下载与查看。
