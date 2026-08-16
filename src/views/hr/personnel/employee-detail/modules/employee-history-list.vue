<template>
  <section class="employee-history-list art-card-xs">
    <header class="employee-history-list__header">
      <div class="employee-history-list__identity">
        <span aria-hidden="true"><ArtSvgIcon :icon="icon" /></span>
        <div>
          <h2>{{ title }}</h2>
          <p>{{ description }}</p>
        </div>
      </div>
      <ElTag type="primary" effect="plain" round>{{ records.length }} 条记录</ElTag>
    </header>

    <div v-if="records.length" class="employee-history-list__records">
      <article v-for="(record, index) in records" :key="record.id || index">
        <header>
          <strong>{{ getTitle(record, index) }}</strong>
          <ElTag v-if="getSubtitle(record)" effect="plain" round>
            {{ getSubtitle(record) }}
          </ElTag>
        </header>
        <ArtDescriptions :data="record" :items="items" :columns="columns" />
      </article>
    </div>
    <ElEmpty v-else :description="`暂无${title}`" :image-size="72" />
  </section>
</template>

<script setup lang="ts">
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  type HistoryRecord = { id?: string }

  withDefaults(
    defineProps<{
      title: string
      description: string
      icon: string
      records: HistoryRecord[]
      items: ArtDescriptionItem<HistoryRecord>[]
      getTitle: (record: HistoryRecord, index: number) => string
      getSubtitle: (record: HistoryRecord) => string
      columns?: number
    }>(),
    { columns: 3 }
  )
</script>

<style scoped lang="scss">
  .employee-history-list {
    min-width: 0;
    padding: 20px;

    &__header,
    &__identity,
    &__identity > span,
    &__records > article > header {
      display: flex;
      align-items: center;
    }

    &__header {
      gap: 16px;
      justify-content: space-between;
      margin-bottom: 16px;
    }

    &__identity {
      min-width: 0;

      > span {
        flex: 0 0 42px;
        justify-content: center;
        width: 42px;
        height: 42px;
        margin-right: 12px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: var(--el-border-radius-base);
      }

      h2 {
        margin: 0;
        font-size: 17px;
      }

      p {
        margin: 4px 0 0;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__records {
      display: grid;
      gap: 14px;

      > article {
        overflow: hidden;
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--custom-radius);
      }

      > article > header {
        gap: 10px;
        justify-content: space-between;
        padding: 12px 16px;
        background: color-mix(in srgb, var(--el-color-primary-light-9) 46%, var(--el-bg-color));
        border-bottom: 1px solid var(--el-border-color-lighter);
      }

      :deep(.art-descriptions) {
        padding: 16px;
      }
    }

    @media (width <= 640px) {
      padding: 16px;

      &__header {
        align-items: flex-start;
      }

      &__identity p {
        display: none;
      }
    }
  }
</style>
