<template>
  <div class="field-permission-page business-workspace-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="FIELD ACCESS GOVERNANCE"
      title="字段权限"
      description="按角色批量授权、按人员设置例外，统一控制列表、详情、导出与打印中的敏感字段。"
      icon="ri:shield-keyhole-line"
      :tags="[
        { label: '租户内隔离', type: 'primary' },
        { label: subjectType === 'role' ? '角色授权' : '人员例外', type: 'info' }
      ]"
      :metrics="overviewMetrics"
    >
      <template #actions>
        <ElTooltip content="刷新字段权限配置" placement="bottom">
          <ArtIconButton
            icon="ri:refresh-line"
            circle
            label="刷新字段权限配置"
            :loading="page.loading || page.configurationLoading"
            @click="retryLoad"
          />
        </ElTooltip>
      </template>
    </BusinessWorkspaceHeader>

    <section class="field-permission-page__scope art-card-xs" aria-label="授权范围">
      <div class="field-permission-page__scope-heading">
        <div>
          <ArtSectionTitle :show-line="false">选择授权范围</ArtSectionTitle>
          <p>人员配置覆盖其全部角色的合并结果；清除人员例外后恢复角色继承。</p>
        </div>
        <div class="field-permission-page__scope-mode">
          <span>授权对象</span>
          <ElSegmented
            v-model="subjectType"
            :options="subjectTypeOptions"
            :disabled="page.loading || page.saving"
            @change="handleSubjectTypeChange"
          />
        </div>
      </div>

      <div class="field-permission-page__selectors">
        <label>
          <span>业务表单</span>
          <ElSelect
            v-model="selectedResourceKey"
            filterable
            :loading="page.loading"
            :disabled="page.saving"
            placeholder="请选择业务表单"
            @change="loadConfiguration"
          >
            <ElOption
              v-for="resource in resources"
              :key="resource.id"
              :label="`${resource.resourceLabel}（${resource.fieldCount} 个敏感字段）`"
              :value="resource.resourceKey"
            />
          </ElSelect>
        </label>

        <label>
          <span>{{ subjectType === 'role' ? '授权角色' : '授权人员' }}</span>
          <ElSelect
            v-model="selectedSubjectId"
            filterable
            :loading="page.loading"
            :disabled="page.saving"
            :placeholder="subjectType === 'role' ? '请选择角色' : '请选择人员'"
            @change="loadConfiguration"
          >
            <ElOption
              v-for="option in subjectOptions"
              :key="option.value"
              :label="option.label"
              :value="option.value"
            />
          </ElSelect>
        </label>
      </div>

      <div class="field-permission-page__scope-policy">
        <span class="field-permission-page__policy-icon" aria-hidden="true">
          <ArtSvgIcon icon="ri:user-star-line" />
        </span>
        <div>
          <strong>创建人豁免优先于人员例外和角色授权</strong>
          <p>
            标记为“创建人可编辑”的字段，仅在本人创建的记录中自动获得编辑权限；查看他人记录时仍按授权矩阵计算。
          </p>
        </div>
        <span class="field-permission-page__policy-level">记录级规则</span>
      </div>
    </section>

    <ArtPageShell
      class="field-permission-page__matrix-shell"
      :loading="page.loading || page.configurationLoading"
      loading-mode="skeleton"
      :error="page.error"
      :empty="!configuration || configuration.fields.length === 0"
      empty-text="暂无可配置的敏感字段"
      @retry="retryLoad"
    >
      <section v-if="configuration" class="field-permission-page__matrix art-card-xs">
        <header class="field-permission-page__matrix-header">
          <div>
            <ArtSectionTitle :show-line="false">字段授权矩阵</ArtSectionTitle>
            <div class="field-permission-page__matrix-context">
              <strong>{{ configuration.resourceLabel }}</strong>
              <span aria-hidden="true">/</span>
              <b>{{ currentSubjectLabel }}</b>
            </div>
          </div>
          <div class="field-permission-page__matrix-summary">
            <span
              class="field-permission-page__sync-state"
              :class="{ 'is-dirty': isDirty }"
              role="status"
            >
              <ArtSvgIcon :icon="isDirty ? 'ri:draft-line' : 'ri:shield-check-line'" />
              {{ isDirty ? `${changedFieldCount} 项待保存` : '配置已同步' }}
            </span>
            <p>
              {{
                subjectType === 'role'
                  ? '角色成员继承本配置；用户拥有多个角色时取权限最大值。'
                  : '“继承角色”不保存人员记录；其余选项覆盖角色合并结果。'
              }}
            </p>
          </div>
        </header>

        <div class="field-permission-page__legend" aria-label="权限等级说明">
          <span v-for="option in accessOptions" :key="option.value">
            <i :class="`is-${option.value}`" aria-hidden="true" />
            <b>{{ option.label }}</b>
            <small>{{ accessMeta[option.value].description }}</small>
          </span>
        </div>

        <div class="field-permission-page__field-list">
          <article
            v-for="field in configuration.fields"
            :key="field.id"
            class="field-permission-page__field-row"
          >
            <div class="field-permission-page__field-identity">
              <span class="field-permission-page__field-icon" aria-hidden="true">
                <ArtSvgIcon :icon="field.maskStrategy ? 'ri:eye-off-line' : 'ri:key-2-line'" />
              </span>
              <div>
                <strong>{{ field.fieldLabel }}</strong>
                <code translate="no">{{ field.fieldKey }}</code>
              </div>
            </div>

            <div class="field-permission-page__field-meta">
              <span
                v-if="field.ownerOverrideEnabled"
                class="field-permission-page__field-flag is-owner"
              >
                <ArtSvgIcon icon="ri:user-star-line" />
                创建人可编辑
              </span>
              <span v-if="field.maskStrategy" class="field-permission-page__field-flag is-mask">
                <ArtSvgIcon icon="ri:eye-off-line" />
                支持脱敏
              </span>
              <span class="field-permission-page__field-default">
                默认 {{ accessMeta[field.defaultAccess].label }}
              </span>
            </div>

            <div class="field-permission-page__field-control">
              <ElSelect
                v-model="permissionDraft[field.fieldKey]"
                :disabled="page.saving || isReadOnly"
                :aria-label="`${field.fieldLabel}字段权限`"
              >
                <ElOption
                  v-if="subjectType === 'user'"
                  :label="`继承角色（${accessMeta[field.inheritedAccess].label}）`"
                  value="inherit"
                />
                <ElOption
                  v-for="option in accessOptions"
                  :key="option.value"
                  :label="option.label"
                  :value="option.value"
                />
              </ElSelect>
              <small>
                当前生效：
                <b :class="`is-${effectiveAccess(field)}`">
                  {{ accessMeta[effectiveAccess(field)].label }}
                </b>
              </small>
            </div>
          </article>
        </div>
      </section>
    </ArtPageShell>

    <ArtStickyActionBar
      v-if="configuration"
      class="field-permission-page__actions"
      :class="{ 'is-dirty': isDirty, 'is-readonly': isReadOnly }"
    >
      <template #summary>
        <div class="field-permission-page__action-summary">
          <span aria-hidden="true">
            <ArtSvgIcon :icon="actionState.icon" />
          </span>
          <div>
            <strong>{{ actionState.title }}</strong>
            <p>{{ actionState.description }}</p>
          </div>
        </div>
      </template>

      <template v-if="!isReadOnly">
        <ElButton :disabled="!isDirty || page.saving" @click="resetDraft">
          撤销未保存修改
        </ElButton>
        <ElButton
          v-auth="'System:FieldPermission:Manage'"
          type="primary"
          :loading="page.saving"
          :disabled="!isDirty"
          @click="saveConfiguration"
        >
          保存 {{ changedFieldCount }} 项授权
        </ElButton>
      </template>
      <span v-else class="field-permission-page__readonly-state">
        <ArtSvgIcon icon="ri:lock-2-line" />
        需要“维护字段权限”按钮权限
      </span>
    </ArtStickyActionBar>
  </div>
</template>

<script setup lang="ts">
  import { ElButton, ElOption, ElSegmented, ElSelect, ElTooltip } from 'element-plus'
  import { cloneDeep, isEqual } from 'lodash-es'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtStickyActionBar from '@/components/core/layouts/art-sticky-action-bar/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import {
    fetchFieldPermissionConfiguration,
    fetchFieldPermissionResources,
    saveFieldPermissions
  } from '@/api/field-permission'
  import { fetchGetRoleList, fetchGetUserList } from '@/api/system-manage'
  import { useAuth } from '@/hooks/core/useAuth'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'FieldPermission' })

  type SubjectType = Api.SystemManage.FieldPermissionSubjectType
  type Configuration = Api.SystemManage.FieldPermissionConfiguration
  type PermissionField = Api.SystemManage.FieldPermissionField
  type AccessLevel = Api.Tms.BasicData.FieldAccessLevel
  type PermissionSelection = AccessLevel | 'inherit'

  interface SelectOption {
    label: string
    value: string
  }

  interface PageGroup {
    loading: boolean
    configurationLoading: boolean
    saving: boolean
    error: Error | null
  }

  interface AccessMeta {
    label: string
    description: string
  }

  const userStore = useUserStore()
  const { getUserInfo } = storeToRefs(userStore)
  const { hasAuth } = useAuth()

  const page = reactive<PageGroup>({
    loading: false,
    configurationLoading: false,
    saving: false,
    error: null
  })
  const resources = shallowRef<Api.SystemManage.FieldPermissionResource[]>([])
  const roleOptions = shallowRef<SelectOption[]>([])
  const userOptions = shallowRef<SelectOption[]>([])
  const subjectType = ref<SubjectType>('role')
  const selectedResourceKey = ref('')
  const selectedSubjectId = ref('')
  const configuration = shallowRef<Configuration | null>(null)
  const permissionDraft = ref<Record<string, PermissionSelection>>({})
  const savedDraft = shallowRef<Record<string, PermissionSelection>>({})

  const subjectTypeOptions = [
    { label: '按角色授权', value: 'role' },
    { label: '按人员例外', value: 'user' }
  ]

  const accessOptions: Array<{ label: string; value: AccessLevel }> = [
    { label: '完全不可见', value: 'hidden' },
    { label: '脱敏查看', value: 'masked' },
    { label: '仅查看', value: 'read' },
    { label: '可编辑', value: 'edit' }
  ]

  const accessMeta: Record<AccessLevel, AccessMeta> = {
    hidden: { label: '完全不可见', description: '列表、详情及导出均隐藏' },
    masked: { label: '脱敏查看', description: '仅展示处理后的安全值' },
    read: { label: '仅查看', description: '显示原值但禁止修改' },
    edit: { label: '可编辑', description: '允许查看并维护原值' }
  }

  const subjectOptions = computed(() =>
    subjectType.value === 'role' ? roleOptions.value : userOptions.value
  )
  const currentSubjectLabel = computed(
    () =>
      subjectOptions.value.find((option) => option.value === selectedSubjectId.value)?.label || '--'
  )
  const isReadOnly = computed(() => !hasAuth('System:FieldPermission:Manage'))
  const changedFieldCount = computed(
    () =>
      configuration.value?.fields.filter(
        (field) => !isEqual(permissionDraft.value[field.fieldKey], savedDraft.value[field.fieldKey])
      ).length ?? 0
  )
  const isDirty = computed(() => Boolean(configuration.value) && changedFieldCount.value > 0)
  const overviewMetrics = computed<BusinessWorkspaceMetric[]>(() => {
    const fields = configuration.value?.fields ?? []
    const explicitCount = fields.filter(
      (field) => permissionDraft.value[field.fieldKey] !== 'inherit'
    ).length
    return [
      {
        label: '授权表单',
        value: resources.value.length,
        description: '已接入统一字段权限解析器',
        icon: 'ri:file-list-3-line',
        tone: 'primary'
      },
      {
        label: '敏感字段',
        value: fields.length,
        description: configuration.value?.resourceLabel || '请选择业务表单',
        icon: 'ri:lock-2-line',
        tone: 'warning'
      },
      {
        label: '显式配置',
        value: explicitCount,
        description: subjectType.value === 'user' ? '人员覆盖项' : '角色授权项',
        icon: 'ri:user-settings-line',
        tone: 'info'
      }
    ]
  })
  const actionState = computed(() => {
    if (isReadOnly.value) {
      return {
        icon: 'ri:eye-line',
        title: '当前为安全只读视图',
        description: '可查看角色与人员的生效权限；修改需分配“维护字段权限”按钮权限。'
      }
    }
    if (isDirty.value) {
      return {
        icon: 'ri:draft-line',
        title: `${changedFieldCount.value} 项字段授权尚未保存`,
        description: '保存后立即参与列表、详情、导出和打印的统一字段权限计算。'
      }
    }
    return {
      icon: 'ri:shield-check-line',
      title: '字段授权配置已同步',
      description: '当前显示的权限等级已生效；切换表单或授权对象可继续核对。'
    }
  })

  const normalizeDraft = (data: Configuration): Record<string, PermissionSelection> =>
    Object.fromEntries(
      data.fields.map((field) => [
        field.fieldKey,
        data.subjectType === 'user'
          ? (field.explicitAccess ?? 'inherit')
          : (field.explicitAccess ?? field.inheritedAccess)
      ])
    )

  const effectiveAccess = (field: PermissionField): AccessLevel => {
    const selection = permissionDraft.value[field.fieldKey]
    return !selection || selection === 'inherit' ? field.inheritedAccess : selection
  }

  const loadConfiguration = async (): Promise<void> => {
    if (!selectedResourceKey.value || !selectedSubjectId.value) {
      configuration.value = null
      permissionDraft.value = {}
      savedDraft.value = {}
      return
    }

    page.configurationLoading = true
    page.error = null
    try {
      const { data, error } = await fetchFieldPermissionConfiguration({
        resourceKey: selectedResourceKey.value,
        subjectType: subjectType.value,
        subjectId: selectedSubjectId.value
      })
      if (error || !data) throw error instanceof Error ? error : new Error('字段权限配置加载失败')
      configuration.value = data
      permissionDraft.value = normalizeDraft(data)
      savedDraft.value = cloneDeep(permissionDraft.value)
    } catch (error) {
      configuration.value = null
      page.error = new Error('字段权限配置加载失败，请刷新后重试。', { cause: error })
    } finally {
      page.configurationLoading = false
    }
  }

  const loadCatalog = async (): Promise<void> => {
    page.loading = true
    page.error = null
    try {
      const tenantId = String(getUserInfo.value.tenantId || '')
      if (!tenantId) throw new Error('当前账号未绑定租户，无法配置租户字段权限')

      const [resourceResult, roleResult, userResult] = await Promise.all([
        fetchFieldPermissionResources(),
        fetchGetRoleList({ tenantId, enabled: true, from: 0, to: 999 }),
        fetchGetUserList({ tenantId, status: '1', from: 0, to: 999 })
      ])

      const catalogError = resourceResult.error ?? roleResult.error ?? userResult.error
      if (catalogError) throw catalogError
      const roles = Array.isArray(roleResult.data)
        ? (roleResult.data as Api.SystemManage.RoleListItem[])
        : []
      const users = Array.isArray(userResult.data)
        ? (userResult.data as Api.SystemManage.UserListItem[])
        : []
      resources.value = resourceResult.data ?? []
      roleOptions.value = roles
        .filter((role) => role.id)
        .map((role) => ({
          label: `${role.roleName}（${role.roleCode}）`,
          value: String(role.id)
        }))
      userOptions.value = users
        .filter((user) => user.id)
        .map((user) => ({
          label: `${user.userName || user.nickName || user.userEmail}（${user.userEmail}）`,
          value: String(user.id)
        }))

      selectedResourceKey.value ||= resources.value[0]?.resourceKey ?? ''
      selectedSubjectId.value ||= roleOptions.value[0]?.value ?? ''
      await loadConfiguration()
    } catch (error) {
      page.error = new Error('字段权限目录加载失败，请检查租户与菜单权限后重试。', {
        cause: error
      })
    } finally {
      page.loading = false
    }
  }

  const handleSubjectTypeChange = async (): Promise<void> => {
    selectedSubjectId.value = subjectOptions.value[0]?.value ?? ''
    await loadConfiguration()
  }

  const resetDraft = (): void => {
    permissionDraft.value = cloneDeep(savedDraft.value)
  }

  const saveConfiguration = async (): Promise<void> => {
    if (!configuration.value || !selectedSubjectId.value) return
    page.saving = true
    try {
      const permissions = Object.fromEntries(
        Object.entries(permissionDraft.value).filter(
          (entry): entry is [string, AccessLevel] => entry[1] !== 'inherit'
        )
      )
      await saveFieldPermissions({
        resourceKey: configuration.value.resourceKey,
        subjectType: subjectType.value,
        subjectId: selectedSubjectId.value,
        permissions
      })
      await loadConfiguration()
    } finally {
      page.saving = false
    }
  }

  const retryLoad = async (): Promise<void> => {
    if (resources.value.length) await loadConfiguration()
    else await loadCatalog()
  }

  onMounted(() => void loadCatalog())
</script>

<style scoped lang="scss">
  .field-permission-page {
    gap: 12px;
    min-width: 0;
    overflow: visible;

    &__scope {
      flex: none;
      padding: 16px;
    }

    &__scope-heading,
    &__matrix-header {
      display: flex;
      gap: 20px;
      align-items: flex-start;
      justify-content: space-between;

      p {
        margin: 5px 0 0;
        font-size: 12px;
        line-height: 1.55;
        color: var(--art-text-gray-500);
      }
    }

    &__scope-heading > div:first-child,
    &__matrix-header > div:first-child {
      min-width: 0;
    }

    &__scope-heading :deep(.art-section-title),
    &__matrix-header :deep(.art-section-title) {
      margin: 0;
    }

    &__scope-mode {
      display: flex;
      flex: none;
      gap: 10px;
      align-items: center;

      > span {
        font-size: 12px;
        font-weight: 600;
        color: var(--art-text-gray-500);
        white-space: nowrap;
      }
    }

    &__selectors {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 14px;
      margin-top: 12px;

      label {
        display: grid;
        gap: 7px;
        min-width: 0;

        > span {
          font-size: 12px;
          font-weight: 600;
          color: var(--art-text-gray-700);
        }
      }
    }

    &__scope-policy {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr) auto;
      gap: 10px;
      align-items: center;
      padding: 12px 16px;
      margin: 16px -16px -16px;
      background: color-mix(in srgb, var(--theme-color) 4%, var(--art-gray-100));
      border-top: 1px solid
        color-mix(in srgb, var(--theme-color) 14%, var(--el-border-color-lighter));

      > div {
        min-width: 0;
      }

      strong {
        display: block;
        color: var(--art-text-gray-800);
      }

      p {
        margin: 2px 0 0;
        font-size: 12px;
        line-height: 1.5;
        color: var(--art-text-gray-600);
      }
    }

    &__policy-icon {
      display: grid;
      flex: 0 0 34px;
      place-items: center;
      width: 34px;
      height: 34px;
      color: var(--theme-color);
      background: color-mix(in srgb, var(--theme-color) 10%, var(--default-box-color));
      border-radius: var(--art-control-radius);
    }

    &__policy-level,
    &__sync-state,
    &__readonly-state {
      display: inline-flex;
      gap: 5px;
      align-items: center;
      min-height: 26px;
      padding: 3px 9px;
      font-size: 12px;
      font-weight: 600;
      white-space: nowrap;
      border-radius: 999px;
    }

    &__policy-level {
      color: var(--art-text-gray-600);
      background: var(--default-box-color);
      box-shadow: inset 0 0 0 1px var(--el-border-color-lighter);
    }

    &__matrix-shell {
      flex: none;
      min-height: 0;
    }

    &__matrix {
      min-height: 0;
      padding: 16px;
    }

    &__matrix-header {
      padding-bottom: 12px;
      border-bottom: 1px solid var(--el-border-color-lighter);
    }

    &__matrix-context {
      display: flex;
      flex-wrap: wrap;
      gap: 7px;
      align-items: center;
      margin-top: 3px;

      strong {
        font-size: 17px;
        color: var(--art-text-gray-900);
      }

      span {
        color: var(--el-border-color-darker);
      }

      b {
        font-size: 13px;
        font-weight: 600;
        color: var(--el-color-primary);
      }
    }

    &__matrix-summary {
      display: grid;
      justify-items: end;
      max-width: 620px;

      p {
        text-align: right;
      }
    }

    &__sync-state {
      color: var(--el-color-success-dark-2);
      background: var(--el-color-success-light-9);
      box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--el-color-success) 28%, transparent);

      &.is-dirty {
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
        box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--el-color-warning) 30%, transparent);
      }
    }

    &__legend {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 8px;
      margin-top: 12px;

      > span {
        display: grid;
        grid-template-columns: auto minmax(0, 1fr);
        gap: 2px 7px;
        align-items: center;
        min-width: 0;
        padding: 9px 10px;
        background: color-mix(in srgb, var(--el-fill-color-light) 76%, transparent);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--art-control-radius);
      }

      i {
        grid-row: 1 / 3;
        width: 8px;
        height: 8px;
        border-radius: 50%;

        &.is-hidden {
          background: var(--el-color-danger);
        }

        &.is-masked {
          background: var(--el-color-warning);
        }

        &.is-read {
          background: var(--el-color-info);
        }

        &.is-edit {
          background: var(--el-color-success);
        }
      }

      b {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        font-weight: 600;
        color: var(--art-text-gray-800);
        white-space: nowrap;
      }

      small {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 11px;
        color: var(--art-text-gray-500);
        white-space: nowrap;
      }
    }

    &__field-list {
      display: grid;
      gap: 8px;
      margin-top: 12px;
    }

    &__field-row {
      display: grid;
      grid-template-columns: minmax(220px, 1.15fr) minmax(230px, 1fr) minmax(240px, 0.9fr);
      gap: 14px;
      align-items: center;
      min-width: 0;
      padding: 11px 13px;
      background: var(--el-fill-color-extra-light);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--art-surface-radius);
      transition:
        background-color 0.18s ease,
        border-color 0.18s ease;

      &:hover {
        background: var(--el-bg-color);
        border-color: var(--el-border-color);
      }
    }

    &__field-identity {
      display: flex;
      gap: 11px;
      align-items: center;
      min-width: 0;

      > div {
        min-width: 0;
      }

      strong,
      code {
        display: block;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      code {
        margin-top: 3px;
        font-size: 11px;
        color: var(--art-text-gray-500);
      }
    }

    &__field-icon {
      display: grid;
      flex: 0 0 34px;
      place-items: center;
      width: 34px;
      height: 34px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--art-control-radius);
    }

    &__field-meta {
      display: flex;
      flex-wrap: wrap;
      gap: 6px 12px;
      align-items: center;
    }

    &__field-flag {
      display: inline-flex;
      gap: 4px;
      align-items: center;
      font-size: 12px;
      font-weight: 600;

      &.is-owner {
        color: var(--el-color-success-dark-2);
      }

      &.is-mask {
        color: var(--el-color-warning-dark-2);
      }
    }

    &__field-default {
      font-size: 12px;
      color: var(--art-text-gray-500);
    }

    &__field-control {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 10px;
      align-items: center;

      small {
        color: var(--art-text-gray-500);
        white-space: nowrap;
      }

      b {
        font-weight: 600;

        &.is-hidden {
          color: var(--el-color-danger);
        }

        &.is-masked {
          color: var(--el-color-warning);
        }

        &.is-read {
          color: var(--el-color-info);
        }

        &.is-edit {
          color: var(--el-color-success);
        }
      }
    }

    &__actions {
      flex: none;
    }

    &__action-summary {
      display: flex;
      gap: 10px;
      align-items: center;
      min-width: 0;

      > span {
        display: grid;
        flex: 0 0 34px;
        place-items: center;
        width: 34px;
        height: 34px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: var(--art-control-radius);
      }

      > div {
        min-width: 0;
      }

      strong {
        display: block;
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--art-text-gray-900);
        white-space: nowrap;
      }

      p {
        margin: 2px 0 0;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        color: var(--art-text-gray-500);
        white-space: nowrap;
      }
    }

    &__readonly-state {
      color: var(--art-text-gray-600);
      background: var(--art-gray-100);
      box-shadow: inset 0 0 0 1px var(--el-border-color-lighter);
    }

    @media (width <= 1050px) {
      &__legend {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__field-row {
        grid-template-columns: minmax(210px, 1fr) minmax(250px, 1fr);
      }

      &__field-meta {
        grid-row: 2;
        grid-column: 1 / -1;
      }
    }

    @media (width <= 720px) {
      &__scope-heading,
      &__matrix-header {
        flex-direction: column;

        p {
          text-align: left;
        }
      }

      &__scope-mode {
        justify-content: space-between;
        width: 100%;
      }

      &__scope-policy {
        grid-template-columns: auto minmax(0, 1fr);
      }

      &__policy-level {
        grid-column: 2;
        justify-self: start;
      }

      &__matrix-summary {
        justify-items: start;
        max-width: none;
      }

      &__selectors,
      &__field-row {
        grid-template-columns: 1fr;
      }

      &__legend {
        grid-template-columns: 1fr;
      }

      &__field-meta {
        grid-row: auto;
        grid-column: auto;
      }

      &__field-control {
        grid-template-columns: 1fr;
      }

      &__action-summary p {
        white-space: normal;
      }
    }
  }
</style>
