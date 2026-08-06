<template>
  <aside class="project-assistant-object-browser art-card-xs">
    <div class="project-assistant-object-browser__title">
      <div>
        <strong>项目对象</strong>
        <small>{{ objects.length }} 条结果</small>
      </div>
      <div class="project-assistant-object-browser__actions">
        <ElTooltip :content="focusMode ? '退出专注模式' : '进入专注模式'" placement="bottom">
          <ElButton
            :class="{ 'is-active': focusMode }"
            text
            circle
            :type="focusMode ? 'primary' : undefined"
            :title="focusMode ? '退出专注模式' : '进入专注模式'"
            :aria-label="focusMode ? '退出专注模式' : '进入专注模式'"
            @click="emit('toggle-focus')"
          >
            <ArtSvgIcon :icon="focusMode ? 'ri:fullscreen-exit-line' : 'ri:focus-3-line'" />
          </ElButton>
        </ElTooltip>
        <ElButton
          class="project-assistant-object-browser__refresh"
          :class="{ 'is-refreshing': loading && loadSource === 'refresh' }"
          text
          circle
          type="primary"
          title="刷新项目对象"
          aria-label="刷新项目对象"
          :disabled="loading"
          @click="emit('refresh')"
        >
          <ArtSvgIcon
            class="project-assistant-object-browser__refresh-icon"
            icon="ri:refresh-line"
          />
        </ElButton>
      </div>
    </div>

    <div class="project-assistant-object-browser__filters">
      <ElInput
        :model-value="filters.keyword"
        class="project-assistant-object-browser__search"
        clearable
        placeholder="搜索对象名称"
        @update:model-value="emit('update:keyword', String($event))"
        @keyup.enter="emit('filter')"
        @clear="emit('filter')"
      >
        <template #prefix><ArtSvgIcon icon="ri:search-line" /></template>
      </ElInput>
      <div class="project-assistant-object-browser__selects">
        <ElSelect
          :model-value="filters.schema"
          @update:model-value="emit('update:schema', String($event))"
          @change="emit('filter')"
        >
          <ElOption label="全部 Schema" value="all" />
          <ElOption v-for="schema in schemas" :key="schema" :label="schema" :value="schema" />
        </ElSelect>
        <ElSelect
          :model-value="filters.objectType"
          @update:model-value="emit('update:object-type', $event as ProjectObjectType)"
          @change="emit('filter')"
        >
          <ElOption
            v-for="option in objectTypeOptions"
            :key="option.value"
            :label="option.label"
            :value="option.value"
          />
        </ElSelect>
      </div>
    </div>

    <ArtAsyncState
      class="project-assistant-object-browser__state"
      :loading="loading && loadSource !== 'refresh'"
      :loading-mode="objects.length ? 'mask' : 'skeleton'"
      :error="error"
      :empty="!loading && !error && !objects.length"
      empty-text="没有匹配的项目对象"
      full-height
      min-height="0"
      @retry="emit('refresh')"
    >
      <ElScrollbar class="project-assistant-object-browser__list">
        <button
          v-for="item in objects"
          :key="`${item.objectType}:${item.schemaName}:${item.objectName}`"
          type="button"
          :class="{ 'is-active': isSelected(item) }"
          @click="emit('select', item)"
        >
          <span class="project-assistant-object-browser__icon">
            <ArtSvgIcon :icon="getObjectIcon(item.objectType)" />
          </span>
          <span>
            <strong>{{ item.objectName }}</strong>
            <small :title="item.description || '暂无对象说明'">
              {{ item.description || '暂无对象说明' }}
            </small>
          </span>
        </button>
      </ElScrollbar>
    </ArtAsyncState>
  </aside>
</template>

<script setup lang="ts">
  import type { ProjectDatabaseObject, ProjectObjectType } from '@/types/supabase-ai-assistant'

  defineOptions({ name: 'ProjectAssistantObjectBrowser' })

  const props = defineProps<{
    focusMode: boolean
    schemas: string[]
    objects: ProjectDatabaseObject[]
    selectedObject: ProjectDatabaseObject | null
    filters: { schema: string; objectType: ProjectObjectType; keyword: string }
    loading: boolean
    loadSource: 'initial' | 'filter' | 'refresh' | null
    error: string | Error | null
  }>()

  const emit = defineEmits<{
    'toggle-focus': []
    refresh: []
    filter: []
    select: [item: ProjectDatabaseObject]
    'update:keyword': [value: string]
    'update:schema': [value: string]
    'update:object-type': [value: ProjectObjectType]
  }>()

  const objectTypeOptions: Array<{ label: string; value: ProjectObjectType }> = [
    { label: '全部对象', value: 'all' },
    { label: '数据表', value: 'table' },
    { label: '视图', value: 'view' },
    { label: '函数', value: 'function' },
    { label: '触发器', value: 'trigger' },
    { label: 'RLS 策略', value: 'policy' },
    { label: '索引', value: 'index' }
  ]

  function getObjectIcon(type: ProjectObjectType): string {
    return {
      table: 'ri:table-2',
      view: 'ri:layout-grid-line',
      materialized_view: 'ri:layout-grid-line',
      function: 'ri:function-line',
      trigger: 'ri:flashlight-line',
      policy: 'ri:shield-keyhole-line',
      index: 'ri:list-ordered-2',
      all: 'ri:database-2-line'
    }[type]
  }

  function isSelected(item: ProjectDatabaseObject): boolean {
    return (
      props.selectedObject?.schemaName === item.schemaName &&
      props.selectedObject?.objectName === item.objectName &&
      props.selectedObject?.objectType === item.objectType
    )
  }
</script>

<style scoped lang="scss">
  .project-assistant-object-browser {
    display: flex;
    flex-direction: column;
    min-width: 0;
    height: 100%;
    min-height: 0;
    overflow: hidden;

    &__title {
      display: flex;
      flex: 0 0 auto;
      align-items: center;
      justify-content: space-between;
      min-height: 62px;
      padding: 12px 15px;
      border-bottom: 1px solid var(--el-border-color-lighter);

      strong,
      small {
        display: block;
      }

      small {
        margin-top: 3px;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__actions {
      display: flex;
      flex: 0 0 auto;
      gap: 2px;
      align-items: center;

      .is-active {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }
    }

    &__refresh.is-refreshing &__refresh-icon {
      animation: project-assistant-browser-spin 0.75s linear infinite;
    }

    &__filters {
      display: flex;
      flex-direction: column;
      gap: 8px;
      padding: 12px;
      border-bottom: 1px solid var(--el-border-color-lighter);
    }

    &__search {
      width: 100% !important;

      --el-input-width: 100%;
    }

    &__selects {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 8px;

      .el-select {
        width: 100%;
        min-width: 0;
      }
    }

    &__state {
      flex: 1;
      min-height: 0;
    }

    &__list {
      height: 100%;
      padding: 7px;
    }

    &__list button {
      display: flex;
      gap: 10px;
      align-items: center;
      width: 100%;
      padding: 10px;
      text-align: left;
      cursor: pointer;
      background: transparent;
      border: 0;
      border-radius: var(--el-border-radius-base);
      transition:
        background-color 0.18s ease,
        transform 0.18s ease;

      &:hover {
        background: var(--el-color-primary-light-9);
        transform: translateX(2px);
      }

      &.is-active {
        background: linear-gradient(90deg, var(--el-color-primary-light-9), transparent);
        box-shadow: inset 3px 0 0 var(--el-color-primary);
      }

      &.is-active strong,
      .project-assistant-object-browser__icon {
        color: var(--el-color-primary);
      }

      > span:not(.project-assistant-object-browser__icon) {
        flex: 1;
        min-width: 0;
      }

      strong,
      small {
        display: block;
        width: 100%;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      small {
        margin-top: 2px;
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }
    }

    &__icon {
      display: grid;
      flex: 0 0 auto;
      place-items: center;
      width: 30px;
      height: 30px;
      background: var(--el-fill-color-light);
      border-radius: var(--el-border-radius-base);
    }
  }

  @keyframes project-assistant-browser-spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
