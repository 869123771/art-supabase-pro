import { uniq } from 'lodash-es'
import { normalizeNullableText, normalizeStringList } from '@/utils/form/normalize'
import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()

export type UiDesignReferenceSurfaceKind =
  'workspace' | 'detail' | 'form' | 'dashboard' | 'configuration' | 'other'

export type UiDesignReferenceStyleSnapshot = Record<
  string,
  string | number | boolean | null | string[]
>

export interface UiDesignReferenceRecord {
  id: string
  routeName: string
  routePathPattern: string
  pageTitle: string
  surfaceKind: UiDesignReferenceSurfaceKind
  preferenceTags: string[]
  note: string | null
  styleSnapshot: UiDesignReferenceStyleSnapshot
  sourceRevision: string | null
  createTime: string
  updateTime: string
}

export interface SaveUiDesignReferencePayload {
  id?: string
  routeName: string
  routePathPattern: string
  pageTitle: string
  surfaceKind: UiDesignReferenceSurfaceKind
  preferenceTags?: readonly string[]
  note?: string | null
  styleSnapshot?: UiDesignReferenceStyleSnapshot
  sourceRevision?: string | null
}

const surfaceKinds = new Set<UiDesignReferenceSurfaceKind>([
  'workspace',
  'detail',
  'form',
  'dashboard',
  'configuration',
  'other'
])

const referenceSelect =
  'id,route_name,route_path_pattern,page_title,surface_kind,preference_tags,note,style_snapshot,source_revision,create_time,update_time'

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function normalizeStyleSnapshot(value: unknown): UiDesignReferenceStyleSnapshot {
  if (!isRecord(value)) return {}

  return Object.fromEntries(
    Object.entries(value).filter(([, item]) => {
      if (item === null || ['string', 'number', 'boolean'].includes(typeof item)) return true
      return Array.isArray(item) && item.every((entry) => typeof entry === 'string')
    })
  ) as UiDesignReferenceStyleSnapshot
}

function normalizeReference(value: unknown): UiDesignReferenceRecord | null {
  if (!isRecord(value)) return null
  if (
    typeof value.id !== 'string' ||
    typeof value.routeName !== 'string' ||
    typeof value.routePathPattern !== 'string' ||
    typeof value.pageTitle !== 'string' ||
    typeof value.surfaceKind !== 'string' ||
    !surfaceKinds.has(value.surfaceKind as UiDesignReferenceSurfaceKind) ||
    typeof value.createTime !== 'string' ||
    typeof value.updateTime !== 'string'
  ) {
    return null
  }

  return {
    id: value.id,
    routeName: value.routeName,
    routePathPattern: value.routePathPattern,
    pageTitle: value.pageTitle,
    surfaceKind: value.surfaceKind as UiDesignReferenceSurfaceKind,
    preferenceTags: normalizeStringList(value.preferenceTags),
    note: typeof value.note === 'string' ? value.note : null,
    styleSnapshot: normalizeStyleSnapshot(value.styleSnapshot),
    sourceRevision: typeof value.sourceRevision === 'string' ? value.sourceRevision : null,
    createTime: value.createTime,
    updateTime: value.updateTime
  }
}

function buildWritePayload(payload: SaveUiDesignReferencePayload) {
  return {
    route_name: payload.routeName.trim(),
    route_path_pattern: payload.routePathPattern.trim(),
    page_title: payload.pageTitle.trim(),
    surface_kind: payload.surfaceKind,
    preference_tags: uniq(normalizeStringList(payload.preferenceTags)).slice(0, 12),
    note: normalizeNullableText(payload.note),
    style_snapshot: normalizeStyleSnapshot(payload.styleSnapshot),
    source_revision: normalizeNullableText(payload.sourceRevision)
  }
}

export async function fetchUiDesignReference(
  routeName: string
): Promise<UiDesignReferenceRecord | null> {
  const { data } = await responseHandle<unknown>(
    () =>
      supabase
        .from('ai_ui_design_reference')
        .select(referenceSelect)
        .eq('route_name', routeName)
        .maybeSingle(),
    { breakReturn: true }
  )
  return normalizeReference(data)
}

export async function saveUiDesignReference(
  payload: SaveUiDesignReferencePayload
): Promise<UiDesignReferenceRecord> {
  const writePayload = buildWritePayload(payload)
  const query = payload.id
    ? supabase
        .from('ai_ui_design_reference')
        .update(writePayload)
        .eq('id', payload.id)
        .select(referenceSelect)
        .single()
    : supabase.from('ai_ui_design_reference').insert(writePayload).select(referenceSelect).single()

  const { data } = await responseHandle<unknown>(() => query, {
    breakReturn: true,
    showErrorMessage: true,
    requireAffected: Boolean(payload.id),
    noAffectedMessage: '设计参考已发生变化，请刷新页面后重试'
  })
  const reference = normalizeReference(data)
  if (!reference) throw new Error('设计参考保存后未返回有效结果')
  return reference
}

export async function removeUiDesignReference(id: string): Promise<void> {
  await responseHandle(
    () => supabase.from('ai_ui_design_reference').delete({ count: 'exact' }).eq('id', id),
    {
      breakReturn: true,
      showErrorMessage: true,
      requireAffected: true,
      noAffectedMessage: '设计参考已被取消，无需重复操作'
    }
  )
}
