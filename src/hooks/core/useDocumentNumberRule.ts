import { fetchDocumentNumberRulesByKeys } from '@/api/document-number'
import { useUserStore } from '@/store/modules/user'

export function useDocumentNumberRule(
  ruleKey: string,
  tenantId?: MaybeRefOrGetter<string | undefined>
) {
  const userStore = useUserStore()
  const rule = shallowRef<Api.SystemManage.DocumentNumberRuleItem>()
  const loading = ref(false)

  const loadRule = async (): Promise<void> => {
    loading.value = true
    try {
      const targetTenantId = toValue(tenantId) || userStore.getUserInfo.tenantId
      const { data } = await fetchDocumentNumberRulesByKeys([ruleKey], targetTenantId)
      rule.value = data?.[0]
    } finally {
      loading.value = false
    }
  }

  const automatic = computed(() => rule.value?.autoEnabled === true)
  const description = computed(() => {
    if (!rule.value) return '编号规则加载中'
    if (!rule.value.autoEnabled) return '当前规则为手工填写，保存时会校验编号唯一性。'
    return `保存时自动生成，示例：${rule.value.preview || rule.value.template}`
  })

  const inputProps = (isEdit: boolean, placeholder: string, lockOnEdit = false) => ({
    disabled: loading.value || (isEdit && lockOnEdit) || (!isEdit && automatic.value),
    placeholder: !isEdit && automatic.value ? rule.value?.preview || '保存后自动生成' : placeholder
  })

  const manualRequired = (isEdit: boolean): boolean =>
    !isEdit && Boolean(rule.value && !rule.value.autoEnabled && rule.value.manualRequired)

  return { rule, loading, automatic, description, inputProps, manualRequired, loadRule }
}
