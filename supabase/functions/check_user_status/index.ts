import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })

Deno.serve(async (request: Request) => {
  try {
    if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
    if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

    const body = await request.json().catch(() => null)
    const email = String(body?.email ?? '')
      .trim()
      .toLowerCase()
    if (!email) return json({ error: 'Missing email' }, 400)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !serviceRoleKey) return json({ error: 'Server not configured' }, 500)

    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } })
    const { data: user, error: userError } = await admin
      .from('sys_user')
      .select('user_email,status,deleted_at,tenant_id')
      .eq('user_email', email)
      .maybeSingle()

    if (userError) return json({ error: 'Database query failed', detail: userError.message }, 500)
    if (!user) return json({ allowed: true, error: 'not_found' })
    if (user.deleted_at) {
      return json(
        { allowed: false, code: 'user_deactivated', error: '账号已注销，请联系管理员' },
        403
      )
    }
    if (['0', '2'].includes(String(user.status))) {
      return json({ allowed: false, code: 'user_banned', error: '账号已被停用，请联系管理员' }, 403)
    }

    const { data: tenant, error: tenantError } = await admin
      .from('sys_tenant')
      .select('status,service_start_date,service_end_date')
      .eq('id', user.tenant_id)
      .maybeSingle()
    if (tenantError) {
      return json({ error: 'Tenant query failed', detail: tenantError.message }, 500)
    }
    if (!tenant || tenant.status !== '1') {
      return json({ allowed: false, code: 'tenant_disabled', error: '所属租户已停用' }, 403)
    }

    const today = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Shanghai',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit'
    }).format(new Date())
    if (tenant.service_start_date && tenant.service_start_date > today) {
      return json(
        {
          allowed: false,
          code: 'tenant_not_started',
          error: `租户服务将于 ${tenant.service_start_date} 启用`
        },
        403
      )
    }
    if (tenant.service_end_date && tenant.service_end_date < today) {
      return json(
        {
          allowed: false,
          code: 'tenant_expired',
          error: `租户服务已于 ${tenant.service_end_date} 到期，请联系平台续期`
        },
        403
      )
    }

    return json({ allowed: true })
  } catch (error) {
    return json({ error: 'Unexpected error', detail: String(error) }, 500)
  }
})
