<template>
  <div class="widget-page">
    <ElCard shadow="never" class="widget-section">
      <template #header>
        <div class="widget-section__header">
          <div>
            <h2>资源选择器</h2>
            <p>基于附件资源列表，支持单选、多选、分类筛选、搜索、分页、右键预览和确认回传。</p>
          </div>
          <ElTag effect="plain">ArtResourcePicker</ElTag>
        </div>
      </template>

      <ElSpace wrap>
        <ElButton type="primary" @click="singleVisible = true">打开单选</ElButton>
        <ElButton @click="multipleVisible = true">打开多选</ElButton>
      </ElSpace>

      <ElDescriptions :column="2" border class="mt-4">
        <ElDescriptionsItem label="单选 v-model">
          <span class="widget-section__value">{{ singleValueText }}</span>
        </ElDescriptionsItem>
        <ElDescriptionsItem label="多选 v-model">
          <span class="widget-section__value">{{ multipleValueText }}</span>
        </ElDescriptionsItem>
      </ElDescriptions>

      <ElTable :data="selectedRows" border class="mt-4">
        <ElTableColumn prop="originName" label="文件名" min-width="180">
          <template #default="{ row }">
            <span class="widget-section__value">{{ row.originName }}</span>
          </template>
        </ElTableColumn>
        <ElTableColumn prop="mimeType" label="MIME" min-width="160" />
        <ElTableColumn prop="sizeInfo" label="大小" width="100" />
        <ElTableColumn prop="url" label="URL" min-width="260">
          <template #default="{ row }">
            <span class="widget-section__value">{{ row.url }}</span>
          </template>
        </ElTableColumn>
      </ElTable>
    </ElCard>

    <ElCard shadow="never" class="widget-section">
      <template #header>
        <div class="widget-section__header">
          <div>
            <h2>API</h2>
            <p>覆盖 ArtResourcePicker / ResourcePanel 的 props 和事件。</p>
          </div>
        </div>
      </template>

      <ElTabs>
        <ElTabPane label="Props">
          <ElTable :data="propsRows" border>
            <ElTableColumn prop="name" label="名称" width="180" />
            <ElTableColumn prop="type" label="类型" width="220" />
            <ElTableColumn prop="defaultValue" label="默认值" width="140" />
            <ElTableColumn prop="desc" label="说明" />
          </ElTable>
        </ElTabPane>
        <ElTabPane label="Events / Resource">
          <ElTable :data="eventRows" border>
            <ElTableColumn prop="name" label="名称" width="180" />
            <ElTableColumn prop="payload" label="参数" width="240" />
            <ElTableColumn prop="desc" label="说明" />
          </ElTable>
        </ElTabPane>
      </ElTabs>
    </ElCard>

    <ArtResourcePicker
      v-model:visible="singleVisible"
      v-model="singleValue"
      :multiple="false"
      default-file-type="image"
      @confirm="handleSingleConfirm"
      @cancel="handleCancel"
    />

    <ArtResourcePicker
      v-model:visible="multipleVisible"
      v-model="multipleValue"
      multiple
      :limit="5"
      :page-size="24"
      default-file-type=""
      @confirm="handleMultipleConfirm"
      @cancel="handleCancel"
    />
  </div>
</template>

<script setup lang="ts">
  import ArtResourcePicker from '@/components/core/forms/art-resource-picker/index.vue'
  import type { Resource } from '@/components/core/forms/art-resource-picker/type'

  defineOptions({ name: 'ResourcePickerWidget' })

  interface ApiRow {
    name: string
    type?: string
    defaultValue?: string
    payload?: string
    desc: string
  }

  const singleVisible = ref(false)
  const multipleVisible = ref(false)
  const singleValue = ref<string>()
  const multipleValue = ref<string[]>([])
  const selectedRows = ref<Resource[]>([])
  const singleValueText = computed(() => singleValue.value ?? '-')
  const multipleValueText = computed(() =>
    multipleValue.value.length ? multipleValue.value.join(', ') : '[]'
  )

  const handleSingleConfirm = (rows: Resource[]) => {
    selectedRows.value = rows
    ElMessage.success(`已选择 ${rows.length} 个资源`)
  }

  const handleMultipleConfirm = (rows: Resource[]) => {
    selectedRows.value = rows
    ElMessage.success(`已选择 ${rows.length} 个资源`)
  }

  const handleCancel = () => {
    ElMessage.info('已取消选择')
  }

  const propsRows: ApiRow[] = [
    {
      name: 'v-model:visible',
      type: 'boolean',
      defaultValue: 'false',
      desc: '控制资源选择器弹窗显示。'
    },
    {
      name: 'v-model',
      type: 'string | string[]',
      defaultValue: '-',
      desc: '绑定选中的资源 URL。multiple=true 时为数组。'
    },
    { name: 'multiple', type: 'boolean', defaultValue: 'false', desc: '是否多选。' },
    { name: 'limit', type: 'number', defaultValue: '-', desc: '多选上限。' },
    { name: 'pageSize', type: 'number', defaultValue: '30', desc: '每页资源数量。' },
    {
      name: 'showAction',
      type: 'boolean',
      defaultValue: 'true',
      desc: '是否显示底部取消/确认按钮。'
    },
    {
      name: 'dbClickConfirm',
      type: 'boolean',
      defaultValue: 'false',
      desc: '双击资源是否立即确认。'
    },
    {
      name: 'defaultFileType',
      type: 'string',
      defaultValue: "''",
      desc: '默认分类：image/video/audio/document 或空字符串。'
    },
    {
      name: 'fileTypes',
      type: 'FileType[]',
      defaultValue: '内置分类',
      desc: '自定义文件分类配置。'
    }
  ]

  const eventRows: ApiRow[] = [
    { name: 'confirm', payload: 'Resource[]', desc: '点击确认或双击确认时返回选中的资源对象。' },
    { name: 'cancel', payload: '-', desc: '点击取消时触发。' },
    { name: 'Resource.id', payload: 'number', desc: '资源主键。' },
    { name: 'Resource.originName', payload: 'string', desc: '原始文件名。' },
    { name: 'Resource.mimeType', payload: 'string', desc: '资源 MIME 类型。' },
    {
      name: 'Resource.url',
      payload: 'string',
      desc: '资源访问地址，也是当前组件默认 v-model 值。'
    },
    { name: 'Resource.sizeInfo', payload: 'string', desc: '格式化后的文件大小。' }
  ]
</script>

<style scoped lang="scss">
  .widget-page {
    display: flex;
    flex-direction: column;
    gap: 16px;
    padding-bottom: 16px;
  }

  .widget-section {
    border-radius: 8px;

    :deep(.el-descriptions__content) {
      min-width: 0;
    }
  }

  .widget-section__header {
    display: flex;
    gap: 16px;
    align-items: flex-start;
    justify-content: space-between;

    h2 {
      margin: 0;
      font-size: 18px;
      font-weight: 600;
    }

    p {
      margin: 6px 0 0;
      color: var(--el-text-color-secondary);
    }
  }

  .widget-section__value {
    display: block;
    max-width: 100%;
    line-height: 22px;
    overflow-wrap: anywhere;
    white-space: normal;
  }
</style>
