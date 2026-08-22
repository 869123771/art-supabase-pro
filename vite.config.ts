import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueJsx from '@vitejs/plugin-vue-jsx'
import { existsSync, readdirSync } from 'node:fs'
import path from 'path'
import { fileURLToPath } from 'url'
import vueDevTools from 'vite-plugin-vue-devtools'
import viteCompression from 'vite-plugin-compression'
import Components from 'unplugin-vue-components/vite'
import AutoImport from 'unplugin-auto-import/vite'
import ElementPlus from 'unplugin-element-plus/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'
import tailwindcss from '@tailwindcss/vite'
import { fileViewerRenderers } from '@file-viewer/vite-plugin'
import { visualizer } from 'rollup-plugin-visualizer'
import { getKnownFileViewerExternalization } from './scripts/build-log-policy'
import { createFileViewerAssetSyncPlugin } from './scripts/file-viewer-asset-sync'

// 添加插件用于生成 .nojekyll 文件
import { createNoJekyllPlugin } from './src/plugins/nojekyll'

// import { visualizer } from 'rollup-plugin-visualizer'

const normalizeModuleId = (id: string) => id.replace(/\\/g, '/')

const matchPackages = (id: string, packages: string[]) => {
  const normalizedId = normalizeModuleId(id)
  return packages.some((packageName) => normalizedId.includes(`/node_modules/${packageName}`))
}

const matchFrameworkPackages = (id: string) => {
  const normalizedId = normalizeModuleId(id)
  const packageRoots = [
    'vue',
    'vue-router',
    'vue-i18n',
    'vue-demi',
    'pinia',
    'pinia-plugin-persistedstate'
  ]

  return (
    packageRoots.some((packageName) => normalizedId.includes(`/node_modules/${packageName}/`)) ||
    normalizedId.includes('/node_modules/@vue/') ||
    normalizedId.includes('/node_modules/@vueuse/')
  )
}

const matchBuildRuntime = (id: string) => {
  const normalizedId = normalizeModuleId(id)
  return (
    matchPackages(id, ['@babel/runtime', 'tslib']) ||
    normalizedId.includes('@oxc-project+runtime') ||
    normalizedId.includes('@oxc-project/runtime') ||
    normalizedId.includes('__vite-browser-external') ||
    normalizedId.includes('commonjsHelpers') ||
    normalizedId.includes('vite/preload-helper') ||
    normalizedId.includes('vite/modulepreload-polyfill')
  )
}

const getElementPlusStyleDeps = (root: string): string[] => {
  const componentsDir = path.resolve(root, 'node_modules/element-plus/es/components')
  if (!existsSync(componentsDir)) return []

  return readdirSync(componentsDir, { withFileTypes: true })
    .filter(
      (entry) =>
        entry.isDirectory() && existsSync(path.join(componentsDir, entry.name, 'style/index.mjs'))
    )
    .map((entry) => `element-plus/es/components/${entry.name}/style/index`)
    .sort()
}

export default ({ mode }: { mode: string }) => {
  const root = process.cwd()
  const requiredModuleViews = [
    ['Finance', 'modules/art-supabase-finance/src/views'],
    ['VMS', 'modules/art-supabase-vms/src/views']
  ] as const
  for (const [applicationName, relativeViewsPath] of requiredModuleViews) {
    if (!existsSync(path.resolve(root, relativeViewsPath))) {
      throw new Error(
        `${applicationName} 子仓未初始化，请先运行 git submodule update --init --recursive`
      )
    }
  }
  const env = loadEnv(mode, root)
  const { VITE_VERSION, VITE_PORT, VITE_BASE_URL, VITE_API_URL, VITE_API_PROXY_URL, VITE_OUT_DIR } =
    env
  const isProduction = mode === 'production'
  const isE2E = mode === 'e2e'
  const enableGeneratedDeclarations = !isProduction && !isE2E
  const enableBuildCompression = env.VITE_BUILD_COMPRESS === 'true'
  const enableBundleAnalyzer =
    env.VITE_BUILD_ANALYZE === 'true' || process.env.VITE_BUILD_ANALYZE === 'true'
  const enableVueDevTools = env.VITE_DEVTOOLS === 'true'
  const enableFileViewerPlugin = !isE2E && (isProduction || env.VITE_FILE_VIEWER === 'true')
  const enableFileViewerAssets = !isE2E && (isProduction || env.VITE_FILE_VIEWER_ASSETS === 'true')
  const outDir = process.env.VITE_OUT_DIR || VITE_OUT_DIR || 'dist'
  const fileViewerAssetStageDir = path.resolve(
    root,
    'node_modules/.cache/art-supabase-pro/file-viewer-assets'
  )
  const elementPlusStyleDeps = getElementPlusStyleDeps(root)
  const knownFileViewerExternalizations = new Set<string>()

  console.log(`[vite] API_URL=${VITE_API_URL}`)
  console.log(`[vite] VERSION=${VITE_VERSION}`)
  console.log(`[vite] outDir=${outDir}`)

  return defineConfig({
    // 开发、E2E 与其他模式使用独立依赖缓存，避免并行启动时互相清理预构建文件。
    cacheDir: path.resolve(root, 'node_modules/.vite', mode),
    define: {
      __APP_VERSION__: JSON.stringify(VITE_VERSION)
    },
    base: VITE_BASE_URL,
    server: {
      port: Number(VITE_PORT),
      watch: {
        ignored: ['**/.codex/**', '**/.idea/**', `**/${outDir}/**`, '**/dist/**', '**/dist-ssr/**']
      },
      proxy: {
        '/api': {
          target: VITE_API_PROXY_URL,
          changeOrigin: true
        }
      },
      host: true
    },
    // 路径别名
    resolve: {
      alias: {
        '@finance': resolvePath('modules/art-supabase-finance/src'),
        '@vms': resolvePath('modules/art-supabase-vms/src'),
        '@': fileURLToPath(new URL('./src', import.meta.url)),
        '@views': resolvePath('src/views'),
        '@imgs': resolvePath('src/assets/images'),
        '@icons': resolvePath('src/assets/icons'),
        '@utils': resolvePath('src/utils'),
        '@stores': resolvePath('src/store'),
        '@styles': resolvePath('src/assets/styles')
      }
    },
    build: {
      target: 'es2020',
      outDir, //dist
      modulePreload: {
        polyfill: false,
        resolveDependencies: (_filename, dependencies, context) => {
          if (context.hostType !== 'html') return dependencies
          return dependencies.filter(
            (dependency) =>
              !/(?:media|monaco|rich-editor|data-tools|file-viewer)[.-]/.test(dependency)
          )
        }
      },
      chunkSizeWarningLimit: 7000,
      minify: 'oxc',
      reportCompressedSize: false,
      rolldownOptions: {
        onLog(level, log, defaultHandler) {
          const knownExternalization =
            level === 'warn' ? getKnownFileViewerExternalization(log) : null
          if (knownExternalization) {
            knownFileViewerExternalizations.add(knownExternalization)
            return
          }
          defaultHandler(level, log)
        },
        checks: {
          invalidAnnotation: false,
          pluginTimings: false
        },
        output: {
          codeSplitting: {
            groups: [
              {
                name: 'build-runtime',
                test: matchBuildRuntime,
                priority: 120
              },
              {
                // Keep Vue's runtime out of feature chunks. Otherwise the entry imports
                // Vue helpers from the 15 MB file-viewer chunk and preloads it on every page.
                name: 'framework',
                test: matchFrameworkPackages,
                priority: 100
              },
              {
                // These utilities are shared by Element Plus, tables and feature renderers.
                // Giving them their own chunk prevents a feature chunk becoming their owner.
                name: 'common-utils',
                test: (id) =>
                  matchPackages(id, [
                    'lodash',
                    'lodash-es',
                    'lodash-unified',
                    'dayjs',
                    'sortablejs',
                    'vue-draggable-plus'
                  ]),
                priority: 90
              },
              {
                name: 'media',
                test: (id) => matchPackages(id, ['xgplayer', 'hls.js']),
                priority: 45
              },
              {
                name: 'monaco',
                test: (id) =>
                  matchPackages(id, [
                    'monaco-editor',
                    'monaco-sql-languages',
                    '@guolao/vue-monaco-editor',
                    '@monaco-editor/loader',
                    'state-local'
                  ]),
                priority: 40
              },
              {
                name: 'element-plus',
                test: (id) => matchPackages(id, ['element-plus', '@element-plus']),
                priority: 30
              },
              {
                name: 'charts',
                test: (id) => matchPackages(id, ['echarts', 'zrender']),
                priority: 30
              },
              {
                name: 'rich-editor',
                test: (id) => matchPackages(id, ['@wangeditor']),
                priority: 30
              },
              {
                name: 'data-tools',
                test: (id) =>
                  matchPackages(id, ['xlsx', 'sql-formatter', 'node-sql-parser', 'crypto-js']),
                priority: 20
              }
            ]
          }
        }
      },
      dynamicImportVarsOptions: {
        warnOnError: true,
        exclude: [],
        include: ['src/views/**/*.vue']
      }
    },
    worker: {
      rolldownOptions: {
        checks: {
          invalidAnnotation: false,
          pluginTimings: false
        }
      }
    },
    plugins: [
      vue(),
      vueJsx(),
      tailwindcss(),
      ...(enableFileViewerPlugin
        ? [
            fileViewerRenderers({
              inject: false,
              copyAssets: enableFileViewerAssets
                ? { mode: 'build', outDir: fileViewerAssetStageDir }
                : false,
              // Rolldown's native code splitting already preserves renderer-level lazy chunks.
              // Disabling the plugin's Rollup manualChunks avoids an ignored-option warning.
              chunkStrategy: 'none'
            })
          ]
        : []),
      createFileViewerAssetSyncPlugin({
        enabled: enableFileViewerPlugin && enableFileViewerAssets,
        sourceRoot: fileViewerAssetStageDir
      }),
      {
        name: 'known-file-viewer-browser-external-summary',
        apply: 'build',
        closeBundle() {
          if (!knownFileViewerExternalizations.size) return
          console.warn(
            `[vite] file-viewer 使用 ${knownFileViewerExternalizations.size} 个已知浏览器 external shim：${[
              ...knownFileViewerExternalizations
            ].join(', ')}`
          )
        }
      },
      // 自动按需导入 API
      AutoImport({
        imports: ['vue', 'vue-router', 'pinia', '@vueuse/core'],
        dts: enableGeneratedDeclarations ? 'src/types/import/auto-imports.d.ts' : false,
        resolvers: [ElementPlusResolver({ importStyle: 'sass' })],
        eslintrc: {
          enabled: enableGeneratedDeclarations,
          filepath: './.auto-import.json',
          globalsPropValue: true
        }
      }),
      // 自动按需导入组件
      Components({
        dts: enableGeneratedDeclarations ? 'src/types/import/components.d.ts' : false,
        exclude: [/[\\/]art-data-select[\\/]preview\.vue$/],
        resolvers: [ElementPlusResolver({ importStyle: 'sass' })]
      }),
      // 按需定制主题配置
      ElementPlus({
        useSource: true
      }),
      // 压缩
      ...(enableBuildCompression
        ? [
            viteCompression({
              verbose: false, // 是否在控制台输出压缩结果
              disable: false, // 是否禁用
              algorithm: 'gzip', // 压缩算法
              ext: '.gz', // 压缩后的文件名后缀
              threshold: 10240, // 只有大小大于该值的资源会被处理 10240B = 10KB
              deleteOriginFile: false // 压缩后是否删除原文件
            })
          ]
        : []),
      ...(!isProduction && !isE2E && enableVueDevTools ? [vueDevTools()] : []),
      // 创建 .nojekyll 文件，禁用 Jekyll 处理
      createNoJekyllPlugin(outDir),
      ...(enableBundleAnalyzer
        ? [
            visualizer({
              filename: '.bundle-stats.html',
              open: false,
              gzipSize: true,
              brotliSize: true
            })
          ]
        : [])
      // 打包分析
      // visualizer({
      //   open: true,
      //   gzipSize: true,
      //   brotliSize: true,
      //   filename: 'dist/stats.html' // 分析图生成的文件名及路径
      // }),
    ],
    // 依赖预构建：避免运行时重复请求与转换，提升首次加载速度
    optimizeDeps: {
      entries: ['index.html', 'src/views/**/*.vue'],
      ignoreOutdatedRequests: true,
      // Element Plus 的按需样式入口会导入 Sass 源码。让 Vite 直接按需处理它们，
      // 避免懒加载页面首次访问时触发依赖重优化和整页刷新。
      exclude: elementPlusStyleDeps,
      include: [
        'echarts/core',
        'echarts/charts',
        'echarts/components',
        'echarts/renderers',
        'xlsx',
        'xgplayer',
        'crypto-js',
        'file-saver',
        'vue-img-cutter',
        'element-plus/es',
        // 预打包 Monaco Editor 的核心和语言 Worker 文件
        'monaco-editor/esm/vs/editor/editor.worker',
        'monaco-editor/esm/vs/language/json/json.worker',
        'monaco-sql-languages/esm/languages/pgsql/pgsql.worker.js'
      ]
    },
    css: {
      preprocessorOptions: {
        // sass variable and mixin
        scss: {
          additionalData: `
            @use "@styles/core/el-light.scss" as elementTheme;
            @use "@styles/core/mixin.scss" as *;
          `
        }
      },
      postcss: {
        plugins: [
          {
            postcssPlugin: 'internal:charset-removal',
            AtRule: {
              charset: (atRule) => {
                if (atRule.name === 'charset') {
                  atRule.remove()
                }
              }
            }
          }
        ]
      }
    }
  })
}

function resolvePath(paths: string) {
  return path.resolve(__dirname, paths)
}
