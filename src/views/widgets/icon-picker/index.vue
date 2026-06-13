<template>
  <div class="widget-page">
    <ElCard shadow="never" class="widget-section">
      <template #header>
        <div class="widget-section__header">
          <div>
            <h2>图标选择器</h2>
            <p>支持 Remix Icon 搜索、懒加载、缓存、手动输入、清空和命令式打开。</p>
          </div>
          <ElTag effect="plain">ArtIconPicker</ElTag>
        </div>
      </template>

      <ElRow :gutter="16">
        <ElCol :xs="24" :md="12">
          <div class="demo-field">
            <span>基础选择</span>
            <ArtIconPicker v-model="iconValue" @select="handleSelect" @clear="handleClear" />
          </div>
        </ElCol>
        <ElCol :xs="24" :md="12">
          <div class="demo-field">
            <span>自定义配置</span>
            <ArtIconPicker
              ref="customPickerRef"
              v-model="customIconValue"
              title="选择菜单图标"
              placeholder="请输入或选择菜单图标"
              :page-size="80"
              :close-on-select="false"
              @change="handleChange"
            />
          </div>
        </ElCol>
      </ElRow>

      <ElSpace wrap>
        <ElButton type="primary" @click="openCustomPicker">handleOpen()</ElButton>
        <ElButton @click="reloadCustomPicker">reload()</ElButton>
        <ElButton @click="clearCustomPicker">handleClear()</ElButton>
      </ElSpace>

      <ElDescriptions :column="2" border class="mt-4">
        <ElDescriptionsItem label="基础值">{{ iconValue }}</ElDescriptionsItem>
        <ElDescriptionsItem label="自定义值">{{ customIconValue }}</ElDescriptionsItem>
      </ElDescriptions>
    </ElCard>

    <ElCard shadow="never" class="widget-section">
      <template #header>
        <div class="widget-section__header">
          <div>
            <h2>API</h2>
            <p>覆盖 ArtIconPicker 的 props、事件和 expose 方法。</p>
          </div>
        </div>
      </template>

      <ElTabs>
        <ElTabPane label="Props">
          <ElTable :data="propsRows" border>
            <ElTableColumn prop="name" label="名称" width="180" />
            <ElTableColumn prop="type" label="类型" width="180" />
            <ElTableColumn prop="defaultValue" label="默认值" width="240" />
            <ElTableColumn prop="desc" label="说明" />
          </ElTable>
        </ElTabPane>
        <ElTabPane label="Events / Expose">
          <ElTable :data="eventRows" border>
            <ElTableColumn prop="name" label="名称" width="180" />
            <ElTableColumn prop="payload" label="参数" width="200" />
            <ElTableColumn prop="desc" label="说明" />
          </ElTable>
        </ElTabPane>
      </ElTabs>
    </ElCard>
  </div>
</template>

<script setup lang="ts">
  import ArtIconPicker from '@/components/core/forms/art-icon-picker/index.vue'

  defineOptions({ name: 'IconPickerWidget' })

  interface ApiRow {
    name: string
    type?: string
    defaultValue?: string
    payload?: string
    desc: string
  }

  const iconValue = ref('ri:home-line')
  const customIconValue = ref('ri:settings-3-line')
  const customPickerRef = ref<InstanceType<typeof ArtIconPicker>>()

  const openCustomPicker = () => {
    void customPickerRef.value?.handleOpen()
  }

  const reloadCustomPicker = () => {
    void customPickerRef.value?.reload()
  }

  const clearCustomPicker = () => {
    customPickerRef.value?.handleClear()
  }

  const handleSelect = (value: string) => {
    ElMessage.success(`已选择：${value}`)
  }

  const handleChange = (value: string) => {
    console.info('ArtIconPicker change', value)
  }

  const handleClear = () => {
    ElMessage.info('已清空图标')
  }

  const propsRows: ApiRow[] = [
    {
      name: 'v-model',
      type: 'string',
      defaultValue: "''",
      desc: '图标值，推荐使用 ri:xxx-line 格式。'
    },
    { name: 'placeholder', type: 'string', defaultValue: '请选择图标', desc: '输入框占位文本。' },
    { name: 'title', type: 'string', defaultValue: '选择图标', desc: '弹窗标题。' },
    { name: 'prefix', type: 'string', defaultValue: 'ri', desc: 'Iconify 图标集合前缀。' },
    {
      name: 'collectionUrl',
      type: 'string',
      defaultValue: 'https://api.iconify.design/collection',
      desc: '图标集合接口地址。'
    },
    {
      name: 'pageSize',
      type: 'number',
      defaultValue: '140',
      desc: '每次渲染/滚动追加的图标数量。'
    },
    { name: 'clearable', type: 'boolean', defaultValue: 'true', desc: '输入框是否允许清空。' },
    { name: 'disabled', type: 'boolean', defaultValue: 'false', desc: '是否禁用组件。' },
    { name: 'readonly', type: 'boolean', defaultValue: 'false', desc: '是否禁止打开选择弹窗。' },
    {
      name: 'closeOnSelect',
      type: 'boolean',
      defaultValue: 'true',
      desc: '选择图标后是否自动关闭弹窗。'
    }
  ]

  const eventRows: ApiRow[] = [
    { name: 'change', payload: 'string', desc: '输入或选择图标值变化时触发。' },
    { name: 'select', payload: 'string', desc: '点击图标项时触发。' },
    { name: 'clear', payload: '-', desc: '清空时触发。' },
    { name: 'handleOpen()', payload: 'Promise<void>', desc: 'expose 方法，打开图标选择弹窗。' },
    { name: 'handleClear()', payload: 'void', desc: 'expose 方法，清空当前值。' },
    { name: 'reload()', payload: 'Promise<void>', desc: 'expose 方法，强制重新加载图标集合。' }
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

  .demo-field {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-bottom: 16px;

    > span {
      font-size: 13px;
      font-weight: 500;
      color: var(--el-text-color-secondary);
    }
  }
</style>
