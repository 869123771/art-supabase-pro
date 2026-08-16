<template>
  <aside v-if="isActive" class="master-delete-notice art-card-xs" aria-live="polite">
    <div class="master-delete-notice__content">
      <div class="master-delete-notice__title">
        <ArtSvgIcon icon="ri:links-line" aria-hidden="true" />
        <strong>正在处理“{{ resourceName }}”的删除前置资料</strong>
        <ElTag type="warning" effect="light" size="small">已精确过滤</ElTag>
      </div>
      <p>{{ props.actionHint }}</p>
    </div>
    <ElButton type="primary" plain @click="goBack">
      <template #icon><ArtSvgIcon icon="ri:arrow-left-line" /></template>
      返回{{ resourceLabel }}管理
    </ElButton>
  </aside>
</template>

<script setup lang="ts">
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  const props = withDefaults(
    defineProps<{
      actionHint?: string
      customerId?: string
      customerName?: string
    }>(),
    {
      actionHint: '当前列表已按关联记录自动过滤。请处理完成后返回原页面继续删除。',
      customerId: '',
      customerName: ''
    }
  )

  const route = useRoute()
  const router = useRouter()
  const isMasterDelete = computed(() => route.query.fromMasterDelete === '1')
  const isActive = computed(() => isMasterDelete.value || route.query.fromCustomerDelete === '1')
  const resourceLabel = computed(() =>
    isMasterDelete.value ? String(route.query.resourceLabel || '主数据') : '客户'
  )
  const resourceName = computed(() =>
    isMasterDelete.value
      ? String(route.query.resourceName || '当前资料')
      : props.customerName || '该客户'
  )

  const goBack = (): void => {
    if (isMasterDelete.value) {
      const returnPath = typeof route.query.returnPath === 'string' ? route.query.returnPath : '/'
      void router.push({
        path: returnPath,
        query: {
          resumeMasterDelete: '1',
          recordId: typeof route.query.resourceId === 'string' ? route.query.resourceId : undefined,
          resourceType:
            typeof route.query.resourceType === 'string' ? route.query.resourceType : undefined,
          resourceLabel: resourceLabel.value,
          resourceName: resourceName.value
        }
      })
      return
    }

    void router.push({
      name: 'TmsCustomer',
      query: {
        resumeCustomerDelete: '1',
        customerId: props.customerId,
        customerName: props.customerName || undefined
      }
    })
  }
</script>

<style scoped lang="scss">
  .master-delete-notice {
    display: flex;
    flex: 0 0 auto;
    gap: 16px;
    align-items: center;
    justify-content: space-between;
    min-width: 0;
    padding: 12px 16px;
    border-color: var(--el-color-warning-light-7);

    &__content {
      min-width: 0;

      p {
        margin: 3px 0 0;
        font-size: 13px;
        line-height: 1.5;
        color: var(--el-text-color-secondary);
      }
    }

    &__title {
      display: flex;
      gap: 7px;
      align-items: center;
      min-width: 0;

      > svg {
        flex: none;
        color: var(--el-color-warning-dark-2);
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--el-text-color-primary);
        white-space: nowrap;
      }
    }

    .el-button {
      flex: none;
    }

    @media (width <= 720px) {
      flex-direction: column;
      align-items: stretch;

      .el-button {
        width: 100%;
      }
    }
  }
</style>
