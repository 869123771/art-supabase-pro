import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function stringFilter(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback
}

Deno.serve(async (req: Request) => {
  try {
    const url = new URL(req.url);
    const method = req.method.toUpperCase();
    const authHeader = req.headers.get('authorization') || '';

    // 校验 Authorization 头格式
    if (!authHeader.toLowerCase().startsWith('bearer ')) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing or invalid Authorization header' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // 提取用户 Token
    const token = authHeader.split(' ')[1];
    if (!token) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing token' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // 读取 Supabase 环境变量
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
    const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!SUPABASE_URL || !SERVICE_ROLE) {
      return new Response(
        JSON.stringify({ success: false, error: 'Server misconfigured' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    if (!anonKey) {
      return new Response(JSON.stringify({ success: false, error: 'Server misconfigured' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      })
    }
    const userClient = createClient(SUPABASE_URL, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false }
    })
    const { data: userData, error: userError } = await userClient.auth.getUser(token)
    if (userError || !userData.user) {
      return new Response(
        JSON.stringify({ success: false, error: 'Invalid token or unable to verify' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      );
    }
    const { data: isSuper, error: permissionError } = await userClient.rpc('current_is_super')
    if (permissionError || isSuper !== true) {
      return new Response(
        JSON.stringify({ success: false, error: 'Forbidden: platform super role required' }),
        { status: 403, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // 解析前端传入的过滤条件
    let filters: Record<string, unknown> = {};
    if (method === 'GET') {
      url.searchParams.forEach((v, k) => { filters[k] = v; });
    } else if (method === 'POST') {
      try {
        const parsed: unknown = await req.json();
        filters = isRecord(parsed) ? parsed : {};
      } catch {
        filters = {};
      }
    }

    // 提取并格式化日志查询参数
    const service = stringFilter(filters.service, 'postgres');
    const requestedLimit = Number(filters.limit ?? 100)
    const limit = Number.isFinite(requestedLimit)
      ? Math.max(1, Math.min(Math.trunc(requestedLimit), 1000))
      : 100
    const since = filters.since;
    const until = filters.until;
    const level = filters.level;
    const status_code = filters.status_code;
    const function_id = filters.function_id;
    const query_text = filters.query_text;
    const order = stringFilter(filters.order, 'desc').toLowerCase();

    // 构造 Supabase Logs API 请求
    const logsBase = `${SUPABASE_URL.replace(/\/$/, '')}/logs/v1`;
    const params = new URLSearchParams();
    params.set('service', service);
    params.set('limit', String(limit));
    if (since) params.set('since', String(since));
    if (until) params.set('until', String(until));
    if (order) params.set('order', order);

    // 代理请求 Supabase 日志接口（此处保留 SERVICE_ROLE 授权，是正确的）
    const logsRes = await fetch(`${logsBase}?${params.toString()}`, {
      method: 'GET',
      headers: { 
        'Authorization': `Bearer ${SERVICE_ROLE}`, 
        'Content-Type': 'application/json' 
      }
    });

    if (!logsRes.ok) {
      const txt = await logsRes.text();
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to fetch logs', detail: txt }),
        { status: 502, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // 解析日志响应数据（兼容多种返回格式）
    let payload: unknown;
    try {
      payload = await logsRes.json();
    } catch {
      payload = await logsRes.text();
    }

    let entries: unknown[] = [];
    if (Array.isArray(payload)) entries = payload;
    else if (isRecord(payload) && Array.isArray(payload.logs)) entries = payload.logs;
    else if (isRecord(payload) && Array.isArray(payload.rows)) entries = payload.rows;
    else if (typeof payload === 'string') entries = payload.split('\n').filter(Boolean).map((l) => ({ line: l }));

    // 二次精细过滤日志数据
    const total_before = entries.length;
    const statusCodes = (typeof status_code === 'string') 
      ? status_code.split(',').map((value) => value.trim())
      : (Array.isArray(status_code)
          ? status_code.filter((value): value is string => typeof value === 'string')
          : null);

    const filtered = entries.filter((rawEntry) => {
      const e = isRecord(rawEntry) ? rawEntry : { value: rawEntry }
      const text = JSON.stringify(e).toLowerCase();
      const normalizedLevel = stringFilter(level).toLowerCase()
      if (normalizedLevel && !(String(e.level || '').toLowerCase() === normalizedLevel || text.includes(`\"level\":\"${normalizedLevel}\"`))) return false;
      if (statusCodes) {
        const sc = String(e.status_code || e.status || '');
        if (!statusCodes.includes(sc)) return false;
      }
      if (function_id) {
        const fid = String(e.function_id || e.function || '');
        if (!fid.includes(String(function_id))) return false;
      }
      if (query_text) {
        if (!text.includes(String(query_text).toLowerCase())) return false;
      }
      return true;
    }).slice(0, limit);

    // 构造返回元信息和最终响应
    const meta = { 
      service, 
      limit, 
      filters_applied: Object.keys(filters), 
      total_before_filter: total_before, 
      total_after_filter: filtered.length 
    };

    return new Response(
      JSON.stringify({ success: true, data: filtered, meta }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  } catch (err) {
    console.error('proxy-logs error', err);
    return new Response(
      JSON.stringify({ success: false, error: String(err) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});
