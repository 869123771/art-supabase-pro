// plugins/nojekyll.ts
import fs from 'fs'
import path from 'path'
import type { Plugin } from 'vite'

export function createNoJekyllPlugin(outDir: string = 'docs'): Plugin {
  return {
    name: 'vite-plugin-nojekyll',
    // Only the top-level build owns files in outDir. Worker closeBundle hooks
    // can otherwise recreate this file while Vite is emptying the directory.
    applyToEnvironment: (environment) => !environment.config.isWorker,
    /**
     * 构建完成时创建 .nojekyll 文件
     */
    closeBundle() {
      const nojekyllPath = path.resolve(outDir, '.nojekyll')

      // 确保输出目录存在
      if (!fs.existsSync(outDir)) {
        fs.mkdirSync(outDir, { recursive: true })
      }

      // 创建 .nojekyll 文件
      fs.writeFileSync(nojekyllPath, '')
      console.log(`✅ Created .nojekyll file in ${outDir}/ for GitHub Pages`)
    }
  }
}
