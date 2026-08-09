import { createClient } from "npm:@supabase/supabase-js@2.34.0"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
    if (req.method !== "POST") return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const body = await req.json().catch(() => null)
    const email = (body?.email || "").toString().trim().toLowerCase()
    if (!email) return new Response(JSON.stringify({ error: "Missing email" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const supabaseUrl = Deno.env.get("SUPABASE_URL")
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    if (!supabaseUrl || !serviceRoleKey) return new Response(JSON.stringify({ error: "Server not configured" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } })
    const { data, error } = await admin.from("sys_user").select("user_email, status, deleted_at").eq("user_email", email).maybeSingle()

    if (error) return new Response(JSON.stringify({ error: "Database query failed", detail: error.message }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    if (!data) return new Response(JSON.stringify({ allowed: true, error: "not_found" }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    if (data.deleted_at) return new Response(JSON.stringify({ allowed: false, code: "user_deactivated", error: "账号已注销，请联系管理员", message: "账号已注销，请联系管理员" }), { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    if (["0", "2"].includes(String(data.status))) return new Response(JSON.stringify({ allowed: false, code: "user_banned", error: "账号已被禁用，请联系管理员", message: "账号已被禁用，请联系管理员" }), { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    return new Response(JSON.stringify({ allowed: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  } catch (err) {
    return new Response(JSON.stringify({ error: "Unexpected error", detail: String(err) }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})
