# Platform runtime artifact

`art-supabase-pro-runtime.tgz` 是从主仓已提交的干净工作树执行 `pnpm pack` 生成的公共运行时制品，供独立业务仓安装。它只包含 `package.json`、`src/` 和 `public/`，避免业务子仓为了复用认证、权限、布局和公共组件而下载主仓的历史构建产物。

公共源码仍以主分支为唯一维护入口；公共能力变更后，应从已提交的主仓版本重新生成本制品并更新各业务仓锁文件。
