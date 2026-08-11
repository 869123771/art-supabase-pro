<template>
  <ArtDialog ref="dialogRef">
    <div class="master-delete-guard">
      <div class="master-delete-guard__lead">
        <div>
          <p>
            {{
              resourceTitle
            }}仍被以下业务资料引用。可勾选安全项直接清理，业务历史请进入对应页面处理。
          </p>
          <span>系统不会自动删除运单、合同、财务、审批或维修历史。</span>
        </div>
        <ElTag type="warning" effect="light">共 {{ dependencies.length }} 条关联</ElTag>
      </div>

      <div class="master-delete-guard__groups">
        <section
          v-for="(group, index) in dependencyGroups"
          :key="group.code"
          class="master-delete-guard__group"
        >
          <header class="master-delete-guard__group-header">
            <div class="master-delete-guard__group-title">
              <span>{{ index + 1 }}</span>
              <strong>{{ group.meta.label }}</strong>
            </div>
            <div class="master-delete-guard__group-header-actions">
              <ElCheckbox
                v-if="getGroupSafeRecords(group).length"
                :model-value="isGroupFullySelected(group)"
                :indeterminate="isGroupPartiallySelected(group)"
                @change="(checked) => toggleGroupSelection(group, Boolean(checked))"
              >
                全选可清理项
              </ElCheckbox>
              <ElTag type="warning" effect="plain" size="small">
                {{ group.records.length }} {{ group.meta.unit }}
              </ElTag>
            </div>
          </header>
          <p class="master-delete-guard__group-help">{{ group.meta.description }}</p>

          <div class="master-delete-guard__records">
            <div
              v-for="record in group.records"
              :key="record.recordId"
              class="master-delete-guard__record"
            >
              <ElCheckbox
                v-if="record.cleanupAllowed"
                :model-value="selectedRecordIds.includes(record.recordId)"
                :aria-label="`选择清理 ${record.recordNo}`"
                @change="(checked) => toggleRecordSelection(record.recordId, Boolean(checked))"
              />
              <span v-else class="master-delete-guard__record-spacer" aria-hidden="true" />

              <div class="master-delete-guard__record-copy">
                <strong :title="record.recordNo">{{ record.recordNo || '未编号记录' }}</strong>
                <span :title="formatRecordMeta(record)">{{ formatRecordMeta(record) }}</span>
              </div>

              <div class="master-delete-guard__record-actions">
                <ElTag
                  :type="record.cleanupAllowed ? 'success' : 'info'"
                  effect="light"
                  size="small"
                >
                  {{ record.cleanupAllowed ? '可选择清理' : '需保留/处理' }}
                </ElTag>
                <ElButton
                  v-if="group.meta.routeName || group.meta.routePath"
                  link
                  type="primary"
                  @click="openDependency(group.meta, record)"
                >
                  {{ group.meta.actionLabel }}
                  <i class="ri:arrow-right-s-line" aria-hidden="true" />
                </ElButton>
              </div>
            </div>
          </div>
        </section>
      </div>

      <div class="master-delete-guard__notice">
        <i class="ri:information-line" aria-hidden="true" />
        <span>处理页面会携带主数据 ID 和关联记录 ID，并在打开后自动过滤。</span>
      </div>
    </div>

    <template #footer="{ api }">
      <div class="master-delete-guard__footer">
        <span v-if="safeRecordCount">
          已选择 {{ selectedRecordIds.length }} / {{ safeRecordCount }} 个安全项
        </span>
        <span v-else>当前关联均属于需保留或先处理的业务记录</span>
        <div class="master-delete-guard__footer-actions">
          <ElButton @click="api.handleClose()">关闭</ElButton>
          <ElButton
            v-if="safeRecordCount"
            type="danger"
            plain
            :loading="cleanupLoading"
            :disabled="!selectedRecordIds.length"
            @click="handleCleanup"
          >
            清理选中项（{{ selectedRecordIds.length }}）
          </ElButton>
        </div>
      </div>
    </template>
  </ArtDialog>
</template>

<script setup lang="ts">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import { groupBy, uniq } from 'lodash-es'
  import { ElMessage } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import {
    cleanupMasterDataDeleteDependencies,
    fetchMasterDataDeleteDependencies,
    type MasterDataDeleteDependencyDetail,
    type MasterDataDeleteResourceType
  } from '@/api/master-data-delete'

  defineOptions({ name: 'MasterDataDeleteGuard' })

  export interface MasterDataDeleteResource {
    id: string
    label: string
  }

  export interface MasterDataDeleteGuardOpenOptions {
    resourceType: MasterDataDeleteResourceType
    resourceLabel: string
    resources: MasterDataDeleteResource[]
  }

  interface DependencyMeta {
    label: string
    unit: string
    description: string
    actionLabel: string
    routeName?: string
    routePath?: string
    order: number
  }

  interface DependencyGroup {
    code: string
    meta: DependencyMeta
    records: MasterDataDeleteDependencyDetail[]
  }

  const emit = defineEmits<{ cleared: [] }>()
  const router = useRouter()
  const route = useRoute()
  const { confirmAction } = useArtFeedback()
  const dialogRef = ref<ArtDialogExpose<Record<string, never>>>()
  const currentOptions = shallowRef<MasterDataDeleteGuardOpenOptions>()
  const dependencies = shallowRef<MasterDataDeleteDependencyDetail[]>([])
  const selectedRecordIds = ref<string[]>([])
  const cleanupLoading = ref(false)

  const dependencyMeta: Record<string, DependencyMeta> = {
    carrier_price: {
      label: '承运商价格方案',
      unit: '条',
      description: '报价配置不属于业务历史，可按需勾选后直接清理。',
      actionLabel: '去处理报价',
      routeName: 'TmsCarrierPrice',
      order: 10
    },
    contract: {
      label: '承运合同',
      unit: '份',
      description: '合同属于经营与审批历史，应先作废或保留并停用承运商。',
      actionLabel: '去处理合同',
      routeName: 'TmsContract',
      order: 20
    },
    driver: {
      label: '归属司机',
      unit: '名',
      description: '请先调整司机归属或逐个处理司机资料。',
      actionLabel: '去处理司机',
      routeName: 'TmsDriver',
      order: 30
    },
    waybill: createWaybillMeta('关联运单', 40),
    driver_waybill: createWaybillMeta('司机关联运单', 10),
    cargo_waybill: createWaybillMeta('货物关联运单', 10),
    address_waybill: createWaybillMeta('地址关联运单', 10),
    vehicle_waybill: createWaybillMeta('车辆关联运单', 10),
    carrier_statement: createFinanceMeta('承运商对账单', '张', 'TmsCarrierSettlement', 50),
    carrier_statement_item: createFinanceMeta('承运商对账明细', '条', 'TmsCarrierSettlement', 60),
    payment_application: createFinanceMeta('付款申请', '张', 'TmsCarrierPaymentApplication', 70),
    payment_application_item: createFinanceMeta(
      '付款申请明细',
      '条',
      'TmsCarrierPaymentApplication',
      80
    ),
    carrier_cash_allocation: createFinanceMeta('付款核销', '条', 'TmsCashTransaction', 90),
    carrier_cash_transaction: createFinanceMeta('付款流水', '笔', 'TmsCashTransaction', 100),
    carrier_invoice: createFinanceMeta('承运商发票', '张', 'TmsInvoiceManagement', 110),
    vehicle_reminder_work_order: {
      label: '车辆提醒工单',
      unit: '条',
      description: '进行中工单需先处理；已取消或已关闭工单可勾选清理。',
      actionLabel: '去处理工单',
      routePath: '/vehicle-manage-system/reminder-manage',
      order: 20
    },
    organization_child: createGovernanceMeta(
      '下级组织',
      '个',
      '请先迁移或停用下级组织，再删除当前组织节点。',
      '去处理组织',
      'Organization',
      10
    ),
    organization_user: createGovernanceMeta(
      '组织成员',
      '名',
      '用户档案与登录身份需要保留，请先迁移到其他组织或注销账号。',
      '去处理用户',
      'User',
      20
    ),
    organization_role: createGovernanceMeta(
      '组织角色',
      '个',
      '角色仍绑定当前组织，请先迁移、停用或处理角色。',
      '去处理角色',
      'Role',
      30
    ),
    role_menu_grant: createGovernanceMeta(
      '菜单授权',
      '项',
      '菜单授权属于权限配置，可按需勾选解绑。',
      '去查看菜单',
      'Menu',
      10
    ),
    role_user_assignment: createGovernanceMeta(
      '用户角色分配',
      '人',
      '用户档案不会删除，仅从选中用户解除该角色。',
      '去处理用户',
      'User',
      20
    ),
    menu_role_grant: createGovernanceMeta(
      '角色菜单授权',
      '项',
      '删除菜单前可选择解除角色授权，用户与角色本身不会删除。',
      '去处理角色',
      'Role',
      10
    ),
    menu_document_number_scene: createGovernanceMeta(
      '编号规则场景',
      '项',
      '编号规则仍定位到当前菜单，应先调整场景归属后再删除菜单。',
      '去处理编号规则',
      'DocumentNumberRule',
      20
    ),
    dict_type_child: createGovernanceMeta(
      '下级字典类型',
      '个',
      '目录存在下级类型时不直接级联删除，请先逐级确认。',
      '去处理字典',
      'Dict',
      10
    ),
    dict_type_item: createGovernanceMeta(
      '字典项',
      '项',
      '字典项属于系统配置，可逐项勾选清理。',
      '去处理字典',
      'Dict',
      20
    ),
    dictionary_child: createGovernanceMeta(
      '下级字典项',
      '项',
      '下级字典项可按需勾选清理，避免隐藏级联删除。',
      '去处理字典',
      'Dict',
      10
    ),
    attachment_waybill_proof: createGovernanceMeta(
      '运单凭证引用',
      '处',
      '附件已作为运单交付凭证使用，必须保留或先替换凭证。',
      '去查看运单',
      'TmsLoadedWaybillList',
      10
    ),
    order_waybill: createWaybillMeta('订单关联运单', 10),
    order_expense: createGovernanceMeta(
      '订单在途费用',
      '笔',
      '费用属于经营与财务历史，不允许随订单物理删除。',
      '去处理费用',
      'TmsInTransitExpense',
      20
    ),
    order_receipt_work_order: createGovernanceMeta(
      '回单异常工单',
      '张',
      '异常工单属于处置记录，应先关闭或保留订单。',
      '去处理工单',
      'TmsDeliveryManagement',
      30
    ),
    order_statement_item: createGovernanceMeta(
      '客户对账明细',
      '条',
      '对账明细属于财务审计历史，不允许随订单删除。',
      '去处理对账',
      'TmsCustomerSettlement',
      40
    )
  }

  function createGovernanceMeta(
    label: string,
    unit: string,
    description: string,
    actionLabel: string,
    routeName: string,
    order: number
  ): DependencyMeta {
    return { label, unit, description, actionLabel, routeName, order }
  }

  function createWaybillMeta(label: string, order: number): DependencyMeta {
    return {
      label,
      unit: '单',
      description: '运单属于运输履约历史，不允许级联物理删除。',
      actionLabel: '去查看运单',
      routeName: 'TmsLoadedWaybillList',
      order
    }
  }

  function createFinanceMeta(
    label: string,
    unit: string,
    routeName: string,
    order: number
  ): DependencyMeta {
    return {
      label,
      unit,
      description: '财务记录属于审计历史，不允许跟随主数据物理删除。',
      actionLabel: '去处理记录',
      routeName,
      order
    }
  }

  const resourceIds = computed(() => currentOptions.value?.resources.map((item) => item.id) ?? [])
  const resourceTitle = computed(() => {
    const options = currentOptions.value
    if (!options) return '当前资料'
    if (options.resources.length === 1) {
      return `${options.resourceLabel}“${options.resources[0].label}”`
    }
    return `选中的 ${options.resources.length} 个${options.resourceLabel}`
  })
  const safeRecordCount = computed(
    () => dependencies.value.filter((item) => item.cleanupAllowed).length
  )
  const dependencyGroups = computed<DependencyGroup[]>(() => {
    const groups = groupBy(dependencies.value, (item) => item.dependencyCode)
    return Object.entries(groups)
      .map(([code, records]) => ({
        code,
        records,
        meta: dependencyMeta[code] ?? {
          label: code,
          unit: '条',
          description: '该记录仍引用当前主数据，请先处理后再删除。',
          actionLabel: '去处理',
          order: 999
        }
      }))
      .sort((left, right) => left.meta.order - right.meta.order)
  })

  const formatRecordMeta = (record: MasterDataDeleteDependencyDetail): string => {
    const parts = [record.recordSummary, record.recordStatus]
    if (record.recordAmount !== null && record.recordAmount !== undefined) {
      parts.push(
        `¥${Number(record.recordAmount).toLocaleString('zh-CN', {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2
        })}`
      )
    }
    return parts.filter(Boolean).join(' · ') || '待处理'
  }

  const toggleRecordSelection = (recordId: string, checked: boolean): void => {
    selectedRecordIds.value = checked
      ? uniq([...selectedRecordIds.value, recordId])
      : selectedRecordIds.value.filter((id) => id !== recordId)
  }

  const getGroupSafeRecords = (group: DependencyGroup): MasterDataDeleteDependencyDetail[] =>
    group.records.filter((record) => record.cleanupAllowed)

  const isGroupFullySelected = (group: DependencyGroup): boolean => {
    const safeRecords = getGroupSafeRecords(group)
    return (
      safeRecords.length > 0 &&
      safeRecords.every((record) => selectedRecordIds.value.includes(record.recordId))
    )
  }

  const isGroupPartiallySelected = (group: DependencyGroup): boolean => {
    const selectedCount = getGroupSafeRecords(group).filter((record) =>
      selectedRecordIds.value.includes(record.recordId)
    ).length
    return selectedCount > 0 && !isGroupFullySelected(group)
  }

  const toggleGroupSelection = (group: DependencyGroup, checked: boolean): void => {
    const groupRecordIds = getGroupSafeRecords(group).map((record) => record.recordId)
    selectedRecordIds.value = checked
      ? uniq([...selectedRecordIds.value, ...groupRecordIds])
      : selectedRecordIds.value.filter((recordId) => !groupRecordIds.includes(recordId))
  }

  const loadDependencies = async (): Promise<void> => {
    const options = currentOptions.value
    if (!options) return
    dependencies.value = await fetchMasterDataDeleteDependencies(
      options.resourceType,
      resourceIds.value
    )
    selectedRecordIds.value = []
  }

  const inspect = async (options: MasterDataDeleteGuardOpenOptions): Promise<boolean> => {
    currentOptions.value = options
    await loadDependencies()
    if (!dependencies.value.length) return false
    await dialogRef.value?.handleOpen(
      {},
      {
        title: `暂时无法删除${options.resourceLabel}`,
        size: 'md',
        contentMaxHeight: '68vh',
        showCancelButton: false,
        showConfirmButton: false,
        dialogProps: { closeOnClickModal: false }
      }
    )
    return true
  }

  const handleCleanup = async (): Promise<void> => {
    const options = currentOptions.value
    const selected = dependencies.value.filter((item) =>
      selectedRecordIds.value.includes(item.recordId)
    )
    if (!options || !selected.length || cleanupLoading.value) return
    try {
      await confirmAction(
        `将永久清理选中的 ${selected.length} 项配置或终态记录。运单、合同和财务历史不会被删除，是否继续？`,
        '清理关联项确认',
        {
          type: 'warning',
          confirmButtonText: `确认清理 ${selected.length} 项`,
          cancelButtonText: '取消',
          confirmButtonClass: 'el-button--danger',
          closeOnClickModal: false
        }
      )
      cleanupLoading.value = true
      const grouped = groupBy(selected, (item) => item.dependencyCode)
      let deletedCount = 0
      for (const [dependencyCode, records] of Object.entries(grouped)) {
        deletedCount += await cleanupMasterDataDeleteDependencies({
          resourceType: options.resourceType,
          resourceIds: resourceIds.value,
          dependencyCode,
          recordIds: records.map((item) => item.recordId)
        })
      }
      await loadDependencies()
      if (!dependencies.value.length) {
        await dialogRef.value?.handleClose(true)
        ElMessage.success(`已清理 ${deletedCount} 项关联资料，现在可以重新删除`)
        emit('cleared')
        return
      }
      ElMessage.success(`已清理 ${deletedCount} 项，其余业务历史仍需保留或处理`)
    } catch (error) {
      if (error !== 'cancel' && error !== 'close') {
        ElMessage.error(getFriendlySupabaseErrorMessage(error, '清理失败，请稍后重试'))
      }
    } finally {
      cleanupLoading.value = false
    }
  }

  const openDependency = (meta: DependencyMeta, record: MasterDataDeleteDependencyDetail): void => {
    const options = currentOptions.value
    if (!options) return
    const resourceQueryKeyMap: Record<MasterDataDeleteResourceType, string> = {
      carrier: 'carrierId',
      driver: 'driverId',
      cargo: 'cargoId',
      customer_address: 'addressId',
      vehicle: 'vehicleId',
      organization: 'organizationId',
      role: 'roleId',
      menu: 'menuId',
      dict_type: 'dictTypeId',
      dictionary: 'dictionaryId',
      attachment: 'attachmentId',
      order: 'orderId'
    }
    const query = {
      fromMasterDelete: '1',
      resourceType: options.resourceType,
      [resourceQueryKeyMap[options.resourceType]]: record.resourceId,
      recordId: record.targetId,
      recordNo: record.recordNo,
      dependencyCode: record.dependencyCode,
      returnPath: route.path,
      resourceId: record.resourceId,
      resourceLabel: options.resourceLabel,
      resourceName:
        options.resources.find((item) => item.id === record.resourceId)?.label ??
        options.resourceLabel
    }
    void dialogRef.value?.handleClose(true)
    if (meta.routeName) {
      void router.push({ name: meta.routeName, query })
      return
    }
    if (meta.routePath) void router.push({ path: meta.routePath, query })
  }

  defineExpose({ inspect })
</script>

<style scoped lang="scss">
  .master-delete-guard {
    display: grid;
    gap: 12px;
    min-width: 0;

    &__lead {
      display: flex;
      gap: 12px;
      align-items: flex-start;
      justify-content: space-between;

      p {
        margin: 0;
        line-height: 1.6;
        color: var(--el-text-color-primary);
      }

      span {
        display: block;
        margin-top: 2px;
        font-size: 13px;
        line-height: 1.5;
        color: var(--el-text-color-secondary);
      }

      .el-tag {
        flex: none;
      }
    }

    &__groups {
      display: grid;
      gap: 10px;
    }

    &__group {
      padding: 12px;
      background: var(--el-fill-color-light);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__group-header,
    &__group-header-actions,
    &__group-title,
    &__record,
    &__record-actions,
    &__footer,
    &__footer-actions,
    &__notice {
      display: flex;
      align-items: center;
    }

    &__group-header,
    &__footer {
      justify-content: space-between;
    }

    &__group-title {
      gap: 8px;

      > span {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 22px;
        height: 22px;
        font-size: 12px;
        font-weight: 700;
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
        border-radius: 50%;
      }
    }

    &__group-header-actions {
      gap: 10px;
    }

    &__group-help {
      margin: 5px 0 0 30px;
      font-size: 13px;
      line-height: 1.5;
      color: var(--el-text-color-secondary);
    }

    &__records {
      display: grid;
      gap: 6px;
      padding-top: 10px;
      margin-top: 10px;
      border-top: 1px dashed var(--el-border-color);
    }

    &__record {
      gap: 8px;
      min-width: 0;
      padding: 8px;
      background: var(--el-bg-color);
      border-radius: var(--el-border-radius-small);
    }

    &__record-spacer {
      flex: 0 0 14px;
      width: 14px;
    }

    &__record-copy {
      display: grid;
      flex: 1;
      min-width: 0;

      strong,
      span {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      strong {
        font-size: 13px;
        color: var(--el-text-color-primary);
      }

      span {
        margin-top: 2px;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__record-actions,
    &__footer-actions,
    &__notice {
      flex: none;
      gap: 8px;
    }

    &__notice {
      align-items: flex-start;
      padding: 10px 12px;
      font-size: 13px;
      line-height: 1.5;
      color: var(--el-color-warning-dark-2);
      background: var(--el-color-warning-light-9);
      border-radius: var(--el-border-radius-base);

      i {
        margin-top: 1px;
        font-size: 16px;
      }
    }

    &__footer {
      gap: 16px;
      width: 100%;

      > span {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 13px;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }
    }

    @media (width <= 640px) {
      &__lead,
      &__record,
      &__footer {
        flex-direction: column;
        align-items: stretch;
      }

      &__record-actions,
      &__footer-actions {
        justify-content: space-between;
      }

      &__footer-actions .el-button {
        flex: 1;
      }
    }
  }
</style>
