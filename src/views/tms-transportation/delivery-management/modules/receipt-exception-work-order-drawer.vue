<template>
  <ArtDrawer ref="drawerRef" size="xl" :show-footer="false">
    <template #header>
      <div class="exception-work-orders__drawer-title">
        <span aria-hidden="true"><ArtSvgIcon icon="ri:file-warning-line" /></span>
        <div>
          <strong>签收异常工单</strong>
          <small>AI 风险发现与人工处置闭环</small>
        </div>
      </div>
    </template>

    <div class="exception-work-orders">
      <section class="exception-work-orders__overview art-card-xs">
        <header class="exception-work-orders__overview-header">
          <div class="exception-work-orders__identity">
            <span class="exception-work-orders__hero-icon" aria-hidden="true">
              <ArtSvgIcon icon="ri:shield-check-line" />
            </span>
            <div>
              <span class="exception-work-orders__eyebrow"><i />AI EXCEPTION WORKFLOW</span>
              <h3>签收异常处置中心</h3>
              <p>聚合 AI 识别风险，支持人工认领、核实、解决与关闭，全过程留痕。</p>
            </div>
          </div>
          <ElTag :type="isPlatformSuper ? 'primary' : 'info'" effect="plain" round>
            <ArtSvgIcon
              :icon="isPlatformSuper ? 'ri:verified-badge-line' : 'ri:eye-line'"
              aria-hidden="true"
            />
            {{ isPlatformSuper ? '可执行工单流转' : '只读查看模式' }}
          </ElTag>
        </header>

        <div class="exception-work-orders__metrics">
          <article v-for="metric in metrics" :key="metric.label" :class="`is-${metric.tone}`">
            <span class="exception-work-orders__metric-icon" aria-hidden="true">
              <ArtSvgIcon :icon="metric.icon" />
            </span>
            <div>
              <span>{{ metric.label }}</span>
              <strong>{{ metric.value }}</strong>
              <small>{{ metric.hint }}</small>
            </div>
          </article>
        </div>
      </section>

      <section class="exception-work-orders__workspace art-card-xs">
        <header class="exception-work-orders__workspace-header">
          <div>
            <ArtSectionTitle :show-line="false">异常工单列表</ArtSectionTitle>
            <p>优先处理严重风险与已超过处置时限的工单</p>
          </div>
          <span>{{ state.rows.length }} 个结果</span>
        </header>

        <div class="exception-work-orders__toolbar">
          <ElInput
            v-model="filters.keyword"
            clearable
            name="exception-work-order-keyword"
            aria-label="搜索异常工单"
            autocomplete="off"
            placeholder="搜索工单号、运单号或异常摘要…"
            @keyup.enter="loadData"
          >
            <template #prefix>
              <ArtSvgIcon icon="ri:search-line" aria-hidden="true" />
            </template>
          </ElInput>
          <ElSelect
            v-model="filters.status"
            clearable
            aria-label="筛选工单状态"
            placeholder="全部状态"
            @change="loadData"
          >
            <ElOption
              v-for="item in statusOptions"
              :key="item.value"
              :label="item.label"
              :value="item.value"
            />
          </ElSelect>
          <ElButton :loading="state.loading" @click="loadData">
            <ArtSvgIcon icon="ri:refresh-line" aria-hidden="true" />刷新
          </ElButton>
        </div>

        <ArtAsyncState
          :loading="state.loading"
          loading-mode="skeleton"
          :error="state.error"
          :empty="!state.rows.length"
          empty-text="暂无签收异常工单"
          :min-height="280"
          @retry="loadData"
        >
          <template #empty-action>
            <div class="exception-work-orders__empty-action">
              <span>新识别的签收风险会自动进入这里</span>
              <ElButton plain :loading="state.loading" @click="loadData">重新检查</ElButton>
            </div>
          </template>

          <div class="exception-work-orders__list">
            <article v-for="row in state.rows" :key="row.id" class="exception-work-orders__item">
              <header>
                <div>
                  <strong>{{ row.workOrderNo }}</strong>
                  <ElTag :type="severityMeta[row.severity].type" size="small" effect="light">{{
                    severityMeta[row.severity].label
                  }}</ElTag>
                  <ElTag :type="statusMeta[row.status].type" size="small" effect="plain">{{
                    statusMeta[row.status].label
                  }}</ElTag>
                </div>
                <span :class="{ 'is-overdue': isOverdue(row) }">{{ dueText(row) }}</span>
              </header>
              <div class="exception-work-orders__item-body">
                <div>
                  <small>关联运单</small><strong>{{ row.orderNoSnapshot }}</strong>
                </div>
                <div>
                  <small>异常类型</small>
                  <strong>{{ row.exceptionTypes.join('、') || '待复核' }}</strong>
                </div>
                <div class="is-summary">
                  <small>AI 异常摘要</small><p>{{ row.summary }}</p>
                </div>
              </div>
              <footer>
                <small>
                  创建于 {{ formatDate(row.createTime) }}
                  <template v-if="row.createBy"> · {{ row.createBy }}</template>
                </small>
                <div v-if="isPlatformSuper" class="exception-work-orders__actions">
                  <ElButton
                    v-if="row.status === 'pending'"
                    type="primary"
                    link
                    @click="transition(row, 'in_progress')"
                    >认领处理</ElButton
                  >
                  <ElButton
                    v-if="row.status === 'in_progress'"
                    type="success"
                    link
                    @click="transition(row, 'resolved')"
                    >标记解决</ElButton
                  >
                  <ElButton
                    v-if="row.status === 'resolved'"
                    type="primary"
                    link
                    @click="transition(row, 'closed')"
                    >关闭工单</ElButton
                  >
                  <ElButton
                    v-if="row.status === 'resolved'"
                    link
                    @click="transition(row, 'in_progress')"
                    >重新处理</ElButton
                  >
                  <ElButton
                    v-if="['pending', 'in_progress'].includes(row.status)"
                    type="danger"
                    link
                    @click="transition(row, 'cancelled')"
                    >取消</ElButton
                  >
                </div>
              </footer>
            </article>
          </div>
        </ArtAsyncState>
      </section>
    </div>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import { ElMessage } from 'element-plus'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { fetchReceiptExceptionWorkOrders, transitionReceiptExceptionWorkOrder } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'

  defineOptions({ name: 'TmsReceiptExceptionWorkOrderDrawer' })
  type WorkOrder = Api.Tms.Delivery.ReceiptExceptionWorkOrder
  type Status = Api.Tms.Delivery.ReceiptExceptionStatus

  const drawerRef = ref<ArtDrawerExpose>()
  const { isPlatformSuper } = storeToRefs(useUserStore())
  const { promptReason } = useArtFeedback()
  const filters = reactive<{ keyword: string; status: Status | '' }>({ keyword: '', status: '' })
  const state = reactive<{ loading: boolean; error: Error | null; rows: WorkOrder[] }>({
    loading: false,
    error: null,
    rows: []
  })
  const statusOptions = [
    { label: '待处理', value: 'pending' },
    { label: '处理中', value: 'in_progress' },
    { label: '已解决', value: 'resolved' },
    { label: '已关闭', value: 'closed' },
    { label: '已取消', value: 'cancelled' }
  ]
  const statusMeta: Record<
    Status,
    { label: string; type: 'info' | 'primary' | 'success' | 'warning' | 'danger' }
  > = {
    pending: { label: '待处理', type: 'warning' },
    in_progress: { label: '处理中', type: 'primary' },
    resolved: { label: '已解决', type: 'success' },
    closed: { label: '已关闭', type: 'info' },
    cancelled: { label: '已取消', type: 'info' }
  }
  const severityMeta = {
    low: { label: '低风险', type: 'info' as const },
    medium: { label: '中风险', type: 'warning' as const },
    high: { label: '高风险', type: 'danger' as const },
    critical: { label: '严重风险', type: 'danger' as const }
  }
  const metrics = computed(() => [
    {
      label: '工单总数',
      value: state.rows.length,
      hint: '当前筛选范围',
      icon: 'ri:file-list-3-line',
      tone: 'primary'
    },
    {
      label: '待处置',
      value: state.rows.filter((row) => ['pending', 'in_progress'].includes(row.status)).length,
      hint: '待处理 + 处理中',
      icon: 'ri:timer-flash-line',
      tone: 'warning'
    },
    {
      label: '已超时',
      value: state.rows.filter(isOverdue).length,
      hint: '已超过处置时限',
      icon: 'ri:alarm-warning-line',
      tone: 'danger'
    },
    {
      label: '严重风险',
      value: state.rows.filter((row) => row.severity === 'critical').length,
      hint: '建议优先处理',
      icon: 'ri:shield-flash-line',
      tone: 'danger'
    }
  ])

  function formatDate(value: string) {
    return dayjs(value).format('YYYY-MM-DD HH:mm')
  }
  function isOverdue(row: WorkOrder) {
    return ['pending', 'in_progress'].includes(row.status) && dayjs().isAfter(dayjs(row.dueAt))
  }
  function dueText(row: WorkOrder) {
    return isOverdue(row)
      ? `已超时 · ${formatDate(row.dueAt)}`
      : `处置时限 ${formatDate(row.dueAt)}`
  }

  async function loadData() {
    state.loading = true
    state.error = null
    try {
      const { data, error } = await fetchReceiptExceptionWorkOrders(filters)
      if (error) throw error
      state.rows = data ?? []
    } catch (error) {
      state.error = error instanceof Error ? error : new Error('异常工单加载失败')
    } finally {
      state.loading = false
    }
  }

  async function transition(row: WorkOrder, nextStatus: Status) {
    try {
      let note: string | undefined
      if (['resolved', 'cancelled'].includes(nextStatus)) {
        note = await promptReason(
          '处理说明将进入异常工单审计记录。',
          nextStatus === 'resolved' ? '解决异常工单' : '取消异常工单',
          {
            confirmButtonText: '确认提交',
            placeholder: '请填写核实结果、处理措施或取消原因',
            emptyMessage: '处理说明不能为空'
          }
        )
      }
      await transitionReceiptExceptionWorkOrder(row.id, nextStatus, note)
      ElMessage.success('异常工单状态已更新')
      await loadData()
    } catch {
      /* 用户取消或接口已提示 */
    }
  }

  async function handleOpen() {
    await drawerRef.value?.handleOpen(undefined, {
      title: '签收异常工单',
      size: 'xl',
      contentHeight: 'calc(100vh - 116px)',
      onOpen: loadData,
      onReset: () => {
        Object.assign(filters, { keyword: '', status: '' })
        Object.assign(state, { loading: false, error: null, rows: [] })
      },
      drawerProps: {
        appendToBody: true,
        closeOnClickModal: false,
        resizable: true
      }
    })
  }
  defineExpose({ handleOpen, loadData })
</script>

<style scoped lang="scss">
  .exception-work-orders {
    display: grid;
    gap: 20px;
    min-width: 0;
    overscroll-behavior: contain;

    &__drawer-title,
    &__overview-header,
    &__identity,
    &__toolbar,
    &__workspace-header,
    &__item header,
    &__item footer,
    &__item header > div,
    &__actions {
      display: flex;
      align-items: center;
    }

    &__drawer-title {
      gap: 11px;

      > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 38px;
        height: 38px;
        font-size: 19px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: var(--el-border-radius-base);
      }

      strong,
      small {
        display: block;
      }

      strong {
        font-size: 16px;
        color: var(--el-text-color-primary);
      }

      small {
        margin-top: 3px;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__overview {
      position: relative;
      display: grid;
      gap: 18px;
      padding: 20px;
      overflow: hidden;
      border-top: 3px solid var(--el-color-primary);

      &::after {
        position: absolute;
        top: -96px;
        right: -70px;
        width: 250px;
        height: 250px;
        pointer-events: none;
        content: '';
        background: radial-gradient(circle, var(--el-color-primary-light-8), transparent 70%);
        border-radius: 50%;
        opacity: 0.5;
      }
    }

    &__overview-header {
      z-index: 1;
      gap: 18px;
      justify-content: space-between;

      .el-tag {
        flex: none;
        gap: 5px;
      }
    }

    &__identity {
      gap: 12px;
      min-width: 0;

      > div {
        min-width: 0;
      }
    }

    &__hero-icon {
      display: grid;
      flex: 0 0 48px;
      place-items: center;
      width: 48px;
      height: 48px;
      font-size: 23px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);
    }

    &__eyebrow {
      display: flex;
      gap: 6px;
      align-items: center;
      margin-bottom: 3px;
      font-size: 10px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.9px;

      i {
        width: 5px;
        height: 5px;
        background: currentcolor;
        border-radius: 50%;
      }
    }

    &__identity h3 {
      margin: 0;
      font-size: 18px;
      color: var(--el-text-color-primary);
    }

    &__identity p {
      margin: 5px 0 0;
      font-size: 13px;
      line-height: 1.5;
      color: var(--el-text-color-secondary);
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
    }

    &__metrics article {
      display: flex;
      gap: 12px;
      align-items: center;
      min-width: 0;
      padding: 14px;
      background: var(--el-fill-color-extra-light);
      border: 1px solid var(--el-border-color-extra-light);
      border-radius: var(--el-border-radius-base);

      > div {
        display: grid;
        min-width: 0;
      }
    }

    &__metric-icon {
      display: grid;
      flex: none;
      place-items: center;
      width: 36px;
      height: 36px;
      font-size: 18px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);
    }

    &__metrics article.is-warning &__metric-icon {
      color: var(--el-color-warning);
      background: var(--el-color-warning-light-9);
    }

    &__metrics article.is-danger &__metric-icon {
      color: var(--el-color-danger);
      background: var(--el-color-danger-light-9);
    }

    &__metrics article > div > span,
    &__metrics article small {
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }

    &__metrics strong {
      margin: 2px 0;
      font-size: 25px;
      font-variant-numeric: tabular-nums;
      line-height: 1;
      color: var(--el-text-color-primary);
    }

    &__workspace {
      min-width: 0;
      padding: 18px;
    }

    &__workspace-header {
      gap: 16px;
      justify-content: space-between;
      margin-bottom: 14px;

      > div {
        min-width: 0;

        p {
          margin: 4px 0 0 11px;
          font-size: 12px;
          color: var(--el-text-color-secondary);
        }
      }

      > span {
        flex: none;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }

      :deep(.art-section-title) {
        margin: 0;
      }
    }

    &__toolbar {
      gap: 10px;
      padding: 12px;
      margin-bottom: 14px;
      background: var(--el-fill-color-extra-light);
      border: 1px solid var(--el-border-color-extra-light);
      border-radius: var(--el-border-radius-base);
    }

    &__toolbar .el-input {
      max-width: 360px;
    }

    &__toolbar .el-select {
      width: 150px;
    }

    &__list {
      display: grid;
      gap: 12px;
    }

    &__item {
      padding: 0;
      overflow: hidden;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__item header,
    &__item footer {
      gap: 12px;
      justify-content: space-between;
      padding: 12px 16px;
    }

    &__item header {
      border-bottom: 1px solid var(--el-border-color-lighter);
    }

    &__item header > div,
    &__actions {
      gap: 8px;
    }

    &__item header > span {
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }

    &__item header > span.is-overdue {
      color: var(--el-color-danger);
    }

    &__item-body {
      display: grid;
      grid-template-columns: 1fr 1.2fr 2.8fr;
      gap: 16px;
      padding: 14px 16px;
    }

    &__item-body div {
      display: flex;
      flex-direction: column;
      gap: 5px;
      min-width: 0;
    }

    &__item-body small,
    &__item footer > small {
      color: var(--el-text-color-secondary);
    }

    &__item-body p {
      margin: 0;
      line-height: 1.6;
    }

    &__item footer {
      background: var(--el-fill-color-extra-light);
    }

    &__empty-action {
      display: grid;
      gap: 10px;
      justify-items: center;

      span {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    @media (width <= 900px) {
      &__metrics {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__item-body {
        grid-template-columns: 1fr 1fr;
      }

      &__item-body .is-summary {
        grid-column: 1 / -1;
      }
    }

    @media (width <= 620px) {
      &__overview-header,
      &__toolbar,
      &__workspace-header,
      &__item footer {
        flex-direction: column;
        align-items: stretch;
      }

      &__overview {
        padding: 16px;
      }

      &__identity {
        align-items: flex-start;
      }

      &__overview-header .el-tag {
        width: fit-content;
      }

      &__metrics {
        grid-template-columns: 1fr 1fr;
      }

      &__item-body {
        grid-template-columns: 1fr;
      }

      &__item-body .is-summary {
        grid-column: auto;
      }

      &__toolbar .el-input,
      &__toolbar .el-select {
        width: 100%;
        max-width: none;
      }

      &__toolbar .el-button {
        width: 100%;
      }
    }
  }
</style>
