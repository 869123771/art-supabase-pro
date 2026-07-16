import { createClient } from "npm:@supabase/supabase-js@2.45.4"

type SysUser = {
  id: string
  auth_user_id: string | null
  tenant_id: string
  user_name: string | null
  nick_name: string | null
  user_phone: string | null
  user_email: string | null
  status: string | null
}

type Driver = {
  id: string
  tenant_id: string
  carrier_id: string | null
  driver_name: string | null
  phone: string | null
  enabled: boolean | null
}

type TmsOrder = {
  id: string
  tenant_id: string
  order_no: string
  cargo_no: string | null
  order_status: string | null
  dispatch_status: string | null
  dispatch_driver_id: string | null
  dispatch_driver_phone: string | null
  dispatch_vehicle_id: string | null
  origin_station: string | null
  destination_station: string | null
  shipping_contact_name: string | null
  shipping_contact_phone: string | null
  shipping_address_detail: string | null
  receiving_contact_name: string | null
  receiving_contact_phone: string | null
  receiving_address_detail: string | null
  planned_departure_time: string | null
  planned_arrival_time: string | null
  dispatched_at: string | null
  signed_at: string | null
  cargo_items: Array<Record<string, unknown>> | null
  cargo_quantity_total: number | string | null
  cargo_weight_total: number | string | null
  cargo_volume_total: number | string | null
  total_fee: number | string | null
  receipt_image_urls: unknown[] | null
  create_by: string | null
  create_time: string | null
  update_by: string | null
  update_time: string | null
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || readKeyMap("SUPABASE_SECRET_KEYS")

const admin = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } })

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
}

function readKeyMap(name: string) {
  const raw = Deno.env.get(name)
  if (!raw) return ""
  try {
    return JSON.parse(raw).default || ""
  } catch {
    return ""
  }
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: corsHeaders })
}

function getBearer(req: Request) {
  const header = req.headers.get("authorization") || ""
  return header.toLowerCase().startsWith("bearer ") ? header.slice(7).trim() : ""
}

function getStringMeta(source: Record<string, unknown> | undefined, keys: string[]) {
  if (!source) return ""
  for (const key of keys) {
    const value = source[key]
    if (typeof value === "string" && value.trim()) return value.trim()
  }
  return ""
}

function getAuthPhone(authUser: { phone?: string; user_metadata?: Record<string, unknown>; app_metadata?: Record<string, unknown> }) {
  return (
    authUser.phone ||
    getStringMeta(authUser.user_metadata, ["phone", "user_phone", "mobile", "tel"]) ||
    getStringMeta(authUser.app_metadata, ["phone", "user_phone", "mobile", "tel"])
  )
}

function numberOrNull(value: unknown) {
  if (value === null || value === undefined || value === "") return null
  const number = Number(value)
  return Number.isFinite(number) ? number : null
}

function mapStatus(order: TmsOrder) {
  if (order.dispatch_status === "cancelled" || order.order_status === "cancelled") return "cancelled"
  if (order.signed_at) return "completed"
  if (order.dispatch_status === "loading") return "loading"
  if (order.dispatch_status === "transporting") return "transporting"
  if (order.dispatch_status === "unloading") return "unloading"
  if (order.dispatch_status === "loaded" || order.dispatch_status === "dispatched") return "accepted"
  return "pending"
}

function mapOrderToWaybill(order: TmsOrder, driver: Driver) {
  const firstCargo = Array.isArray(order.cargo_items) ? order.cargo_items[0] || {} : {}
  const status = mapStatus(order)
  const receiptFiles = Array.isArray(order.receipt_image_urls)
    ? order.receipt_image_urls.map((url) => (typeof url === "string" ? { url } : url)).filter(Boolean)
    : []
  const cargoWeight = numberOrNull(order.cargo_weight_total)

  return {
    tenant_id: order.tenant_id,
    waybill_no: order.order_no,
    status,
    carrier_id: driver.carrier_id,
    driver_id: driver.id,
    vehicle_id: order.dispatch_vehicle_id,
    origin_city: order.origin_station || "",
    destination_city: order.destination_station || "",
    shipper_name: order.shipping_contact_name,
    shipper_phone: order.shipping_contact_phone,
    shipper_address: order.shipping_address_detail || "",
    receiver_name: order.receiving_contact_name,
    receiver_phone: order.receiving_contact_phone,
    receiver_address: order.receiving_address_detail || "",
    planned_load_time: order.planned_departure_time,
    planned_unload_time: order.planned_arrival_time,
    accepted_at: ["accepted", "loading", "transporting", "unloading", "completed"].includes(status)
      ? order.dispatched_at
      : null,
    completed_at: status === "completed" ? order.signed_at : null,
    cancelled_at: status === "cancelled" ? order.update_time || new Date().toISOString() : null,
    cargo_name: String(firstCargo.cargo_name || order.cargo_no || "货物"),
    cargo_type: firstCargo.package_type ? String(firstCargo.package_type) : null,
    cargo_weight_ton: cargoWeight === null ? null : cargoWeight / 1000,
    cargo_volume_m3: numberOrNull(order.cargo_volume_total),
    cargo_quantity: order.cargo_quantity_total === null || order.cargo_quantity_total === undefined
      ? null
      : String(order.cargo_quantity_total),
    freight_amount: numberOrNull(order.total_fee) || 0,
    route_points: [],
    pickup_photos: [],
    delivery_photos: status === "completed" ? receiptFiles : [],
    receipt_attachments: status === "completed" ? receiptFiles : [],
    remark: `synced from tms_order ${order.id}`,
    create_by: order.create_by,
    create_time: order.create_time || new Date().toISOString(),
    update_by: order.update_by,
    update_time: new Date().toISOString(),
  }
}

async function getCurrentUser(req: Request) {
  const token = getBearer(req)
  if (!token) throw new Error("缺少登录凭证")
  const { data, error } = await admin.auth.getUser(token)
  if (error || !data.user) throw new Error("登录已失效，请重新登录")
  return data.user
}

async function getSysUser(authUser: { id: string; email?: string; phone?: string }) {
  const filters = [
    `auth_user_id.eq.${authUser.id}`,
    authUser.email ? `user_email.eq.${authUser.email}` : "",
    authUser.phone ? `user_phone.eq.${authUser.phone}` : "",
  ].filter(Boolean)

  const { data, error } = await admin
    .from("sys_user")
    .select("id,auth_user_id,tenant_id,user_name,nick_name,user_phone,user_email,status")
    .or(filters.join(","))
    .order("create_time", { ascending: false })
    .limit(1)

  if (error) throw error
  const user = (data || [])[0] as SysUser | undefined
  if (!user) throw new Error("当前账号未绑定系统用户")
  return user
}

async function getDriver(user: SysUser, authUser: { phone?: string; user_metadata?: Record<string, unknown>; app_metadata?: Record<string, unknown> }) {
  const phone = user.user_phone || getAuthPhone(authUser)
  if (!phone) throw new Error("当前账号未绑定手机号")

  const { data, error } = await admin
    .from("tms_driver")
    .select("id,tenant_id,carrier_id,driver_name,phone,enabled,create_time")
    .eq("phone", phone)
    .eq("enabled", true)
    .order("create_time", { ascending: false })
    .limit(1)

  if (error) throw error
  const driver = (data || [])[0] as Driver | undefined
  if (!driver) throw new Error("当前手机号未绑定启用的司机档案")
  return driver
}

async function getDispatchedOrders(driver: Driver) {
  const phone = driver.phone || ""
  const { data, error } = await admin
    .from("tms_order")
    .select(
      "id,tenant_id,order_no,cargo_no,order_status,dispatch_status,dispatch_driver_id,dispatch_driver_phone,dispatch_vehicle_id,origin_station,destination_station,shipping_contact_name,shipping_contact_phone,shipping_address_detail,receiving_contact_name,receiving_contact_phone,receiving_address_detail,planned_departure_time,planned_arrival_time,dispatched_at,signed_at,cargo_items,cargo_quantity_total,cargo_weight_total,cargo_volume_total,total_fee,receipt_image_urls,create_by,create_time,update_by,update_time",
    )
    .eq("tenant_id", driver.tenant_id)
    .or(`dispatch_driver_id.eq.${driver.id},dispatch_driver_phone.eq.${phone}`)
    .in("dispatch_status", ["loaded", "dispatched", "loading", "transporting", "unloading"])
    .order("create_time", { ascending: false })

  if (error) throw error
  return (data || []) as TmsOrder[]
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders })
  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed" }, 405)

  try {
    const authUser = await getCurrentUser(req)
    const sysUser = await getSysUser({ id: authUser.id, email: authUser.email || undefined, phone: authUser.phone || undefined })
    const driver = await getDriver(sysUser, authUser)
    const orders = await getDispatchedOrders(driver)

    if (orders.length === 0) return json({ ok: true, synced: 0, waybillNos: [] })

    const waybills = orders.map((order) => mapOrderToWaybill(order, driver))
    const { data, error } = await admin
      .from("tms_waybill")
      .upsert(waybills, { onConflict: "tenant_id,waybill_no" })
      .select("waybill_no")

    if (error) throw error
    return json({ ok: true, synced: data?.length || 0, waybillNos: (data || []).map((row) => row.waybill_no) })
  } catch (error) {
    const message = error instanceof Error ? error.message : "同步运单失败"
    console.error("sync-driver-waybills error", message)
    return json({ ok: false, error: message }, 500)
  }
})
