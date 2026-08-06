<template>
  <section class="ai-order-master-data art-card-xs">
    <div class="ai-order-master-data__heading">
      <div>
        <ArtSectionTitle :show-line="false">前置资料一键建档</ArtSectionTitle>
        <p>勾选资料完整的项目，统一创建后自动重新匹配到当前订单。</p>
      </div>
      <div class="ai-order-master-data__counts">
        <ElTag type="success" effect="plain">可创建 {{ readyCount }} 项</ElTag>
        <ElTag v-if="blockedCount" type="danger" effect="plain">
          待补充 {{ blockedCount }} 项
        </ElTag>
      </div>
    </div>

    <ElCheckboxGroup
      :model-value="selectedKeys"
      class="ai-order-master-data__list"
      @update:model-value="handleSelectedKeysChange"
    >
      <ElCheckbox
        v-for="task in tasks"
        :key="task.key"
        :value="task.key"
        :disabled="!task.ready || creating"
        border
      >
        <span class="ai-order-master-data__item">
          <span class="ai-order-master-data__item-heading">
            <ArtSvgIcon :icon="kindMeta[task.kind].icon" />
            <strong>{{ task.title }}</strong>
            <small>{{ kindMeta[task.kind].label }}</small>
          </span>
          <small>{{ task.description }}</small>
          <em v-if="task.reason">
            <ArtSvgIcon icon="ri:error-warning-line" />
            {{ task.reason }}
          </em>
        </span>
      </ElCheckbox>
    </ElCheckboxGroup>

    <div class="ai-order-master-data__hint">
      <ArtSvgIcon icon="ri:shield-check-line" />
      <span>仅写入当前租户的所选档案；整批失败会全部回滚，订单仍需手动保存。</span>
    </div>
  </section>
</template>

<script setup lang="ts">
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import type { AiOrderMasterDataTask } from './ai-order-types'

  defineOptions({ name: 'TmsAiOrderMasterDataPanel' })

  const props = defineProps<{
    tasks: AiOrderMasterDataTask[]
    creating: boolean
    selectedKeys: string[]
  }>()

  const emit = defineEmits<{
    'update:selectedKeys': [keys: string[]]
  }>()

  const kindMeta: Record<AiOrderMasterDataTask['kind'], { icon: string; label: string }> = {
    station: { icon: 'ri:map-pin-2-line', label: '站点' },
    customer: { icon: 'ri:building-2-line', label: '客户' },
    address: { icon: 'ri:route-line', label: '地址' },
    cargo: { icon: 'ri:archive-stack-line', label: '货物' }
  }
  const readyCount = computed(() => props.tasks.filter((task) => task.ready).length)
  const blockedCount = computed(() => props.tasks.length - readyCount.value)

  watch(
    () => props.tasks,
    (nextTasks) => {
      const available = new Set(nextTasks.filter((task) => task.ready).map((task) => task.key))
      const retained = props.selectedKeys.filter((key) => available.has(key))
      emit('update:selectedKeys', retained.length ? retained : [...available])
    },
    { immediate: true, deep: true }
  )

  function handleSelectedKeysChange(keys: Array<string | number>): void {
    emit('update:selectedKeys', keys.map(String))
  }
</script>

<style scoped lang="scss">
  .ai-order-master-data {
    padding: 16px;

    &__heading {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;

      p {
        margin: 6px 0 0;
        line-height: 1.5;
        color: var(--el-text-color-secondary);
      }
    }

    &__counts {
      display: flex;
      flex: none;
      flex-wrap: wrap;
      gap: 6px;
      justify-content: flex-end;
    }

    &__list {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
      margin-top: 14px;

      :deep(.el-checkbox) {
        width: 100%;
        height: auto;
        min-height: 88px;
        padding: 12px;
        margin: 0;
        border-radius: var(--el-border-radius-base);
      }

      :deep(.el-checkbox__label) {
        min-width: 0;
        white-space: normal;
      }
    }

    &__item {
      display: grid;
      gap: 6px;
      min-width: 0;

      > small {
        overflow: hidden;
        color: var(--el-text-color-secondary);
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      &-heading {
        display: flex;
        gap: 7px;
        align-items: center;
        min-width: 0;

        > svg {
          flex: none;
          color: var(--theme-color);
        }

        small {
          flex: none;
          padding: 2px 6px;
          font-size: 11px;
          color: var(--el-text-color-secondary);
          background: var(--art-main-bg-color);
          border-radius: 999px;
        }
      }

      strong {
        min-width: 0;
        overflow: hidden;
        font-weight: 600;
        color: var(--el-text-color-primary);
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      em {
        display: inline-flex;
        gap: 4px;
        align-items: center;
        font-size: 12px;
        font-style: normal;
        color: var(--el-color-danger);
      }
    }

    &__hint {
      display: flex;
      gap: 7px;
      align-items: flex-start;
      padding: 10px 12px;
      margin-top: 14px;
      line-height: 1.5;
      color: var(--el-text-color-secondary);
      background: color-mix(in srgb, var(--theme-color) 5%, var(--art-main-bg-color));
      border-radius: var(--el-border-radius-base);

      svg {
        flex: none;
        margin-top: 2px;
        color: var(--theme-color);
      }
    }

    @media (width <= 680px) {
      &__heading {
        flex-direction: column;
      }

      &__counts {
        justify-content: flex-start;
      }

      &__list {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
