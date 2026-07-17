# 一键同步远端 Supabase 到本地

这个目录的 `sync-remote-to-local.ps1` 会完成两件事：

1. 将远端数据库 schema 导出为本地 baseline 迁移文件。
2. 完整备份远端数据库、Storage 文件、Edge Functions 和项目元数据到 `supabase/backups/`。

它不会打印、写入或提交数据库密码。Edge Function 的 secret **值**无法从 Supabase 导出，备份仅记录其名称；OAuth、SMTP、域名等 Dashboard-only 设置也必须单独记录。

## 运行

1. 启动 Docker Desktop，等待状态显示 **Engine running**。
2. 在项目根目录打开 PowerShell：

   ```powershell
   cd D:\spa\art-supabase-pro
   .\supabase\sync-remote-to-local.ps1
   ```

3. 在密码提示处输入数据库密码。PowerShell 不会显示输入内容。

脚本会复用当前项目已有的 Supabase link，不会每次调用 Management API。首次使用且项目未链接时，才会执行 `supabase link`。

数据库 pooler 主机名无法被本机 DNS 解析时，脚本会通过 DNS-over-HTTPS 临时解析 IP，并使用 TLS 加密的直连 URL 进行数据库导出；不会把密码写入文件。
Windows 已启用系统代理时，脚本会先将该代理用于本次 PowerShell 进程的 DNS-over-HTTPS、Supabase API 请求；不会更改系统代理配置。
Storage 下载会先尝试 Supabase CLI；如果 CLI 在 Windows 上把路径误判成“本地到本地”并报 `Unsupported operation`，脚本会自动改用 Storage API 递归下载 bucket 文件。service role key 只在内存里临时使用，不会写入备份目录。

成功时，终端会显示 baseline SQL 路径和 `manifest.json` 路径。

## 结果位置

- `supabase/migrations/<timestamp>_baseline.sql`：可提交到 Git 的数据库 schema baseline。
- `supabase/remote-migration-history.txt`：执行前远端迁移历史的快照。
- `supabase/backups/<timestamp>/`：完整逻辑备份；其中 `manifest.json` 存在才表示备份完整。

`backups/` 已被 Git 忽略，因为它包含业务数据和 Storage 文件。请把它另外保存到加密存储，不要提交。

## 失败处理

### Docker 或 DNS 报错

若看到 `public.ecr.aws`、`pooler.supabase.com` 或 Docker 拉取镜像的 DNS 错误，先不要重试迁移。先确认：

```powershell
Resolve-DnsName public.ecr.aws -Type A
docker pull public.ecr.aws/supabase/postgres:17.6.1.062
```

这两条必须成功。若本机使用代理软件，也要保持代理软件运行，并在 Docker Desktop 中启用相应的代理设置。

### 远程历史存在、本地没有迁移文件

脚本会停止，不会自动运行 `supabase migration repair --status reverted`。这是保护措施：该操作会改写远端迁移历史，必须先人工审查 `remote-migration-history.txt`。

### 已经有 baseline，只想再做备份

```powershell
.\supabase\sync-remote-to-local.ps1 -SkipBaseline
```

## 验证

```powershell
Get-ChildItem .\supabase\migrations -Filter '*.sql' | Select-Object Name, Length
supabase migration list --linked
Get-ChildItem .\supabase\backups -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
```

baseline 的 Local 与 Remote 版本应一致；最新备份目录必须有 `manifest.json`。

如果脚本在 `Capturing deployed Edge Function source and metadata...` 之后提示
`api.supabase.com: no such host`，这是本机 DNS/代理问题。脚本会自动复用 Windows
系统代理；请确认代理软件正在运行，并且 Windows 的系统代理已启用，然后重新运行脚本。
失败时新建的备份目录没有 `manifest.json`，属于不完整备份，不能用于恢复。

`supabase secrets list` 偶尔会因管理 API 返回 `EOF` 而失败。脚本会自动重试 3 次；
仍失败时会在 `edge-function-secret-names.json` 记录错误并继续。Supabase 本身无法导出
Secret 值，因此恢复时始终需要手工重新录入全部 Secret 值。
