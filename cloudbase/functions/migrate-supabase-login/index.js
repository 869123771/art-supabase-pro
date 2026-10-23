'use strict'

const http = require('node:http')
const managerPackage = require('@cloudbase/manager-node')
const { createClient } = require('@supabase/supabase-js')

const CloudBase = managerPackage.CloudBase || managerPackage.default || managerPackage

const ENVIRONMENT_ID = process.env.CLOUDBASE_ENV_ID || process.env.TCB_ENV || ''
const SOURCE_URL = process.env.SOURCE_SUPABASE_URL || ''
const SOURCE_ANON_KEY = process.env.SOURCE_SUPABASE_ANON_KEY || ''
const PHONE_PATTERN = /^1\d{10}$/u

const fail = (code, message) => ({ ok: false, code, message })

const readPayload = (event) => {
  if (!event || typeof event !== 'object') return null
  if (event.body && typeof event.body === 'string') {
    try {
      return JSON.parse(event.body)
    } catch {
      return null
    }
  }
  return event
}

const migrateLogin = async (event) => {
  const payload = readPayload(event)
  const identifier = typeof payload?.identifier === 'string' ? payload.identifier.trim() : ''
  const password = typeof payload?.password === 'string' ? payload.password : ''
  const captchaToken =
    typeof payload?.captchaToken === 'string' && payload.captchaToken.trim()
      ? payload.captchaToken.trim()
      : undefined

  if ((!identifier.includes('@') && !PHONE_PATTERN.test(identifier)) || !password) {
    return fail('invalid_credentials', '账号或密码错误')
  }
  if (!ENVIRONMENT_ID || !SOURCE_URL || !SOURCE_ANON_KEY) {
    return fail('server_misconfigured', '登录迁移服务尚未配置')
  }

  const source = createClient(SOURCE_URL, SOURCE_ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false }
  })
  let sourceUserId
  if (identifier.includes('@')) {
    const { data, error } = await source.auth.signInWithPassword({
      email: identifier.toLowerCase(),
      password,
      options: { captchaToken }
    })
    if (error || !data.user?.id) return fail('invalid_credentials', '账号或密码错误')
    sourceUserId = data.user.id
  } else {
    const { data, error } = await source.functions.invoke('login-with-phone', {
      body: { phone: identifier, password, captchaToken }
    })
    const accessToken = data?.session?.accessToken
    if (error || typeof accessToken !== 'string') {
      return fail('invalid_credentials', '账号或密码错误')
    }
    const userResult = await source.auth.getUser(accessToken)
    if (userResult.error || !userResult.data.user?.id) {
      return fail('invalid_credentials', '账号或密码错误')
    }
    sourceUserId = userResult.data.user.id
  }

  try {
    const managerConfig = {
      envId: ENVIRONMENT_ID,
      accessKey: process.env.CLOUDBASE_APIKEY,
      secretId: process.env.TENCENTCLOUD_SECRETID,
      secretKey: process.env.TENCENTCLOUD_SECRETKEY,
      token: process.env.TENCENTCLOUD_SESSIONTOKEN,
      region: process.env.CLOUDBASE_REGION || 'ap-shanghai'
    }
    const manager =
      typeof CloudBase.init === 'function'
        ? CloudBase.init(managerConfig)
        : new CloudBase(managerConfig)
    const result = await manager.user.modifyUser({ uid: sourceUserId, password })
    if (result?.Data?.Success === false) {
      return fail('password_migration_failed', '原密码迁移失败，请联系管理员')
    }
    return { ok: true, uid: sourceUserId }
  } catch (error) {
    const code = typeof error?.code === 'string' ? error.code : ''
    if (/password/i.test(code) || /password/i.test(String(error?.message || ''))) {
      return fail('password_policy_rejected', '原密码不符合新平台规则，请联系管理员处理')
    }
    return fail('password_migration_failed', '原密码迁移失败，请稍后重试')
  } finally {
    await source.auth.signOut().catch(() => undefined)
  }
}

exports.main = migrateLogin

const allowedOrigins = new Set(
  String(process.env.ALLOWED_ORIGINS || '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean)
)

const readJson = (request) =>
  new Promise((resolve, reject) => {
    let content = ''
    request.setEncoding('utf8')
    request.on('data', (chunk) => {
      content += chunk
      if (content.length > 16_384) request.destroy(new Error('Request body is too large'))
    })
    request.on('end', () => {
      try {
        resolve(content ? JSON.parse(content) : {})
      } catch (error) {
        reject(error)
      }
    })
    request.on('error', reject)
  })

if (require.main === module) {
  http
    .createServer(async (request, response) => {
      const origin = request.headers.origin || ''
      const allowedOrigin = allowedOrigins.has(origin) ? origin : ''
      if (allowedOrigin) {
        response.setHeader('Access-Control-Allow-Origin', allowedOrigin)
        response.setHeader('Vary', 'Origin')
      }
      response.setHeader('Content-Type', 'application/json; charset=utf-8')
      response.setHeader('Cache-Control', 'no-store')
      if (request.method === 'OPTIONS') {
        response.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS')
        response.setHeader('Access-Control-Allow-Headers', 'Content-Type')
        response.writeHead(allowedOrigin ? 204 : 403)
        response.end()
        return
      }
      if (request.method !== 'POST' || (origin && !allowedOrigin)) {
        response.writeHead(403)
        response.end(JSON.stringify(fail('forbidden', '请求来源无效')))
        return
      }
      try {
        const result = await migrateLogin(await readJson(request))
        response.writeHead(result.ok ? 200 : 400)
        response.end(JSON.stringify(result))
      } catch {
        response.writeHead(400)
        response.end(JSON.stringify(fail('invalid_request', '请求无效')))
      }
    })
    .listen(Number(process.env.PORT || 9000), '0.0.0.0')
}
