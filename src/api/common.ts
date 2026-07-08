import { useSupabase } from '@/hooks'
import { calcFileHash, formatSize } from '@/utils'
import { useUserStore } from '@/store/modules/user'
import dayjs from 'dayjs'
import http from '@/utils/http'
import TreeUtils, { type TreeNode } from '@/utils/tree'

const { supabase, responseHandle } = useSupabase()
const regionTreeUtils = new TreeUtils({ childrenKey: 'children' })
const REGION_SOURCE_URLS = [
  '/data/pca-code.json',
  'https://fastly.jsdelivr.net/gh/modood/Administrative-divisions-of-China@master/dist/pca-code.json',
  'https://raw.githubusercontent.com/modood/Administrative-divisions-of-China/master/dist/pca-code.json'
]
let regionOptionsCache: RegionOption[] | null = null

export interface RegionOption extends TreeNode {
  name: string
  code?: string
  children?: RegionOption[]
}

export async function fetchRegionOptions(): Promise<RegionOption[]> {
  if (regionOptionsCache) return regionOptionsCache

  let lastError: unknown
  for (const url of REGION_SOURCE_URLS) {
    try {
      const response = await http.get<unknown>({
        url,
        skipAuth: true,
        skipResponseWrapper: true,
        showErrorMessage: false
      })
      regionOptionsCache = regionTreeUtils.normalizeTreeData<RegionOption>(response)
      return regionOptionsCache
    } catch (error) {
      lastError = error
    }
  }

  throw lastError instanceof Error ? lastError : new Error('行政区划数据加载失败')
}

export async function checkUnique(params: {
  table: string
  field: string
  value: string
  excludeId?: string
  extraWhere?: string | any
}) {
  const { table, field, value, excludeId, extraWhere } = params
  let query = supabase.from(table).select('id', { count: 'exact', head: true }).eq(field, value)

  //编辑排除自己id
  if (excludeId) {
    query = query.neq('id', excludeId)
  }

  //额外的where条件
  if (extraWhere) {
    Object.entries(extraWhere).forEach(([key, val]) => {
      if (val !== undefined && val !== null) {
        query = query.eq(key, val)
      }
    })
  }

  return await responseHandle(() => query as any, { ignoreCheck: true })
}

export async function uploadAttachment(
  files: File | File[],
  options?: {
    bucket?: string
    createBy?: string
    remark?: string
    concurrency?: number
  }
): Promise<Api.DataCenter.Resources.ResourceListItem[]> {
  const {
    getUserInfo: { userName, nickName }
  } = useUserStore()
  const {
    bucket = 'attachments',
    createBy = userName || nickName,
    remark = '',
    concurrency = 3
  } = options || {}

  // 统一成数组
  const fileList = Array.isArray(files) ? files : [files]
  const queue = [...fileList]
  const results: Api.DataCenter.Resources.ResourceListItem[] = []
  const errors: unknown[] = []

  // worker（并发控制）
  async function worker() {
    while (queue.length) {
      const file = queue.shift()
      if (!file) return

      try {
        const res = await uploadSingle(file)
        results.push(res)
      } catch (e) {
        console.error('[uploadAttachment]', file.name, e)
        errors.push(e)
      }
    }
  }

  await Promise.all(Array.from({ length: Math.min(concurrency, fileList.length) }, () => worker()))

  if (errors.length > 0) {
    throw errors[0]
  }

  return results

  /* ---------------- 单文件原子逻辑 ---------------- */

  async function uploadSingle(file: File) {
    // 1️⃣ hash
    const hash = await calcFileHash(file)

    // 2️⃣ 查重
    const { data: existed } = await responseHandle<Api.DataCenter.Resources.ResourceListItem>(
      () => supabase.from('sys_attachment').select('*').eq('hash', hash).maybeSingle() as any,
      {
        ignoreCheck: true
      }
    )

    if (existed) return existed

    // 3️⃣ 路径
    const suffix = file.name.split('.').pop() || ''
    const objectName = `${hash}.${suffix}`
    const storagePath = dayjs().format('YYYY/MM/DD')
    const fullPath = `${storagePath}/${objectName}`

    // 4️⃣ 上传
    await responseHandle(
      () =>
        supabase.storage.from(bucket).upload(fullPath, file, {
          upsert: false,
          contentType: file.type
        }),
      {
        breakReturn: true,
        showMessage: false
      }
    )

    // 5️⃣ url
    const { data } = await responseHandle(
      () => supabase.storage.from(bucket).getPublicUrl(fullPath) as any,
      {
        ignoreCheck: true
      }
    )

    // 6️⃣ 写库
    const insertData = {
      tenant_id: null,
      storage_mode: 'supabase',
      origin_name: file.name,
      object_name: objectName,
      hash,
      mime_type: file.type,
      storage_path: storagePath,
      suffix,
      size_byte: file.size,
      size_info: formatSize(file.size),
      url: data.publicUrl,
      create_by: createBy,
      update_by: createBy,
      remark
    }

    const query = await supabase.from('sys_attachment').insert(insertData).select().single()

    const { data: inserted } = await responseHandle<Api.DataCenter.Resources.ResourceListItem>(
      () => query as any,
      {
        ignoreCheck: true,
        showMessage: true,
        breakReturn: true
      }
    )

    if (!inserted) {
      throw new Error('附件上传失败')
    }

    return inserted
  }
}
