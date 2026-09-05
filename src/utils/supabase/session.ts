import type { Session } from '@supabase/supabase-js'
import { supabase } from '@/plugins/supabase'

export const SUPABASE_SESSION_EXPIRED_MESSAGE = '登录状态已失效，请重新登录'

type SessionExpiredHandler = () => boolean | Promise<boolean>

let refreshSessionPromise: Promise<Session | null> | null = null
let sessionExpiredHandler: SessionExpiredHandler | null = null
let sessionExpiredHandlingPromise: Promise<boolean> | null = null
let sessionExpiryHandled = false

/**
 * 并发请求共用一次刷新，防止多个页面初始化时争抢同一个 refresh token。
 * 返回恢复后的 Session；明确无法恢复时返回 null。
 */
export async function refreshSupabaseSessionOnce(): Promise<Session | null> {
  if (!refreshSessionPromise) {
    refreshSessionPromise = supabase.auth
      .refreshSession()
      .then(({ data, error }) => {
        if (error || !data.session) return null
        sessionExpiryHandled = false
        return data.session
      })
      .catch(() => null)
      .finally(() => {
        refreshSessionPromise = null
      })
  }

  return refreshSessionPromise
}

/** 注册应用层的统一失效处理，低层请求工具无需反向依赖 Pinia 或路由。 */
export function registerSupabaseSessionExpiredHandler(handler: SessionExpiredHandler): () => void {
  sessionExpiredHandler = handler

  return () => {
    if (sessionExpiredHandler === handler) sessionExpiredHandler = null
  }
}

/** 多个并发 401 只触发一次清理、提示和登录页跳转。 */
export async function notifySupabaseSessionExpired(): Promise<boolean> {
  if (sessionExpiryHandled) return true
  if (!sessionExpiredHandler) return false

  if (!sessionExpiredHandlingPromise) {
    sessionExpiredHandlingPromise = Promise.resolve(sessionExpiredHandler())
      .then((handled) => {
        sessionExpiryHandled = handled
        return handled
      })
      .finally(() => {
        sessionExpiredHandlingPromise = null
      })
  }

  return sessionExpiredHandlingPromise
}

/** 新会话建立后允许后续独立的失效事件再次触发统一处理。 */
export function markSupabaseSessionActive(): void {
  sessionExpiryHandled = false
}
