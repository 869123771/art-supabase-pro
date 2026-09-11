// plugins/nojekyll.ts
import fs from 'fs'
import path from 'path'
import type { Plugin, ResolvedConfig } from 'vite'

export function createNoJekyllPlugin(fallbackOutDir: string = 'docs'): Plugin {
  let resolvedConfig: ResolvedConfig | undefined

  return {
    name: 'vite-plugin-nojekyll',
    // Only the top-level build owns files in outDir. Worker closeBundle hooks
    // can otherwise recreate this file while Vite is emptying the directory.
    applyToEnvironment: (environment) => !environment.config.isWorker,
    configResolved(config) {
      resolvedConfig = config
    },
    /**
     * 构建完成时创建 .nojekyll 文件
     */
    closeBundle() {
      const root = resolvedConfig?.root ?? process.cwd()
      const outDir = resolvedConfig?.build.outDir ?? fallbackOutDir
      const outputDirectory = path.resolve(root, outDir)
      const nojekyllPath = path.join(outputDirectory, '.nojekyll')

      // 确保输出目录存在
      if (!fs.existsSync(outputDirectory)) {
        fs.mkdirSync(outputDirectory, { recursive: true })
      }

      // 创建 .nojekyll 文件
      fs.writeFileSync(nojekyllPath, '')
      console.log(`✅ Created .nojekyll file in ${outputDirectory} for GitHub Pages`)
    }
  }
}
