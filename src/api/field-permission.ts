import { useSupabase } from '@/hooks'

type SubjectType = Api.SystemManage.FieldPermissionSubjectType
type AccessLevel = Api.Tms.BasicData.FieldAccessLevel

const { supabase, responseHandle } = useSupabase()

export async function fetchFieldPermissionResources() {
  return await responseHandle<Api.SystemManage.FieldPermissionResource[]>(
    () => supabase.rpc('get_field_permission_resources'),
    {
      showErrorMessage: true,
      errorMessage: '字段权限目录加载失败，请稍后重试'
    }
  )
}

export async function fetchFieldPermissionConfiguration(params: {
  resourceKey: string
  subjectType: SubjectType
  subjectId: string
}) {
  return await responseHandle<Api.SystemManage.FieldPermissionConfiguration>(
    () =>
      supabase.rpc('get_field_permission_configuration', {
        p_resource_key: params.resourceKey,
        p_subject_type: params.subjectType,
        p_subject_id: params.subjectId
      }),
    {
      showErrorMessage: true,
      errorMessage: '字段权限配置加载失败，请稍后重试'
    }
  )
}

export async function saveFieldPermissions(params: {
  resourceKey: string
  subjectType: SubjectType
  subjectId: string
  permissions: Record<string, AccessLevel>
}) {
  return await responseHandle(
    () =>
      supabase.rpc('set_field_permissions', {
        p_resource_key: params.resourceKey,
        p_subject_type: params.subjectType,
        p_subject_id: params.subjectId,
        p_permissions: params.permissions
      }),
    {
      showMessage: true,
      message: '字段权限保存成功',
      errorMessage: '字段权限保存失败，请检查按钮权限后重试',
      breakReturn: true
    }
  )
}
