import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()
type ExtraWhere = Record<string, string | number | boolean | null | undefined>

export async function checkUniqueField(params: {
  table: string
  field: string
  value: string
  excludeId?: string
  extraWhere?: ExtraWhere
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

  return await responseHandle(() => query, {})
}
