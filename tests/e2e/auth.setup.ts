import fs from 'node:fs'
import { mkdir } from 'node:fs/promises'
import path from 'node:path'
import { createClient } from '@supabase/supabase-js'
import { expect, test as setup } from '@playwright/test'
import { loadEnv } from 'vite'

const authFile = path.join(process.cwd(), 'playwright', '.auth', 'user.json')
const packageVersion = JSON.parse(fs.readFileSync('package.json', 'utf8')).version as string

function readDemoCredentials(): { email: string; password: string } {
  const loginSource = fs.readFileSync('src/views/auth/login/index.vue', 'utf8')
  const email = process.env.E2E_EMAIL || loginSource.match(/email:\s*'([^']+)'/)?.[1]
  const password = process.env.E2E_PASSWORD || loginSource.match(/password:\s*'([^']+)'/)?.[1]

  if (!email || !password) {
    throw new Error('请通过 E2E_EMAIL 和 E2E_PASSWORD 提供视觉回归账号')
  }
  return { email, password }
}

setup('登录并保存视觉回归会话', async ({ page }) => {
  setup.setTimeout(90_000)
  await mkdir(path.dirname(authFile), { recursive: true })

  const env = loadEnv('development', process.cwd(), '')
  const supabaseUrl = env.VITE_SUPABASE_URL
  const supabaseKey = env.VITE_SUPABASE_KEY
  if (!supabaseUrl || !supabaseKey) {
    throw new Error('缺少 VITE_SUPABASE_URL 或 VITE_SUPABASE_KEY')
  }

  const authClient = createClient(supabaseUrl, supabaseKey, {
    auth: { persistSession: false }
  })
  const { data, error } = await authClient.auth.signInWithPassword(readDemoCredentials())
  expect(error?.message, 'Supabase 测试账号登录失败').toBeUndefined()
  expect(data.session, 'Supabase 未返回测试会话').toBeTruthy()

  const session = data.session!
  const projectRef = new URL(supabaseUrl).hostname.split('.')[0]
  await page.goto('/#/auth/login')
  await page.evaluate(
    ({ storageKey, userStoreKey, sessionData }) => {
      localStorage.setItem(storageKey, JSON.stringify(sessionData))
      localStorage.setItem(
        userStoreKey,
        JSON.stringify({
          accessToken: sessionData.access_token,
          isLogin: true,
          refreshToken: sessionData.refresh_token
        })
      )

      for (const key of Object.keys(localStorage)) {
        if (!/^sys-v.+-setting$/.test(key)) continue
        const setting = JSON.parse(localStorage.getItem(key) || '{}') as Record<string, unknown>
        localStorage.setItem(
          key,
          JSON.stringify({
            ...setting,
            pageTransition: '',
            showSettingGuide: false
          })
        )
      }
    },
    {
      storageKey: `sb-${projectRef}-auth-token`,
      userStoreKey: `sys-v${env.VITE_VERSION || packageVersion}-user`,
      sessionData: session
    }
  )

  await page.reload({ waitUntil: 'domcontentloaded' })
  await page.goto('/#/dashboard/console')
  await expect(page).not.toHaveURL(/#\/auth\/login/, { timeout: 30_000 })
  await page.context().storageState({ path: authFile })
})
