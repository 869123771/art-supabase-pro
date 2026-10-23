import cloudbase from '@cloudbase/js-sdk'
import process from 'node:process'

const environmentId = process.env.CLOUDBASE_PROBE_ENV_ID?.trim()
const email = process.env.CLOUDBASE_PROBE_EMAIL?.trim()
const password = process.env.CLOUDBASE_PROBE_PASSWORD
const expectedUid = process.env.CLOUDBASE_PROBE_UID?.trim()

if (!environmentId || !email || !password || !expectedUid) {
  throw new Error('CloudBase probe environment is incomplete')
}

const app = cloudbase.init({ env: environmentId, region: 'ap-shanghai' })
const auth = typeof app.auth === 'function' ? app.auth({ persistence: 'none' }) : app.auth
const signIn = await auth.signInWithPassword({ email, password })
if (signIn.error || signIn.data?.user?.id !== expectedUid) {
  throw new Error('CloudBase password login did not return the expected user', {
    cause: signIn.error
  })
}

const database = (
  app.rdb as unknown as () => {
    from: (table: string) => {
      select: (columns: string) => {
        eq: (
          column: string,
          value: string
        ) => {
          single: () => Promise<{
            data: { id?: string; auth_user_id?: string; tenant_id?: string } | null
            error: Error | null
          }>
        }
      }
    }
  }
)()
const profile = await database
  .from('sys_user')
  .select('id,auth_user_id,tenant_id')
  .eq('auth_user_id', expectedUid)
  .single()
if (profile.error || profile.data?.auth_user_id !== expectedUid || !profile.data.tenant_id) {
  throw new Error('CloudBase PostgreSQL RLS read did not return the probe profile', {
    cause: profile.error
  })
}

await auth.signOut()
process.stdout.write(`${JSON.stringify({ auth: 'ok', postgres: 'ok', tenantIdPresent: true })}\n`)
