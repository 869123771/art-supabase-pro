# UI 视觉回归

视觉回归覆盖 Dashboard、在途监控、发票管理、Supabase AI 助手和 ArtTableQuery 示例页，分别使用 1440×900、1280×800 和 390×844 视口。

测试默认通过独立的 `41737` 端口预览仓库 `docs` 部署产物。源码 UI 发生变化后，先构建再生成或确认新基线：

```powershell
pnpm.cmd exec playwright install chromium
pnpm.cmd build
pnpm.cmd test:e2e:update
```

日常验证：

```powershell
pnpm.cmd test:e2e
```

测试准备阶段通过 Supabase 密码认证建立隔离会话，避免 Cloudflare Turnstile 阻断自动化。默认读取登录页自带的演示账号；需要覆盖账号、远程地址或本机浏览器通道时设置环境变量：

```powershell
$env:E2E_EMAIL='your-account@example.com'
$env:E2E_PASSWORD='your-password'
$env:E2E_BASE_URL='https://your-preview.example.com'
$env:E2E_BROWSER_CHANNEL='chrome'
pnpm.cmd test:e2e
```

失败时使用 `pnpm.cmd test:e2e:report` 查看截图差异与 Trace。认证状态只保存在被 Git 忽略的 `playwright/.auth/`。
