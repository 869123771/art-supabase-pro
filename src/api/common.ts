import { useSupabase } from '@/hooks'
import { calcFileHash, formatSize } from '@/utils'
import { useUserStore } from '@/store/modules/user'
import dayjs from 'dayjs'

const { supabase, responseHandle } = useSupabase()
export async function checkUnique(params: {
  table: string
  field: string
  value: string
  excludeId?: string
  extraWhere?: string | any
}) {
  const { getUserInfo } = useUserStore()
  const { table, field, value, excludeId, extraWhere } = params
  let query = supabase
    .from(table)
    .select('id', { count: 'exact', head: true })
    .eq(field, value)
    .eq('create_by', getUserInfo.email)

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
): Promise<any[]> {
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
  const results: any[] = []

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
        // 是否中断由你决定
      }
    }
  }

  await Promise.all(Array.from({ length: Math.min(concurrency, fileList.length) }, () => worker()))

  return results

  /* ---------------- 单文件原子逻辑 ---------------- */

  async function uploadSingle(file: File) {
    // 1️⃣ hash
    const hash = await calcFileHash(file)

    // 2️⃣ 查重
    const { data: existed } = await supabase
      .from('attachment')
      .select('*')
      .eq('hash', hash)
      .maybeSingle()

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

    const query = await supabase.from('attachment').insert(insertData).select().single()

    return await responseHandle(() => query as any, {
      ignoreCheck: true,
      showMessage: true
    })
  }
}
