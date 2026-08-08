<template>
  <div class="tenant-page art-full-height">
    <section class="tenant-page__overview art-card-xs">
      <header class="tenant-page__hero">
        <div class="tenant-page__identity">
          <div class="tenant-page__brand" aria-hidden="true">
            <ArtSvgIcon icon="ri:building-4-line" />
          </div>
          <div>
            <span>TENANT GOVERNANCE</span>
            <h1>租户管理</h1>
            <p>统一维护组织身份、访问状态与数据隔离边界，系统租户受到额外保护。</p>
          </div>
        </div>
        <div class="tenant-page__hero-status">
          <ElTag type="success" effect="light" round>数据隔离已启用</ElTag>
          <ElTag :type="canManageTenant ? 'primary' : 'info'" effect="plain" round>
            {{ canManageTenant ? '可维护' : '只读模式' }}
          </ElTag>
        </div>
      </header>

      <div class="tenant-page__metrics" aria-label="租户治理概览">
        <article>
          <div class="tenant-page__metric-icon is-primary">
            <ArtSvgIcon icon="ri:group-2-line" />
          </div>
          <div>
            <span>当前结果</span>
            <strong>{{ overview.total }}</strong>
            <small>随筛选条件实时更新</small>
          </div>
        </article>
        <article>
          <div class="tenant-page__metric-icon is-success">
            <ArtSvgIcon icon="ri:checkbox-circle-line" />
          </div>
          <div>
            <span>本页启用</span>
            <strong>{{ enabledTenantCount }}</strong>
            <small>当前页可正常访问</small>
          </div>
        </article>
        <article>
          <div class="tenant-page__metric-icon is-warning">
            <ArtSvgIcon icon="ri:shield-keyhole-line" />
          </div>
          <div>
            <span>受保护身份</span>
            <strong>{{ systemTenantCodes.size }}</strong>
            <small>平台与注册租户不可删除</small>
          </div>
        </article>
      </div>
    </section>

    <ArtTableQuery
      ref="tableQueryRef"
      focusable
      v-model="searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
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
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { deleteTenant, deleteTenantBatch, fetchGetTenantList } from '@/api/system-manage'
  import TenantDialog from './modules/tenant-dialog.vue'
  import { useUserStore } from '@/store/modules/user'
  import { useSystemParam } from '@/hooks'

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
  }
  const userStore = useUserStore()
  const { getDictMap, isSuper } = storeToRefs(userStore)
  const { defaultRegisterTenantCode, loadRoleBuiltinCodes } = useSystemParam()

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const overview = reactive<{ total: number; rows: TenantOverviewRow[] }>({
    total: 0,
    rows: []
  })
  const systemTenantCodes = computed(
    () => new Set(['platform', defaultRegisterTenantCode.value.toLowerCase()])
  )
  const canManageTenant = computed(() => Boolean(isSuper.value))
  const enabledTenantCount = computed(
    () => overview.rows.filter((row) => String(row.status) === '1').length
  )

  onMounted(() => {
    void loadRoleBuiltinCodes()
  })

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
    emptyDescription: canManageTenant.value
      ? '可调整筛选条件，或新增租户后再查看。'
      : '当前账号仅能查看已授权的租户信息。'
  }

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() =>
    canManageTenant.value
      ? [
          {
            type: 'add',
            permission: 'System:Tenant:Add',
            onClick: () => openDialog()
          },
          {
            type: 'delete',
            permission: 'System:Tenant:Delete',
            content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
              `确定删除选中的 ${selectedCount} 个租户吗？删除后无法恢复。`,
            onClick: async ({ selectedRows }) => {
              const ids = selectedRows.map((row) => row.id).filter(Boolean)
              await deleteTenantBatch(ids)
              await tableQueryRef.value?.refreshRemove()
            }
          }
        ]
      : []
  )

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
      selectable: (row: Tenant) => canManageTenant.value && !isSystemTenant(row)
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
      formatter: (row) =>
        canManageTenant.value ? (
          <div class="tenant-row-actions">
            <ArtButtonTable type="edit" onClick={() => openDialog(row)} />
            {!isSystemTenant(row) ? (
              <ArtButtonMore
                list={getTenantMoreActions(row)}
                onClick={(item: ButtonMoreItem) => handleTenantAction(item, row)}
              />
            ) : null}
          </div>
        ) : (
          <span class="tenant-readonly-cell">只读</span>
        )
    }
  ]

  const openDialog = (row?: Tenant): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const isSystemTenant = (row: Pick<Tenant, 'tenantCode'>): boolean => {
    return systemTenantCodes.value.has(String(row.tenantCode ?? '').toLowerCase())
  }

  const getTenantMoreActions = (row: Tenant): ButtonMoreItem[] => {
    return isSystemTenant(row)
      ? []
      : [
          {
            key: 'delete',
            label: '删除租户',
            icon: 'ri:delete-bin-4-line',
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
    overview.rows = rows.map((row) => ({ status: row.status }))
    overview.total = response.total ?? rows.length
  }

  const handleDelete = async (row: Tenant): Promise<void> => {
    if (!row.id) return

    try {
      await confirmAction(
        `删除「${row.tenantName}」后，其账号、角色及业务数据关联可能受到影响。确认继续吗？`,
        '删除租户',
        {
          confirmButtonText: '确认删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteTenant(row.id)
      await tableQueryRef.value?.refreshRemove()
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
      justify-content: space-between;
      gap: 20px;
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
        overflow-wrap: anywhere;
        font-size: 13px;
        line-height: 1.6;
        color: var(--el-text-color-secondary);
      }
    }

    &__brand {
      justify-content: center;
      flex: 0 0 50px;
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
        min-width: 0;
        gap: 12px;
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
          color: var(--el-text-color-secondary);
          text-overflow: ellipsis;
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
      justify-content: center;
      flex: 0 0 38px;
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
      min-width: 0;
      align-items: center;
      gap: 10px;

      .tenant-identity-cell__icon {
        display: grid;
        flex: 0 0 36px;
        width: 36px;
        height: 36px;
        font-size: 14px;
        font-weight: 700;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border: 1px solid var(--el-color-primary-light-7);
        border-radius: var(--art-control-radius);
        place-items: center;

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
        align-items: center;
        gap: 6px;

        strong {
          overflow: hidden;
          font-weight: 600;
          color: var(--el-text-color-primary);
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      }

      .tenant-identity-cell__code {
        display: block;
        overflow: hidden;
        font-size: 12px;
        color: var(--el-text-color-secondary);
        text-overflow: ellipsis;
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

    @media (max-width: 900px) {
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

    @media (max-width: 640px) {
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
