<template>
  <section class="ai-order-master-data art-card-xs">
    <div class="ai-order-master-data__heading">
      <div>
        <ArtSectionTitle :show-line="false">AI 一键建档</ArtSectionTitle>
        <p>勾选资料完整的项目，确认后统一创建基础档案。</p>
      </div>
      <ElTag type="warning" effect="light">待建档 {{ tasks.length }} 项</ElTag>
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
          <strong>{{ task.title }}</strong>
          <small>{{ task.description }}</small>
          <em v-if="task.reason">{{ task.reason }}</em>
        </span>
      </ElCheckbox>
    </ElCheckboxGroup>

    <p class="ai-order-master-data__hint">创建入口在抽屉底部，只创建基础资料，不会保存当前订单。</p>
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

    &__list {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
      margin-top: 14px;

      :deep(.el-checkbox) {
        width: 100%;
        height: auto;
        min-height: 72px;
        padding: 10px 12px;
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
      gap: 4px;

      strong {
        font-weight: 600;
        color: var(--el-text-color-primary);
      }

      small {
        overflow: hidden;
        color: var(--el-text-color-secondary);
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      em {
        font-size: 12px;
        font-style: normal;
        color: var(--el-color-danger);
      }
    }

    &__hint {
      margin-top: 14px;
      color: var(--el-text-color-secondary);
    }

    @media (width <= 680px) {
      &__list {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
