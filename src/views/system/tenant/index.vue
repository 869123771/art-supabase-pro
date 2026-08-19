<template>
  <div class="tenant-page business-workspace-page art-full-height">
    <BusinessWorkspaceHeader
      class="tenant-page__overview"
      eyebrow="TENANT GOVERNANCE"
      title="租户管理"
      description="统一维护组织身份、访问状态与数据隔离边界，系统租户受到额外保护。"
      icon="ri:building-4-line"
      :tags="[
        { label: '数据隔离已启用', type: 'success', effect: 'light' },
        { label: '权限按角色授权', type: 'primary', effect: 'plain' }
      ]"
      :metrics="workspaceMetrics"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableQueryRef" />
      </template>
    </BusinessWorkspaceHeader>

    <ArtTableQuery
      ref="tableQueryRef"
      focusable
      v-model="searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      header-actions-placement="workspace"
      :table-props="tableProps"
      :on-success="handleTableSuccess"
    />

    <TenantDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext,
    ArtTableQueryProps,
    ArtTableQueryTableProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore from '@/components/core/forms/art-button-more/index.vue'
  import type { ButtonMoreItem } from '@/components/core/forms/art-button-more/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import { deactivateTenant, deactivateTenantBatch, fetchGetTenantList } from '@/api/system-manage'
  import TenantDialog from './modules/tenant-dialog.vue'
  import { useUserStore } from '@/store/modules/user'
  import { useAuth } from '@/hooks/core/useAuth'

  defineOptions({ name: 'Tenant' })

  const { confirmAction } = useArtFeedback()

  type Tenant = Api.SystemManage.TenantListItem
  type SearchParams = Api.SystemManage.TenantSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: Tenant) => Promise<void>
  }

  interface TenantOverviewRow {
    status?: unknown
    builtinType?: Api.SystemManage.TenantBuiltinType | null
  }
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const { hasAuth } = useAuth()

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const overview = reactive<{ total: number; rows: TenantOverviewRow[] }>({
    total: 0,
    rows: []
  })
  const systemTenantCount = computed(
    () => overview.rows.filter((row) => Boolean(row.builtinType)).length
  )
  const enabledTenantCount = computed(
    () => overview.rows.filter((row) => String(row.status) === '1').length
  )
  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '当前结果',
      value: overview.total,
      description: '随筛选条件实时更新',
      icon: 'ri:group-2-line'
    },
    {
      label: '本页启用',
      value: enabledTenantCount.value,
      description: '当前页可正常访问',
      icon: 'ri:checkbox-circle-line',
      tone: 'success'
    },
    {
      label: '受保护身份',
      value: systemTenantCount.value,
      description: '平台与注册租户不可停用',
      icon: 'ri:shield-keyhole-line',
      tone: 'warning'
    }
  ])

  const searchQuery = ref<SearchParams>({
    tenantCode: '',
    tenantName: '',
    status: undefined
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '租户编码',
      key: 'tenantCode',
      type: 'input',
      props: { placeholder: '请输入租户编码', clearable: true }
    },
    {
      label: '租户名称',
      key: 'tenantName',
      type: 'input',
      props: { placeholder: '请输入租户名称', clearable: true }
    },
    {
      label: '状态',
      key: 'status',
      type: 'select',
      props: {
        options: getDictMap.value.status ?? []
      }
    }
  ])

  const tableProps: ArtTableQueryTableProps = {
    rowKey: 'id',
    tableLayout: 'fixed',
    emptyText: '暂无符合条件的租户',
    emptyDescription: '可调整筛选条件；拥有新增权限的角色也可以创建租户。'
  }

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      permission: 'System:Tenant:Add',
      onClick: () => openDialog()
    },
    {
      type: 'delete',
      label: '批量停用',
      permission: 'System:Tenant:Delete',
      content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
        `确定停用选中的 ${selectedCount} 个租户吗？账号将不能继续使用，历史数据仍会保留。`,
      onClick: async ({ selectedRows }) => {
        const ids = selectedRows.map((row) => row.id).filter(Boolean)
        await deactivateTenantBatch(ids)
        await tableQueryRef.value?.refreshUpdate()
      }
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })
    return fetchGetTenantList({
      ...params,
      from,
      to
    })
  }

  const columnsFactory = (): ColumnOption<Tenant>[] => [
    {
      type: 'selection',
      width: 50,
      fixed: 'left',
      reserveSelection: true,
      selectable: (row: Tenant) => hasAuth('System:Tenant:Delete') && !isSystemTenant(row)
    },
    {
      type: 'globalIndex',
      label: '序号',
      width: 72
    },
    {
      prop: 'tenantIdentity',
      label: '租户身份',
      minWidth: 260,
      formatter: (row) => (
        <div class="tenant-identity-cell">
          <span
            class={['tenant-identity-cell__icon', { 'is-system': isSystemTenant(row) }]}
            aria-hidden="true"
          >
            {(row.tenantName || '租').slice(0, 1)}
          </span>
          <div class="tenant-identity-cell__copy">
            <div class="tenant-identity-cell__heading">
              <strong title={row.tenantName}>{row.tenantName}</strong>
              {isSystemTenant(row) ? (
                <span class="tenant-identity-cell__system">系统租户</span>
              ) : null}
            </div>
            <span class="tenant-identity-cell__code" title={row.tenantCode}>
              {row.tenantCode}
            </span>
          </div>
        </div>
      )
    },
    {
      prop: 'status',
      label: '状态',
      width: 100,
      dict: { code: 'status', display: 'auto' }
    },
    {
      prop: 'remark',
      label: '用途说明',
      minWidth: 260,
      showOverflowTooltip: true,
      formatter: (row) =>
        row.remark ? (
          <span class="tenant-remark-cell">{row.remark}</span>
        ) : (
          <span class="tenant-cell-placeholder">暂无说明</span>
        )
    },
    {
      prop: 'createTime',
      label: '创建信息',
      minWidth: 190,
      formatter: (row) => (
        <div class="tenant-created-cell">
          <span>{formatWithDayjs(row.createTime)}</span>
          <small>{row.createBy || '系统创建'}</small>
        </div>
      )
    },
    {
      prop: 'operation',
      label: '操作',
      width: 112,
      fixed: 'right',
      formatter: (row) => (
        <div class="tenant-row-actions">
          <ArtButtonTable
            type="edit"
            permission="System:Tenant:Edit"
            onClick={() => openDialog(row)}
          />
          {!isSystemTenant(row) ? (
            <ArtButtonMore
              list={getTenantMoreActions(row)}
              onClick={(item: ButtonMoreItem) => handleTenantAction(item, row)}
            />
          ) : null}
        </div>
      )
    }
  ]

  const openDialog = (row?: Tenant): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const isSystemTenant = (row: Pick<Tenant, 'builtinType'>): boolean => Boolean(row.builtinType)

  const getTenantMoreActions = (row: Tenant): ButtonMoreItem[] => {
    return isSystemTenant(row)
      ? []
      : [
          {
            key: 'delete',
            label: '停用租户',
            icon: 'ri:pause-circle-line',
            color: 'var(--el-color-danger)',
            auth: 'System:Tenant:Delete'
          }
        ]
  }

  const handleTenantAction = (item: ButtonMoreItem, row: Tenant): void => {
    switch (item.key) {
      case 'edit':
        openDialog(row)
        break
      case 'delete':
        void handleDelete(row)
        break
    }
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.rows = rows.map((row) => ({
      status: row.status,
      builtinType: row.builtinType
    }))
    overview.total = response.total ?? rows.length
  }

  const handleDelete = async (row: Tenant): Promise<void> => {
    if (!row.id) return

    try {
      await confirmAction(
        `停用「${row.tenantName}」后，该租户账号将无法继续使用；组织、角色及业务历史均会保留。`,
        '停用租户',
        {
          confirmButtonText: '确认停用',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deactivateTenant(row.id)
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消删除时无需额外提示。
    }
  }
</script>

<style scoped lang="scss">
  .tenant-page {
    gap: 12px;
    min-width: 0;

    &__overview {
      flex: 0 0 auto;
      min-width: 0;
      overflow: hidden;
    }

    &__hero,
    &__identity,
    &__hero-status,
    &__metrics article,
    &__brand,
    &__metric-icon {
      display: flex;
      align-items: center;
    }

    &__hero {
      gap: 20px;
      justify-content: space-between;
      padding: 20px 24px 18px;
      background: radial-gradient(
        circle at 92% 0%,
        var(--el-color-primary-light-9),
        transparent 32%
      );
    }

    &__identity {
      min-width: 0;

      > div:last-child {
        min-width: 0;
      }

      span {
        display: block;
        margin-bottom: 3px;
        font-size: 10px;
        font-weight: 700;
        color: var(--el-color-primary);
        letter-spacing: 0.14em;
      }

      h1 {
        margin: 0 0 3px;
        font-size: 22px;
        line-height: 1.35;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0;
        font-size: 13px;
        line-height: 1.6;
        color: var(--el-text-color-secondary);
        overflow-wrap: anywhere;
      }
    }

    &__brand {
      flex: 0 0 50px;
      justify-content: center;
      width: 50px;
      height: 50px;
      margin-right: 16px;
      color: white;
      background: linear-gradient(145deg, var(--el-color-primary), var(--el-color-primary-dark-2));
      border-radius: var(--custom-radius);

      :deep(svg) {
        width: 23px;
        height: 23px;
      }
    }

    &__hero-status {
      flex: 0 0 auto;
      gap: 8px;
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      border-top: 1px solid var(--el-border-color-lighter);

      article {
        gap: 12px;
        min-width: 0;
        padding: 14px 24px;

        &:not(:last-child) {
          border-right: 1px solid var(--el-border-color-lighter);
        }

        > div:last-child {
          display: grid;
          min-width: 0;
        }

        span,
        small {
          overflow: hidden;
          text-overflow: ellipsis;
          color: var(--el-text-color-secondary);
          white-space: nowrap;
        }

        span {
          font-size: 12px;
        }

        strong {
          margin: 1px 0;
          font-size: 20px;
          line-height: 1.25;
          color: var(--el-text-color-primary);
        }

        small {
          font-size: 11px;
        }
      }
    }

    &__metric-icon {
      flex: 0 0 38px;
      justify-content: center;
      width: 38px;
      height: 38px;
      border-radius: var(--el-border-radius-base);

      :deep(svg) {
        width: 18px;
        height: 18px;
      }

      &.is-primary {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }

      &.is-success {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }

      &.is-warning {
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
      }
    }

    :deep(.tenant-row-actions) {
      display: flex;
      gap: 4px;
      align-items: center;
    }

    :deep(.tenant-identity-cell) {
      display: flex;
      gap: 10px;
      align-items: center;
      min-width: 0;

      .tenant-identity-cell__icon {
        display: grid;
        flex: 0 0 36px;
        place-items: center;
        width: 36px;
        height: 36px;
        font-size: 14px;
        font-weight: 700;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border: 1px solid var(--el-color-primary-light-7);
        border-radius: var(--art-control-radius);

        &.is-system {
          color: var(--el-color-warning-dark-2);
          background: var(--el-color-warning-light-9);
          border-color: var(--el-color-warning-light-7);
        }
      }

      .tenant-identity-cell__copy,
      .tenant-identity-cell__heading {
        min-width: 0;
      }

      .tenant-identity-cell__heading {
        display: flex;
        gap: 6px;
        align-items: center;

        strong {
          overflow: hidden;
          text-overflow: ellipsis;
          font-weight: 600;
          color: var(--el-text-color-primary);
          white-space: nowrap;
        }
      }

      .tenant-identity-cell__code {
        display: block;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }

      .tenant-identity-cell__system {
        flex: none;
        padding: 1px 6px;
        font-size: 10px;
        line-height: 17px;
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
        border-radius: 999px;
      }
    }

    :deep(.tenant-remark-cell) {
      color: var(--el-text-color-regular);
    }

    :deep(.tenant-cell-placeholder),
    :deep(.tenant-readonly-cell) {
      font-size: 12px;
      color: var(--el-text-color-placeholder);
    }

    :deep(.tenant-created-cell) {
      display: grid;
      min-width: 0;
      line-height: 20px;

      span,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      span {
        color: var(--el-text-color-primary);
      }

      small {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    @media (width <= 900px) {
      &__hero {
        align-items: flex-start;
      }

      &__hero-status {
        flex-direction: column;
        align-items: flex-end;
      }

      &__metrics article {
        padding-inline: 16px;
      }
    }

    @media (width <= 640px) {
      &__hero {
        flex-direction: column;
        padding: 18px;
      }

      &__hero-status {
        flex-direction: row;
        align-items: center;
        margin-left: 66px;
      }

      &__metrics {
        grid-template-columns: 1fr;

        article:not(:last-child) {
          border-right: 0;
          border-bottom: 1px solid var(--el-border-color-lighter);
        }
      }
    }
  }
</style>
