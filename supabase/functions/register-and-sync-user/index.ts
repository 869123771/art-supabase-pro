import { createClient } from "npm:@supabase/supabase-js@2.35.0"
import { v4 as uuidv4 } from "npm:uuid@9.0.0"

const allowedOrigins = ["http://localhost:3006", "https://ckbftoopuyophiebamwy.supabase.co"]

function getOriginAllowed(origin: string | null) {
  if (!origin) return null
  if (allowedOrigins.includes(origin)) return origin
  return null
}

function corsHeaders(origin: string | null) {
  const allowed = getOriginAllowed(origin) !== null
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With, apikey, x-client-info",
    "Access-Control-Max-Age": "86400",
  }
  if (allowed) {
    headers["Access-Control-Allow-Origin"] = origin as string
    headers["Access-Control-Allow-Credentials"] = "true"
    headers["Vary"] = "Origin"
  } else {
    headers["Access-Control-Allow-Origin"] = "*"
  }
  return headers
}

async function json(req: Request) {
  try { return await req.json() } catch { return {} }
}

function cleanAppUserData(appUserData: any): any {
  if (!appUserData || typeof appUserData !== "object") return {}
  const cleaned = { ...appUserData }
  delete cleaned.password
  delete cleaned.confirm_password
  delete cleaned.action
  delete cleaned.email
  return cleaned
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } })
const supabaseDB = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } })

async function ensureAuditTable() {
  const sql = `CREATE TABLE IF NOT EXISTS public.sync_user_audit (
    id uuid PRIMARY KEY,
    request_id uuid,
    action text,
    input jsonb,
    previous jsonb,
    result jsonb,
    created_at timestamptz default now()
  );`
  try { await supabaseDB.rpc("sql", { q: sql }) } catch { /* ignore legacy helper absence */ }
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin")
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) })

  const requestId = uuidv4()
  const body = await json(req)
  const auditId = uuidv4()
  const action = "create"

  try { await ensureAuditTable() } catch { /* ignore */ }
  try { await supabaseDB.from("sync_user_audit").insert([{ id: auditId, request_id: requestId, action, input: body }]) } catch (e) { console.error("Audit insert error:", e) }

  try {
    const email = body.email
    const appUserData = body.app_user_data || body
    if (!email) return new Response(JSON.stringify({ ok: false, error: "email required" }), { status: 400, headers: corsHeaders(origin) })

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    if (!emailRegex.test(email)) return new Response(JSON.stringify({ ok: false, error: "Invalid email format" }), { status: 400, headers: corsHeaders(origin) })

    const password = appUserData.password || body.password || uuidv4().slice(0, 12)
    if (password.length < 6) return new Response(JSON.stringify({ ok: false, error: "Password must be at least 6 characters" }), { status: 400, headers: corsHeaders(origin) })

    const { data: authUser, error: authErr } = await supabaseAdmin.auth.admin.createUser({ email, password, email_confirm: true })
    if (authErr) {
      const duplicateErrors = ["user_already_exists", "duplicate key", "Email already registered", "already exists"]
      const isDuplicate = duplicateErrors.some((keyword) => authErr.code === keyword || (authErr.message || "").includes(keyword))
      return new Response(JSON.stringify({ ok: false, error: isDuplicate ? "Email already registered" : `Failed to create user: ${authErr.message}` }), { status: isDuplicate ? 400 : 500, headers: corsHeaders(origin) })
    }

    const authUserId = authUser.user.id
    const cleanedData = cleanAppUserData(appUserData)
    const userRoles = Array.isArray(cleanedData.user_roles) && cleanedData.user_roles.length > 0 ? cleanedData.user_roles : ["R_REGISTER"]
    const insertData: any = { ...cleanedData, auth_user_id: authUserId, user_email: email, user_roles: userRoles, user_type: "2", create_by: email }
    delete insertData.password

    const { data: created, error: insertErr } = await supabaseDB.from("sys_user").insert(insertData).select().single()
    if (insertErr) {
      await supabaseAdmin.auth.admin.deleteUser(authUserId).catch((delErr) => console.error(`[ERROR] Rollback auth user failed: ${delErr.message}`))
      return new Response(JSON.stringify({ ok: false, error: `Failed to create app user: ${insertErr.message}` }), { status: 500, headers: corsHeaders(origin) })
    }

    try { await supabaseDB.from("sync_user_audit").update({ result: { ok: true, auth_user_id: authUserId, app_user: created } }).eq("id", auditId) } catch (e) { console.error("Audit update error (create):", e) }
    return new Response(JSON.stringify({ ok: true, auth_user_id: authUserId, app_user: created }), { status: 200, headers: corsHeaders(origin) })
  } catch (e) {
    const errorMsg = (e as Error).message || String(e)
    try { await supabaseDB.from("sync_user_audit").update({ result: { ok: false, error: errorMsg } }).eq("id", auditId) } catch (auditErr) { console.error("Audit update error (global catch):", auditErr) }
    return new Response(JSON.stringify({ ok: false, error: errorMsg }), { status: 500, headers: corsHeaders(origin) })
  }
})
