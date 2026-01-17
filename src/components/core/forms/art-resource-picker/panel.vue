<template>
  <div class="resource-panel h-full flex flex-col">
    <div class="flex flex-col justify-between gap-y-1 md:flex-row">
      <div>
        <el-segmented
          v-model="segment.active"
          :options="segment.options"
          size="default"
          block
          @change="handleFileTypesChange"
        >
          <template #default="{ item }">
            <div class="flex items-center justify-center">
              <ArtSvgIcon
                :icon="item!.icon"
                class="mr-1 flex items-center justify-center text-[17px]"
              />
              <span>{{ typeof item.label === 'function' ? item.label() : item.label }}</span>
            </div>
          </template>
        </el-segmented>
      </div>
      <div class="flex justify-end">
        <el-input
          v-model="queryParams.originName"
          placeholder="搜索此分类下的资源"
          clearable
          class="w-full md:w-[180px]"
          @input="handleGetResourceList"
        >
          <template #suffix>
            <ArtSvgIcon icon="ri-search-line" />
          </template>
        </el-input>
      </div>
    </div>

    <div class="mt-2 min-h-0 flex-1">
      <el-scrollbar v-if="loading || resources.length">
        <div class="flex flex-wrap px-[2px] pt-[2px]">
          <el-space fill wrap :fill-ratio="9">
            <template v-for="resource in resources" :key="resource.id">
              <div
                class="resource-item"
                :class="{ active: isSelected(resource) }"
                @click="handleClick(resource)"
                @dblclick="handleDbClick(resource)"
                @contextmenu.prevent="(e: MouseEvent) => executeContextmenu(e, resource)"
              >
                <div class="resource-item__cover">
                  <template v-if="getCover(resource)">
                    <el-image :src="getCover(resource)" fit="cover" class="h-full w-full" lazy>
                      <template #error>
                        <div
                          class="relative m-[8px] h-[calc(100%-16px)] w-[calc(100%-16px)] flex items-center justify-center overflow-hidden"
                        >
                          <div
                            class="cursor-default overflow-hidden text-ellipsis whitespace-pre-wrap"
                          >
                            {{ resource.originName }}
                          </div>
                        </div>
                      </template>
                    </el-image>
                  </template>
                  <template v-else>
                    <div
                      class="relative m-[8px] h-[calc(100%-16px)] w-[calc(100%-16px)] flex items-center justify-center overflow-hidden"
                    >
                      <div class="cursor-default overflow-hidden text-ellipsis whitespace-pre-wrap">
                        {{ resource.originName }}
                      </div>
                    </div>
                  </template>
                </div>
                <div v-if="getCover(resource)" class="resource-item__name cursor-default">
                  {{ resource.originName }}
                </div>
                <div class="resource-item__selected">
                  <ArtSvgIcon icon="ri-checkbox-circle-fill" class="resource-item__selected-icon" />
                </div>
              </div>
            </template>
            <template v-if="resources.length === 0">
              <el-skeleton
                v-for="i in skeletonNum"
                :key="i"
                class="resource-skeleton relative"
                animated
              >
                <template #template>
                  <el-skeleton-item class="absolute !h-full w-full" variant="rect" />
                </template>
              </el-skeleton>
            </template>
            <div v-for="i in 10" :key="i" class="resource-placeholder" />
          </el-space>
        </div>
      </el-scrollbar>
      <div v-else class="h-full w-full flex flex-1 items-center justify-center">
        <el-empty />
      </div>

      <!-- 右键菜单组件 -->
      <ArtMenuRight
        ref="menuRef"
        :menu-items="menu.items"
        :menu-width="180"
        :submenu-width="140"
        :border-radius="10"
        @select="menu.handleSelect"
      />
    </div>

    <div class="resource-panel__footer flex justify-between pt-2">
      <div class="flex items-center">
        <el-tag
          v-if="props.multiple && props.limit"
          size="large"
          class="mr-2"
          :class="{
            'color-[var(--el-color-danger)]': props.limit && selectedKeys.length >= props.limit
          }"
        >
          {{ selectedKeys.length }}
          <template v-if="props.multiple && props.limit"> /{{ props.limit }} </template>
        </el-tag>
        <el-pagination
          v-model:current-page="queryParams.page"
          :disabled="loading"
          :total="queryParams.total"
          :page-size="queryParams.pageSize"
          background
          layout="prev, pager, next"
          :pager-count="5"
          @change="handleGetResourceList"
        />
      </div>
      <div v-if="props.showAction">
        <slot name="actions">
          <el-button @click="cancel"> 取消 </el-button>
          <el-button type="primary" @click="confirm"> 确认 </el-button>
        </slot>
      </div>
    </div>

    <div class="resource-dock">
      <template v-for="btn in resourceStore.getAllButton()" :key="btn.name">
        <div class="res-app-container">
          <div class="res-app">
            <el-tooltip
              :content="btn.label"
              placement="top"
              :show-after="300"
              :offset="10"
              :show-arrow="false"
            >
              <div>
                <input
                  type="file"
                  :name="btn.name"
                  class="hidden"
                  v-bind="btn?.uploadConfig ?? {}"
                  @change="handleFile($event, btn)"
                  @click.stop="() => {}"
                />
                <i class="res-app-icon">
                  <ArtSvgIcon :icon="btn.icon" />
                </i>
              </div>
            </el-tooltip>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>

<script setup lang="ts">
  import type { FileType, Resource, ResourcePanelProps } from './type.ts'
  import ArtMenuRight from '@/components/core/others/art-menu-right/index.vue'
  import type { MenuItemType } from '@/components/core/others/art-menu-right/index.vue'
  import { ElMessageBox } from 'element-plus'
  import { deleteResource, fetchGetResourceList } from '@/api/data-center'
  import useResourceStore from '@/store/modules/resource'
  import { pageInfoHandler } from '@utils/table/tableUtils'
  import { useImageViewer } from '@/hooks'

  defineOptions({ name: 'ArtSourcePanel' })

  const props = withDefaults(defineProps<ResourcePanelProps>(), {
    multiple: false,
    limit: undefined,
    showAction: true,
    pageSize: 30,
    dbClickConfirm: false
  })

  const emit = defineEmits<{
    (e: 'cancel'): void
    (e: 'confirm', value: any[]): void
  }>()

  const modelValue = defineModel<string | string[] | undefined>()

  const resourceStore = useResourceStore()

  const menuRef = ref<InstanceType<typeof ArtMenuRight>>()

  const segment = ref({
    active: props.defaultFileType ?? '',
    options: [
      { label: () => '所有', value: '', icon: 'ri:gallery-view-2', suffix: '' },
      {
        label: () => '图片',
        value: 'image',
        icon: 'ri:image-line',
        suffix: 'png,jpg,jpeg,gif,bmp,webp'
      },
      {
        label: () => '视频',
        value: 'video',
        icon: 'ri:folder-video-line',
        suffix: 'mp4,avi,wmv,mov,flv,mkv,webm'
      },
      {
        label: () => '音频',
        value: 'audio',
        icon: 'ri:file-music-line',
        suffix: 'mp3,wav,ogg,wma,aac,flac,ape,wavpack'
      },
      {
        label: () => '文档',
        value: 'document',
        icon: 'ri:file-text-line',
        suffix: 'doc,docx,xls,xlsx,ppt,pptx,pdf'
      }
    ] as FileType[]
  })

  /**
   * 查询参数
   */
  const queryParams = ref<Record<string, any>>({
    page: 1,
    pageSize: props.pageSize,
    total: 0,
    originName: '',
    suffix: ''
  })

  /**
   * 当前资源列表
   */
  const resources = ref<Resource[]>([])

  /**
   * 选中资源的key列表,该数据可用做直接返回
   */
  const selectedKeys = ref<Array<string | number>>([])

  const returnType = 'url'
  const selected = ref<Resource[]>([])

  const loading = ref(false)

  const menu = ref({
    resource: {} as Resource,
    items: computed((): MenuItemType[] => [
      !isSelected(menu.value.resource)
        ? {
            key: 'select',
            label: '选中',
            icon: 'ri-check-fill'
          }
        : {
            key: 'deselect',
            label: '取消选中',
            icon: 'ri-close-fill'
          },
      {
        key: 'singleSelect',
        label: '独立此项',
        icon: 'ri-checkbox-circle-line',
        showLine: true
      },
      {
        key: 'view',
        label: '查看',
        icon: 'ri-eye-line',
        disabled: !canPreview(menu.value.resource)
      },
      {
        key: 'delete',
        label: '删除',
        icon: 'ri-delete-bin-2-line'
      }
    ]),
    handleSelect(item: MenuItemType) {
      const { resource } = menu.value
      if (item.key === 'select') {
        select(resource)
      }
      if (item.key === 'deselect') {
        unSelect(resource)
      }
      if (item.key === 'singleSelect') {
        clearSelected()
        select(resource)
      }
      if (item.key === 'view') {
        useImageViewer([resource?.url ?? ''])
      }
      if (item.key === 'delete') {
        if (resource?.id) {
          handleDelete(resource.id)
        }
      }
    }
  })

  // 监听v-model变化，更新selectedKeys
  watch(
    () => modelValue.value,
    (newValue) => {
      selectedKeys.value = Array.isArray(newValue) ? newValue : newValue ? [newValue] : []
    },
    { deep: true }
  )

  // 监听selectedKeys变化，更新v-model
  watch(
    () => selectedKeys.value,
    (newKeys) => {
      const newValue = props.multiple ? newKeys : newKeys[0]
      // 同样，只有在modelValue真正改变时才更新
      if (modelValue.value && modelValue.value !== newValue) {
        modelValue.value = newValue as string | string[]
      }
    },
    { deep: true }
  )

  /**
   * 加载占位符数量
   */
  const skeletonNum = computed(() => {
    return loading.value ? queryParams.value.pageSize : 30
  })

  /**
   * 右键菜单
   */
  function executeContextmenu(e: MouseEvent, resource: Resource) {
    e.preventDefault()
    e.stopPropagation()
    menu.value.resource = resource
    nextTick(() => {
      menuRef.value?.show(e)
    })
  }

  /**
   * 获取封面
   * @param resource
   */
  function getCover(resource: Resource): string | undefined {
    if (resource?.mimeType?.startsWith('image')) {
      return resource.url
    }
    return undefined
  }

  /**
   * 判断是否能预览
   * @param resource
   */
  function canPreview(resource: Resource) {
    return resource?.mimeType?.startsWith('image')
  }

  /**
   * 判断是否被选中
   * @param resource
   */
  function isSelected(resource: Resource) {
    const key = resource[returnType] as string
    return selectedKeys.value.includes(key)
  }

  /**
   * 选中资源
   */
  function select(resource: Resource) {
    const key = resource[returnType] as string
    // 单选
    if (props.multiple) {
      // 判断是否上限
      if (props.limit && selectedKeys.value.length >= props.limit) {
        //return msg.warning(t('maxSelect', { limit: props.limit }))
      }
      selectedKeys.value.push(key)
      if (!selected.value.find((i) => i[returnType] === key)) {
        selected.value.push(resource)
      }
    } else {
      selected.value = [resource]
      selectedKeys.value = [key]
    }
  }

  /**
   * 取消选中
   */
  function unSelect(resource: Resource) {
    const key = resource[returnType] as string
    selectedKeys.value = selectedKeys.value.filter((i) => i !== key)
    selected.value = selected.value.filter((i) => i[returnType] !== key)
  }

  /**
   * 清空选中
   */
  function clearSelected() {
    selectedKeys.value = []
    selected.value = []
  }

  function cancel() {
    emit('cancel')
  }

  function confirm() {
    emit('confirm', selected.value)
  }

  /**
   * 删除选中
   */
  async function handleDelete(id: number): Promise<void> {
    ElMessageBox.confirm(`确定要删除这条数据吗？`, '系统提示', {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'error'
    }).then(async () => {
      const params = {
        id
      }
      try {
        loading.value = true
        await deleteResource(params)
        await handleGetResourceList()
      } finally {
        loading.value = false
      }
    })
  }

  /**
   * 处理点击资源事件
   */
  function handleClick(resource: Resource) {
    // eslint-disable-next-line @typescript-eslint/no-unused-expressions
    isSelected(resource) ? unSelect(resource) : select(resource)
  }

  /**
   * 处理双击资源事件
   */
  function handleDbClick(resource: Resource) {
    // 双击确认选中单个元素
    clearSelected()
    select(resource)
    confirm()
  }

  function handleFile(ev: Event, btn: Api.DataCenter.Resources.Button) {
    try {
      loading.value = true
      const target = ev.target
      if (!(target instanceof HTMLInputElement)) return

      const files = target.files

      if (!files || files.length === 0) return
      btn.upload?.(files.length === 1 ? files[0] : Array.from(files), {
        btn,
        handleGetResourceList
      })

      // ⚠️ 关键：清空 value，保证同一文件可重复选
      target.value = ''
    } finally {
      loading.value = false
    }
  }

  function getParentNode(e: PointerEvent | MouseEvent, labelName: string) {
    let node: any = e.target
    while (node.tagName !== labelName.toUpperCase()) {
      node = node?.parentNode
    }
    return node
  }

  const handleFileTypesChange = (value: any) => {
    const { options } = segment.value
    queryParams.value.suffix = options.find((i) => i.value === value)?.suffix as string
    handleGetResourceList()
  }

  const handleGetResourceList = async () => {
    try {
      loading.value = true
      resources.value = []
      const { suffix, originName, page: current, pageSize: size } = queryParams.value
      const { from, to } = pageInfoHandler({ current, size })
      const params = {
        originName,
        suffix,
        from,
        to
      }
      const { data } = await fetchGetResourceList(params)
      resources.value = data ?? []
    } finally {
      loading.value = false
    }
  }

  onMounted(async () => {
    await handleGetResourceList()

    // eslint-disable-next-line no-undef
    const apps = document.getElementsByClassName('res-app') as HTMLCollectionOf<HTMLDivElement>

    for (let i = 0; i < apps.length; i++) {
      const app = apps[i] as HTMLDivElement
      app.addEventListener('click', (e: MouseEvent) => {
        e.stopPropagation()
        const node = getParentNode(e, 'div')
        const fileInput = node.children[0]
        const btn = resourceStore
          .getAllButton()
          ?.find((item) => item.name === fileInput.getAttribute('name'))
        if (btn?.click) {
          btn?.click?.(btn, selected as any)
        }
        if (btn?.upload) {
          fileInput?.click?.()
        }
      })
      app?.parentElement?.addEventListener('mouseover', () => {
        const index = i
        app.className = 'res-app main-effect'

        if (index === 0) {
          if (apps[1]) {
            apps[1].className = 'res-app second-effect'
          }
          if (apps[2]) {
            apps[2].className = 'res-app third-effect'
          }
        } else if (index === apps.length - 1) {
          if (apps[index - 1]) {
            apps[index - 1].className = 'res-app second-effect'
          }
          if (apps[index - 2]) {
            apps[index - 2].className = 'res-app third-effect'
          }
        } else {
          if (apps[index - 1]) {
            apps[index - 1].className = 'res-app second-effect'
          }
          if (apps[index + 1]) {
            apps[index + 1].className = 'res-app second-effect'
          }

          if (index - 2 > -1 && apps[index - 2]) {
            apps[index - 2].className = 'res-app third-effect'
          }

          if (index + 2 < apps.length && apps[index + 2]) {
            apps[index + 2].className = 'res-app third-effect'
          }
        }
      })

      app?.parentElement?.addEventListener('mouseout', () => {
        for (const app of apps as any) {
          app.className = 'res-app'
        }
      })
    }
  })

  onUnmounted(() => {
    // 取消监听
    document.querySelectorAll('.ma-resource-dock .res-app').forEach((app) => {
      app.removeEventListener('mousemove', () => {})
      app.removeEventListener('mouseout', () => {})
      app.removeEventListener('click', () => {})
    })
  })
</script>

<style scoped lang="scss">
  @keyframes fadeIn {
    from {
      opacity: 0;
    }
    to {
      opacity: 1;
    }
  }

  .resource-panel {
    position: relative;
    --resource-item-size: 120px;

    .resource-dock {
      position: absolute;
      background-color: rgba(229, 231, 235, 1); /* bg-gray-2 */
      border-radius: 12px;
      padding: 4px;
      display: flex;
      align-items: center;
      justify-content: center;
      column-gap: 0.125rem;

      left: 50%;
      transform: translate(-50%);
      bottom: 0;

      /* dark-bg-dark-9 */
      :root.dark & {
        background-color: #1f2937;
      }

      .res-app-container {
        position: relative;
        height: 40px;
        display: flex;
        align-items: center;
      }

      /* 白色圆点 */
      .activate::after {
        content: '';
        display: block;
        position: absolute;

        width: 0;
        height: 0;

        border-width: 2px;
        border-style: solid;
        border-color: #ffffff;
        border-radius: 9999px;

        bottom: 2px;
        left: 50%;
        transform: translateX(-50%);
      }

      .res-app {
        width: 40px;
        height: 40px;

        display: flex;
        align-items: center;
        justify-content: center;

        border-radius: 10px;

        background-color: rgba(209, 213, 219, 1); /* bg-gray-3 */

        box-shadow:
          inset 0 4px 6px -1px rgba(0, 0, 0, 0.1),
          inset 0 2px 4px -2px rgba(0, 0, 0, 0.1);

        transition: all 0.3s;

        /* dark-bg-dark-4 dark-shadow-dark-9 */
        :root.dark & {
          background-color: #374151;
          box-shadow:
            inset 0 1px 2px rgba(0, 0, 0, 0.6),
            0 4px 6px rgba(0, 0, 0, 0.6);
        }
      }

      .res-app-icon {
        display: inline-flex;
        justify-content: center;
        align-items: center;
        width: 55px;
        height: 55px;
        font-size: 1.5rem !important;
        line-height: 2rem !important;

        color: #111827;
        cursor: pointer;

        transition: all 0.3s;

        :root.dark & {
          color: #e5e7eb;
        }
      }

      /* 主放大效果 */
      .main-effect {
        width: 80px;
        height: 80px;
        transform: translateY(-40px);
      }

      .main-effect .res-app-icon {
        width: 80px;
        height: 80px;
        font-size: 60px !important;
      }

      /* 次放大效果 */
      .second-effect {
        width: 60px;
        height: 60px;
        transform: translateY(-20px);
      }

      .second-effect .res-app-icon {
        width: 60px;
        height: 60px;
        font-size: 40px !important;
      }

      /* 最次放大效果 */
      .third-effect {
        width: 50px;
        height: 50px;
        transform: translateY(-10px);
      }

      .third-effect .res-app-icon {
        width: 50px;
        height: 50px;
        font-size: 30px !important;
      }
    }
  }

  .resource-item {
    position: relative;
    min-width: var(--resource-item-size);
    padding-bottom: 100%;
    overflow: hidden;

    border-radius: 4px;
    box-sizing: border-box;

    background-color: #f9fafb;
    animation: fadeIn 0.38s ease-out forwards;

    :root.dark & {
      background-color: #1f2937;
    }
  }

  .resource-item__cover {
    position: absolute;
    inset: 0;
  }

  .resource-item__name {
    position: absolute;
    bottom: 0;
    left: 0;
    right: 0;
    height: 24px;

    padding: 0 10px;

    font-size: 12px;
    line-height: 24px;

    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;

    background-color: rgba(156, 163, 175, 0.6);
    color: #ffffff;
  }

  .resource-item__selected {
    position: absolute;
    top: -30px;
    right: -30px;

    width: 40px;
    height: 40px;

    background-image: linear-gradient(to top right, transparent 50%, rgb(37, 99, 235) 50%);
  }

  .resource-item__selected-icon {
    position: absolute;
    top: 0;
    right: 0;
    padding: 2px;
    color: #ffffff;
    font-size: 22px;
  }

  .resource-item.active .resource-item__selected {
    top: 0;
    right: 0;
  }

  .resource-placeholder {
    min-width: var(--resource-item-size);
    height: 0;
    padding: 0;
    pointer-events: none;
  }

  .resource-skeleton {
    min-width: var(--resource-item-size);
    padding-bottom: 100%;
  }

  .resource-item:hover,
  .resource-item.active {
    box-shadow: 0 0 0 2px rgb(37, 99, 235);
  }
</style>
