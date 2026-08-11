# UI 视觉回归

视觉回归覆盖 Dashboard、在途监控、发票管理、Supabase AI 助手、AI 项目规划、运单录入、网站配置和 ArtTableQuery 示例页，并配置桌面、平板、移动端、暗色与阴影盒模型环境。

测试默认通过独立的 `41737` 端口预览 `VITE_OUT_DIR` 配置的生产构建；本项目当前输出目录为 `docs`。源码 UI 发生变化后，先构建再生成或确认新基线：

```powershell
pnpm.cmd exec playwright install chromium
pnpm.cmd build
pnpm.cmd test:e2e:update
```

本地默认复用已安装的 Chrome；CI 环境使用 Playwright Chromium，因此流水线初始化阶段仍需执行 `pnpm.cmd test:e2e:install`。

日常验证：

```powershell
pnpm.cmd test:e2e
```

提交前的核心页面快速门禁只运行 1440 桌面与 390 移动端：

```powershell
pnpm.cmd test:e2e:core
```

完整 CI 门禁会依次执行静态检查、项目快照校验、生产构建和核心视觉回归：

```powershell
pnpm.cmd check:ci
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
