# Supabase 远端备份与跨项目恢复

这两个 PowerShell 脚本完成一次**快照迁移**：

```text
原远端项目 ckbftoopuyophiebamwy
        ↓ backup-supabase.ps1
本机 supabase/backups/<时间戳>/
        ↓ restore-supabase.ps1
另一个全新、空白的 Supabase 远端项目
```

“本地”指本机上的备份文件夹，**不是**本机运行的 Supabase 数据库；脚本也不会持续双向同步。两次执行之间，原远端新增的数据不会自动进入已生成的备份。要迁移最新状态，重新执行备份并使用新的备份目录。

## 首次准备

1. 安装 [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) 和 Docker Desktop，启动 Docker Desktop。在 PowerShell 中确认 `supabase --version`、`supabase db query --help`、`docker version` 均可运行。命令参数已按 CLI 2.118.0 核对。脚本通过 Docker 使用 `psql`，无需另外安装 PostgreSQL 客户端。
2. 执行 `supabase login`，登录对原项目和目标项目都有管理权限的账号。
3. 准备原项目的**数据库密码**。它不是 Supabase 登录密码，也不是 API key；在 Supabase Dashboard 的 Database Settings 中管理。
4. 恢复前，先在 Dashboard 创建一个**全新、空白**的目标项目，记录它的 20 位 project ref 和数据库密码。不要把生产项目或已有业务数据的项目当作目标。
5. 从仓库根目录 `D:\spa\art-supabase-pro` 运行以下命令。不要把密码直接写进命令或保存到仓库里；脚本会交互式提示输入。

## 第一步：原远端 → 本地备份

```powershell
Set-Location 'D:\spa\art-supabase-pro'
.\supabase\backup-supabase.ps1
```

输入**原项目**的数据库密码。默认来源是 `ckbftoopuyophiebamwy`。成功后，终端会显示类似 `supabase/backups/20260930-123456` 的绝对路径；记下这个路径。

备份目录由脚本按时间戳新建，不覆盖旧目录。里面有：

| 路径 | 内容 |
| --- | --- |
| `manifest.json` | 来源、时间、文件大小和 SHA-256 校验值 |
| `database/` | 数据库角色、结构、数据、迁移历史，以及 `auth`/`storage` 托管结构参考快照 |
| `storage/` | 各 bucket 的文件内容 |
| `functions/` | 从原远端下载的已部署 Edge Function 源码；没有已部署函数时可以不存在 |
| `metadata/` | bucket、Realtime、函数和 Secret 名称等元数据 |
| `config.toml` | 本仓库的 Supabase CLI 配置副本 |

`supabase/backups/` 已被 Git 忽略。备份包含用户和业务数据，应放在受控、加密的存储中，不要提交、分享或公开。若导出中途报错，**不要使用**那个没有完整 `manifest.json` 的目录；修正错误后重新备份。

## 第二步：先校验本地备份

把下面的时间戳和目标 project ref 换成实际值：

```powershell
.\supabase\restore-supabase.ps1 `
  -BackupPath '.\supabase\backups\20260930-123456' `
  -TargetProjectRef 'abcdefghijklmnopqrst' `
  -VerifyBackupOnly
```

这一步只核对清单、文件完整性和函数目录，不连接或修改任何远端。看到 `Backup verified` 才继续。`TargetProjectRef` 在校验时仅用于检查目标不是备份的来源。

## 第三步：本地备份 → 另一个远端

```powershell
.\supabase\restore-supabase.ps1 `
  -BackupPath '.\supabase\backups\20260930-123456' `
  -TargetProjectRef 'abcdefghijklmnopqrst'
```

输入**目标项目**的数据库密码，再按提示完整输入目标 project ref 确认。脚本会先拒绝来源相同、已有 `public` 表、Auth 用户、Storage 数据或已部署函数的目标，然后导入数据库、Realtime 发布关系、Storage 文件和已部署的 Edge Functions。恢复使用临时工作目录，不会把本仓库当前的 Supabase 链接改为目标项目。

这一步会写入目标项目。数据库导入在一个事务中执行；如果后续 Storage 或函数部署失败，目标可能只完成了一部分。此时应检查错误，并在**新的空项目**上重试完整恢复，不要把同一份备份当作可安全合并到已有项目的增量包。

## 恢复后还要做什么

- 在目标项目重新填写 Edge Function Secrets 的**值**；`metadata/edge-function-secret-names.json` 只有名称，没有值。重新配置 Auth/OAuth、SMTP、邮件模板、站点 URL、回调地址、自定义域名及其他 Dashboard 专属设置。
- 查看 `database/managed-schema-snapshot.sql`，人工核对原项目对 `auth`、`storage` 托管结构做过的自定义策略、触发器等变更；脚本不会自动重放整个托管 schema。如果使用 Vault 或列加密，先按 [Supabase 官方迁移指南](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore) 迁移加密根密钥。自定义 `LOGIN` 角色密码也要单独设置。
- 原项目的函数 import map、`deno.json` 等额外文件可能无法从已部署函数中完整还原。需要时从受控的源代码另行部署。脚本恢复的是**备份时远端已部署**的函数，并不会把此后对仓库 `supabase/functions/` 的本地修改自动发布到目标。
- 检查目标的 API 暴露配置、Storage 文件类型与缓存设置、Realtime、Auth 登录，以及关键业务表数量和租户权限。Storage 的 API 回退上传会使用 `application/octet-stream`，所以特殊 MIME 类型和缓存策略需要复核。
- 要让前端连接新项目，另行更新前端环境中的 Supabase URL 和公开 key；不要把 `service_role` 或 `sb_secret_` key 放进前端。

## 常见问题

- **提示找不到 `supabase`**：先按官方文档安装 CLI，重新打开终端，再运行 `supabase --version`。
- **提示 Docker 未启动**：启动 Docker Desktop，等 `docker version` 成功后重试。
- **PowerShell 禁止执行脚本**：可以仅对本次进程使用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\supabase\backup-supabase.ps1`；恢复时同理替换脚本名并附上参数。
- **目标被判定为非空**：换一个新建的空项目。脚本刻意不提供覆盖或合并模式。
- **需要把数据导入本机运行的 Supabase**：这是另一套流程；这两个脚本只生成本地备份并恢复到另一个云项目。

命令和限制依据：[Supabase 官方备份与恢复指南](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)、[CLI 数据库导出参考](https://supabase.com/docs/reference/cli/supabase-db-dump)、[CLI 函数下载参考](https://supabase.com/docs/reference/cli/supabase-functions-download)、[CLI Storage 拷贝参考](https://supabase.com/docs/reference/cli/supabase-storage-cp)。
