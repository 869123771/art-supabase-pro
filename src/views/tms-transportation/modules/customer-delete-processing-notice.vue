<template>
  <aside class="customer-delete-processing-notice art-card-xs" aria-live="polite">
    <div class="customer-delete-processing-notice__icon" aria-hidden="true">
      <ArtSvgIcon icon="ri:links-line" />
    </div>

    <div class="customer-delete-processing-notice__content">
      <div class="customer-delete-processing-notice__title">
        <strong>正在处理“{{ processingName }}”的删除前置资料</strong>
        <ElTag type="warning" effect="light" size="small">已精确定位</ElTag>
      </div>
      <p>{{ actionHint }}</p>
    </div>

    <ElButton class="customer-delete-processing-notice__back" type="primary" plain @click="goBack">
      <template #icon><ArtSvgIcon icon="ri:arrow-left-line" /></template>
      返回{{ processingLabel }}管理
    </ElButton>
  </aside>
</template>

<script setup lang="ts">
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  const props = defineProps<{
    customerId: string
    customerName?: string
    actionHint: string
  }>()

  const router = useRouter()
  const route = useRoute()
  const isMasterDelete = computed(() => route.query.fromMasterDelete === '1')
  const processingLabel = computed(() =>
    isMasterDelete.value && typeof route.query.resourceLabel === 'string'
      ? route.query.resourceLabel
      : '客户'
  )
  const processingName = computed(() => {
    if (isMasterDelete.value && typeof route.query.resourceName === 'string') {
      return route.query.resourceName
    }
    return props.customerName || '该客户'
  })

  const goBack = (): void => {
    if (isMasterDelete.value && typeof route.query.returnPath === 'string') {
      void router.push({
        path: route.query.returnPath,
        query: {
          resumeMasterDelete: '1',
          recordId: typeof route.query.resourceId === 'string' ? route.query.resourceId : undefined,
          resourceType:
            typeof route.query.resourceType === 'string' ? route.query.resourceType : undefined,
          resourceLabel: processingLabel.value,
          resourceName: processingName.value
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
  .customer-delete-processing-notice {
    display: flex;
    flex: 0 0 auto;
    gap: 12px;
    align-items: center;
    min-width: 0;
    padding: 12px 16px;
    border-color: var(--el-color-warning-light-7);

    &__icon {
      display: inline-flex;
      flex: 0 0 36px;
      align-items: center;
      justify-content: center;
      width: 36px;
      height: 36px;
      font-size: 19px;
      color: var(--el-color-warning-dark-2);
      background: var(--el-color-warning-light-9);
      border-radius: 50%;
    }

    &__content {
      flex: 1;
      min-width: 0;

      p {
        margin: 4px 0 0;
        font-size: 13px;
        line-height: 1.5;
        color: var(--el-text-color-secondary);
      }
    }

    &__title {
      display: flex;
      gap: 8px;
      align-items: center;
      min-width: 0;

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--el-text-color-primary);
        white-space: nowrap;
      }
    }

    &__back {
      flex: none;
    }

    @media (width <= 760px) {
      flex-wrap: wrap;
      align-items: flex-start;

      &__content {
        flex-basis: calc(100% - 48px);
      }

      &__title {
        flex-direction: column;
        align-items: flex-start;
      }

      &__back {
        width: 100%;
      }
    }
  }
</style>
