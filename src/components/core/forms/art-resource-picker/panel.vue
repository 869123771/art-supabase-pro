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

    <button
      v-if="props.showPasteUpload"
      type="button"
      class="resource-paste-zone"
      :class="{ 'is-uploading': uploading }"
      :disabled="uploading"
      aria-label="粘贴剪贴板图片并上传"
      @paste="handlePasteImage"
    >
      <span class="resource-paste-zone__icon" aria-hidden="true">
        <ArtSvgIcon :icon="uploading ? 'ri-loader-4-line' : 'ri-clipboard-line'" />
      </span>
      <span class="resource-paste-zone__content">
        <strong>{{ uploading ? '图片上传中' : '粘贴图片上传' }}</strong>
        <span>
          {{
            uploading
              ? '正在保存剪贴板图片，请稍候'
              : '点击此框后按 Ctrl+V（macOS 为 ⌘V），无需先下载图片'
          }}
        </span>
      </span>
      <kbd v-if="!uploading" class="resource-paste-zone__shortcut">Ctrl V</kbd>
    </button>

    <div class="mt-2 min-h-0 flex-1">
      <component :is="resourceListContainer" v-if="loading || resources.length">
        <div class="flex flex-wrap px-[2px] pt-[2px]">
          <el-space fill wrap :fill-ratio="9">
            <template v-for="resource in resources" :key="resource.id">
              <button
                type="button"
                class="resource-item"
                :class="{ active: isSelected(resource) }"
                :aria-pressed="isSelected(resource)"
                :aria-label="`选择资源 ${resource.originName}`"
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
              </button>
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
      </component>
      <div v-else class="h-full w-full flex flex-1 items-center justify-center">
        <ArtEmptyState
          title="暂无可用资源"
          description="可以切换资源类型，或尝试更换搜索关键词"
          size="compact"
          :visual-size="76"
        />
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
      <template v-for="(btn, index) in resourceStore.getAllButton()" :key="btn.name">
        <div class="res-app-container">
          <input
            :ref="(element) => setFileInputRef(btn.name, element)"
            type="file"
            :name="btn.name"
            class="hidden"
            v-bind="btn.uploadConfig ?? {}"
            @change="handleFile($event, btn)"
          />
          <el-tooltip
            :content="btn.label"
            placement="top"
            :show-after="300"
            :offset="10"
            :show-arrow="false"
          >
            <button
              type="button"
              class="res-app"
              :class="getDockEffectClass(index)"
              :disabled="uploading"
              :aria-label="btn.label"
              @click="handleUploadButtonClick(btn)"
              @mouseenter="hoveredDockIndex = index"
              @mouseleave="hoveredDockIndex = undefined"
            >
              <span class="res-app-icon" aria-hidden="true">
                <ArtSvgIcon :icon="btn.icon" />
              </span>
            </button>
          </el-tooltip>
        </div>
      </template>
    </div>
    <MasterDataDeleteGuard ref="deleteGuardRef" @cleared="handleGetResourceList" />
  </div>
</template>

<script setup lang="ts">
  import ArtEmptyState from '@/components/core/feedback/art-empty-state/index.vue'
  import type { FileType, Resource, ResourcePanelProps } from './type.ts'
  import ArtMenuRight from '@/components/core/others/art-menu-right/index.vue'
  import type { MenuItemType } from '@/components/core/others/art-menu-right/index.vue'
  import { ElMessage, ElMessageBox, ElScrollbar } from 'element-plus'
  import { deleteResource, fetchGetResourceList, renameResource } from '@/api/data-center'
  import useResourceStore from '@/store/modules/resource'
  import { pageInfoHandler } from '@utils/table/tableUtils'
  import { openFilePreview } from '@/hooks/core/useFilePreview'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import dayjs from 'dayjs'
  import MasterDataDeleteGuard, {
    type MasterDataDeleteGuardOpenOptions
  } from '@/components/business/master-data-delete-guard/index.vue'

  defineOptions({ name: 'ArtResourcePanel' })

  const props = withDefaults(defineProps<ResourcePanelProps>(), {
    multiple: false,
    limit: undefined,
    internalScroll: true,
    showAction: true,
    showCopyActions: false,
    showPasteUpload: false,
    showRenameAction: false,
    pageSize: 30,
    dbClickConfirm: false
  })

  const emit = defineEmits<{
    (e: 'cancel'): void
    (e: 'confirm', value: Resource[]): void
  }>()

  const modelValue = defineModel<string | string[] | undefined>()

  const resourceStore = useResourceStore()
  const { promptText } = useArtFeedback()
  interface MasterDataDeleteGuardExpose {
    inspect: (options: MasterDataDeleteGuardOpenOptions) => Promise<boolean>
  }
  const deleteGuardRef = ref<MasterDataDeleteGuardExpose>()

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
  interface ResourceQueryParams {
    page: number
    pageSize: number
    total: number
    originName: string
    suffix: string
  }

  const queryParams = ref<ResourceQueryParams>({
    page: 1,
    pageSize: props.pageSize,
    total: 0,
    originName: '',
    suffix: ''
  })

  const fileInputRefs = new Map<string, HTMLInputElement>()
  const hoveredDockIndex = ref<number>()

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
  const uploading = ref(false)
  const resourceListContainer = computed(() => (props.internalScroll ? ElScrollbar : 'div'))

  const menu = ref({
    resource: {} as Resource,
    items: computed((): MenuItemType[] => {
      const resource = menu.value.resource
      const copyItems: MenuItemType[] = []

      if (props.showCopyActions) {
        copyItems.push({
          key: 'copyLink',
          label: '复制链接',
          icon: 'ri-link',
          disabled: !resource.url
        })
        if (isImageResource(resource)) {
          copyItems.push({
            key: 'copyImage',
            label: '复制图片',
            icon: 'ri-image-line'
          })
        }
        if (!props.showRenameAction) {
          const lastCopyItem = copyItems.at(-1)
          if (lastCopyItem) lastCopyItem.showLine = true
        }
      }

      return [
        !isSelected(resource)
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
          disabled: !canPreview(resource)
        },
        ...copyItems,
        ...(props.showRenameAction
          ? [
              {
                key: 'rename',
                label: '重命名',
                icon: 'ri-edit-line',
                showLine: true,
                disabled: !resource.id
              }
            ]
          : []),
        {
          key: 'delete',
          label: '删除',
          icon: 'ri-delete-bin-2-line'
        }
      ]
    }),
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
        const result = openFilePreview({
          name: resource.originName,
          url: resource.url,
          fileType: resource.suffix
        })
        if (result === 'blocked') ElMessage.warning('浏览器阻止了新页签，请允许本站打开弹出式窗口')
      }
      if (item.key === 'copyLink') {
        void handleCopyLink(resource)
      }
      if (item.key === 'copyImage') {
        void handleCopyImage(resource)
      }
      if (item.key === 'rename') {
        void handleRename(resource)
      }
      if (item.key === 'delete') {
        if (resource?.id) {
          void handleDelete(resource)
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
    { deep: true, immediate: true }
  )

  // 监听selectedKeys变化，更新v-model
  watch(
    () => selectedKeys.value,
    (newKeys) => {
      const newValue = props.multiple ? [...newKeys] : newKeys[0]
      if (props.multiple) {
        const currentValue = Array.isArray(modelValue.value)
          ? modelValue.value
          : modelValue.value
            ? [modelValue.value]
            : []
        const isSame =
          currentValue.length === newKeys.length &&
          currentValue.every((key, index) => key === newKeys[index])
        if (!isSame) {
          modelValue.value = newValue as string[]
        }
        return
      }

      if (modelValue.value !== newValue) {
        modelValue.value = newValue as string | undefined
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
    return Boolean(resource?.url)
  }

  function isImageResource(resource: Resource): boolean {
    if (resource.mimeType?.toLowerCase().startsWith('image/')) return true
    return /^(bmp|gif|jpe?g|png|webp)$/i.test(resource.suffix?.trim() ?? '')
  }

  async function handleCopyLink(resource: Resource): Promise<void> {
    const url = resource.url?.trim()
    if (!url) {
      ElMessage.warning('当前资源没有可复制的访问链接')
      return
    }

    try {
      await copyPlainText(url)
      ElMessage.success('资源链接已复制，可粘贴到浏览器或消息中')
    } catch {
      ElMessage.error('链接复制失败，请检查浏览器剪贴板权限后重试')
    }
  }

  async function copyPlainText(value: string): Promise<void> {
    if (window.isSecureContext && navigator.clipboard?.writeText) {
      try {
        await navigator.clipboard.writeText(value)
        return
      } catch {
        // 浏览器拒绝现代剪贴板权限时，继续使用兼容复制通道。
      }
    }

    const textarea = document.createElement('textarea')
    textarea.value = value
    textarea.setAttribute('readonly', '')
    textarea.style.position = 'fixed'
    textarea.style.top = '-9999px'
    textarea.style.opacity = '0'
    document.body.appendChild(textarea)
    textarea.focus()
    textarea.select()
    const copied = document.execCommand('copy')
    textarea.remove()
    if (!copied) throw new Error('CLIPBOARD_COPY_FAILED')
  }

  async function handleCopyImage(resource: Resource): Promise<void> {
    const url = resource.url?.trim()
    if (!url || !isImageResource(resource)) {
      ElMessage.warning('当前资源不是可复制的图片')
      return
    }
    if (
      !window.isSecureContext ||
      !navigator.clipboard?.write ||
      typeof ClipboardItem === 'undefined'
    ) {
      ElMessage.warning('当前浏览器不支持直接复制图片，请改用“复制链接”')
      return
    }

    try {
      const pngBlob = fetchClipboardImage(url)
      await navigator.clipboard.write([new ClipboardItem({ 'image/png': pngBlob })])
      ElMessage.success('图片已复制，可直接粘贴到聊天或文档中')
    } catch (error: unknown) {
      if (
        error instanceof DOMException &&
        (error.name === 'NotAllowedError' || error.name === 'SecurityError')
      ) {
        ElMessage.error('浏览器未允许复制图片，请开启本站剪贴板权限后重试')
        return
      }
      ElMessage.error('图片复制失败，请确认资源可访问，或改用“复制链接”')
    }
  }

  async function fetchClipboardImage(url: string): Promise<Blob> {
    const response = await fetch(url, { credentials: 'omit', mode: 'cors' })
    if (!response.ok) throw new Error('RESOURCE_FETCH_FAILED')

    const source = await response.blob()
    if (!source.type.startsWith('image/')) throw new Error('RESOURCE_NOT_IMAGE')
    if (source.type === 'image/png') return source

    const bitmap = await createImageBitmap(source)
    try {
      const canvas = document.createElement('canvas')
      canvas.width = bitmap.width
      canvas.height = bitmap.height
      const context = canvas.getContext('2d')
      if (!context) throw new Error('CANVAS_CONTEXT_UNAVAILABLE')
      context.drawImage(bitmap, 0, 0)
      return await new Promise<Blob>((resolve, reject) => {
        canvas.toBlob(
          (blob) => (blob ? resolve(blob) : reject(new Error('IMAGE_CONVERSION_FAILED'))),
          'image/png'
        )
      })
    } finally {
      bitmap.close()
    }
  }

  function getResourceExtension(resource: Resource): string {
    const suffix = resource.suffix?.trim().replace(/^\./, '') ?? ''
    return suffix ? `.${suffix}` : ''
  }

  function getResourceBaseName(resource: Resource, extension: string): string {
    const currentName = resource.originName?.trim() ?? ''
    return extension && currentName.toLowerCase().endsWith(extension.toLowerCase())
      ? currentName.slice(0, -extension.length)
      : currentName
  }

  async function handleRename(resource: Resource): Promise<void> {
    if (!resource.id) return

    const extension = getResourceExtension(resource)
    const currentBaseName = getResourceBaseName(resource, extension)
    try {
      const baseName = await promptText(
        extension ? `请输入新的文件名，扩展名 ${extension} 将自动保留` : '请输入新的文件名',
        '重命名附件',
        {
          initialValue: currentBaseName,
          placeholder: '请输入文件名',
          emptyMessage: '文件名不能为空',
          maxLength: Math.max(1, 200 - extension.length),
          maxLengthMessage: '完整文件名不能超过 200 个字符',
          confirmButtonText: '保存名称',
          type: 'info'
        }
      )
      const originName = `${baseName}${extension}`
      if (originName === resource.originName) return

      loading.value = true
      await renameResource({ id: String(resource.id), originName })
      resource.originName = originName
      await handleGetResourceList()
      ElMessage.success('附件名称已更新，原访问链接保持不变')
    } catch (error: unknown) {
      if (error !== 'cancel' && error !== 'close') {
        ElMessage.error(getFriendlySupabaseErrorMessage(error, '附件重命名失败，请稍后重试'))
      }
    } finally {
      loading.value = false
    }
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
    if (!key || selectedKeys.value.includes(key)) return

    if (props.multiple) {
      if (props.limit && selectedKeys.value.length >= props.limit) {
        ElMessage.warning(`最多只能选择 ${props.limit} 个资源`)
        return
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
  async function handleDelete(resource: Resource): Promise<void> {
    if (!resource.id) return
    const blocked = await deleteGuardRef.value?.inspect({
      resourceType: 'attachment',
      resourceLabel: '附件资源',
      resources: [{ id: String(resource.id), label: resource.originName || '未命名附件' }]
    })
    if (blocked) return

    ElMessageBox.confirm(`确定要删除“${resource.originName || '未命名附件'}”吗？`, '删除附件', {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'warning',
      confirmButtonClass: 'el-button--danger'
    }).then(async () => {
      const params = {
        id: resource.id
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
    if (!props.dbClickConfirm) return
    // 双击确认选中单个元素
    clearSelected()
    select(resource)
    confirm()
  }

  function setFileInputRef(name: string, element: unknown): void {
    if (element instanceof HTMLInputElement) {
      fileInputRefs.set(name, element)
      return
    }
    fileInputRefs.delete(name)
  }

  function handleUploadButtonClick(btn: Api.DataCenter.Resources.Button): void {
    if (uploading.value) return
    if (btn.click) {
      btn.click(btn, selected.value)
      return
    }
    if (btn.upload) fileInputRefs.get(btn.name)?.click()
  }

  function getDockEffectClass(index: number): string | undefined {
    if (hoveredDockIndex.value === undefined) return undefined
    const distance = Math.abs(index - hoveredDockIndex.value)
    if (distance === 0) return 'main-effect'
    if (distance === 1) return 'second-effect'
    if (distance === 2) return 'third-effect'
    return undefined
  }

  async function uploadFiles(
    files: File | File[],
    btn: Api.DataCenter.Resources.Button
  ): Promise<void> {
    if (!btn.upload || uploading.value) return
    uploading.value = true
    try {
      await btn.upload(files, {
        btn,
        handleGetResourceList
      })
    } finally {
      uploading.value = false
    }
  }

  async function handleFile(ev: Event, btn: Api.DataCenter.Resources.Button): Promise<void> {
    const target = ev.target
    if (!(target instanceof HTMLInputElement)) return
    const files = target.files
    target.value = ''
    if (!files?.length) return

    try {
      await uploadFiles(files.length === 1 ? files[0] : Array.from(files), btn)
      ElMessage.success(files.length === 1 ? '文件上传成功' : `${files.length} 个文件上传成功`)
    } catch (error: unknown) {
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '文件上传失败，请检查文件后重试'))
    }
  }

  function getClipboardImageExtension(mimeType: string): string {
    const knownExtensions: Record<string, string> = {
      'image/jpeg': 'jpg',
      'image/svg+xml': 'svg',
      'image/x-icon': 'ico'
    }
    return knownExtensions[mimeType] ?? mimeType.split('/')[1]?.split('+')[0] ?? 'png'
  }

  function createClipboardImageFile(file: File, index: number, total: number): File {
    const timestamp = dayjs().format('YYYYMMDD_HHmmss')
    const sequence = total > 1 ? `_${index + 1}` : ''
    const extension = getClipboardImageExtension(file.type)
    return new File([file], `粘贴图片_${timestamp}${sequence}.${extension}`, {
      type: file.type,
      lastModified: Date.now()
    })
  }

  async function handlePasteImage(event: ClipboardEvent): Promise<void> {
    if (uploading.value) return
    const clipboardItems = Array.from(event.clipboardData?.items ?? [])
    const sourceFiles = clipboardItems
      .filter((item) => item.kind === 'file' && item.type.startsWith('image/'))
      .map((item) => item.getAsFile())
      .filter((file): file is File => file !== null)

    if (!sourceFiles.length) {
      ElMessage.warning('剪贴板中没有可上传的图片，请先在其他位置右键复制图片')
      return
    }

    event.preventDefault()
    const imageButton = resourceStore.getButton('local-image-upload')
    if (!imageButton?.upload) {
      ElMessage.error('图片上传入口暂不可用，请刷新页面后重试')
      return
    }

    const files = sourceFiles.map((file, index) =>
      createClipboardImageFile(file, index, sourceFiles.length)
    )
    try {
      await uploadFiles(files.length === 1 ? files[0] : files, imageButton)
      ElMessage.success(
        files.length === 1 ? '剪贴板图片上传成功' : `${files.length} 张图片上传成功`
      )
    } catch (error: unknown) {
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '剪贴板图片上传失败，请稍后重试'))
    }
  }

  const handleFileTypesChange = (value: string | number | boolean) => {
    const { options } = segment.value
    queryParams.value.suffix = options.find((i) => i.value === String(value))?.suffix ?? ''
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

  onMounted(handleGetResourceList)
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

    .resource-paste-zone {
      display: flex;
      gap: 12px;
      align-items: center;
      width: 100%;
      min-height: 58px;
      padding: 10px 14px;
      margin-top: 10px;
      color: var(--art-gray-800);
      text-align: left;
      cursor: pointer;
      background-color: color-mix(in srgb, var(--theme-color) 5%, var(--default-box-color));
      border: 1px dashed color-mix(in srgb, var(--theme-color) 42%, var(--default-border));
      border-radius: var(--art-control-radius);
      transition:
        color 180ms ease,
        background-color 180ms ease,
        border-color 180ms ease,
        box-shadow 180ms ease;

      &:hover,
      &:focus-visible {
        color: var(--theme-color);
        background-color: color-mix(in srgb, var(--theme-color) 9%, var(--default-box-color));
        border-color: var(--theme-color);
      }

      &:focus-visible {
        outline: none;
        box-shadow: 0 0 0 3px color-mix(in srgb, var(--theme-color) 18%, transparent);
      }

      &:disabled {
        cursor: wait;
        opacity: 0.8;
      }

      &__icon {
        display: inline-flex;
        flex: 0 0 34px;
        align-items: center;
        justify-content: center;
        width: 34px;
        height: 34px;
        font-size: 20px;
        color: var(--theme-color);
        background-color: color-mix(in srgb, var(--theme-color) 12%, transparent);
        border-radius: var(--el-border-radius-base);
      }

      &__content {
        display: flex;
        flex: 1;
        flex-direction: column;
        gap: 2px;
        min-width: 0;

        strong {
          font-size: 14px;
          line-height: 20px;
          color: inherit;
        }

        span {
          overflow: hidden;
          font-size: 12px;
          line-height: 18px;
          text-overflow: ellipsis;
          color: var(--art-gray-600);
          white-space: nowrap;
        }
      }

      &__shortcut {
        flex: none;
        padding: 3px 7px;
        font-family: inherit;
        font-size: 11px;
        line-height: 16px;
        color: var(--art-gray-700);
        background-color: var(--default-box-color);
        border: 1px solid var(--default-border);
        border-radius: var(--el-border-radius-small);
        box-shadow: inset 0 -1px 0 color-mix(in srgb, var(--art-gray-900) 12%, transparent);
      }

      &.is-uploading &__icon {
        animation: resource-paste-spin 900ms linear infinite;
      }
    }

    .resource-dock {
      position: absolute;
      bottom: 0;
      left: 50%;
      display: flex;
      column-gap: 0.125rem;
      align-items: center;
      justify-content: center;
      padding: 4px;
      background-color: rgb(229 231 235 / 100%); /* bg-gray-2 */
      border-radius: 12px;
      transform: translate(-50%);

      /* dark-bg-dark-9 */
      :root.dark & {
        background-color: #1f2937;
      }

      .res-app-container {
        position: relative;
        display: flex;
        align-items: center;
        height: 40px;
      }

      /* 白色圆点 */
      .activate::after {
        position: absolute;
        bottom: 2px;
        left: 50%;
        display: block;
        width: 0;
        height: 0;
        content: '';
        border-color: #fff;
        border-style: solid;
        border-width: 2px;
        border-radius: 9999px;
        transform: translateX(-50%);
      }

      .res-app {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 40px;
        height: 40px;
        background-color: rgb(209 213 219 / 100%); /* bg-gray-3 */
        border-radius: 10px;
        box-shadow:
          inset 0 4px 6px -1px rgb(0 0 0 / 10%),
          inset 0 2px 4px -2px rgb(0 0 0 / 10%);
        transition:
          background-color 0.3s,
          box-shadow 0.3s,
          transform 0.3s;

        &:disabled {
          cursor: wait;
          opacity: 0.62;
        }

        /* dark-bg-dark-4 dark-shadow-dark-9 */
        :root.dark & {
          background-color: #374151;
          box-shadow:
            inset 0 1px 2px rgb(0 0 0 / 60%),
            0 4px 6px rgb(0 0 0 / 60%);
        }
      }

      .res-app-icon {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 55px;
        height: 55px;
        font-size: 1.5rem !important;
        line-height: 2rem !important;
        color: #111827;
        cursor: pointer;
        transition:
          color 0.3s,
          background-color 0.3s;

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
    box-sizing: border-box;
    min-width: var(--resource-item-size);
    padding-bottom: 100%;
    overflow: hidden;
    background-color: #f9fafb;
    border-radius: 4px;
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
    right: 0;
    bottom: 0;
    left: 0;
    height: 24px;
    padding: 0 10px;
    overflow: hidden;
    text-overflow: ellipsis;
    font-size: 12px;
    line-height: 24px;
    color: #fff;
    white-space: nowrap;
    background-color: rgb(156 163 175 / 60%);
  }

  .resource-item__selected {
    position: absolute;
    top: -30px;
    right: -30px;
    width: 40px;
    height: 40px;
    background-image: linear-gradient(to top right, transparent 50%, var(--main-color) 50%);
  }

  .resource-item__selected-icon {
    position: absolute;
    top: 0;
    right: 0;
    padding: 2px;
    font-size: 22px;
    color: #fff;
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
    box-shadow: 0 0 0 2px var(--main-color);
  }

  @keyframes resource-paste-spin {
    to {
      transform: rotate(360deg);
    }
  }

  @media (width <= 640px) {
    .resource-panel {
      .resource-paste-zone {
        align-items: flex-start;

        &__content span {
          white-space: normal;
        }

        &__shortcut {
          display: none;
        }
      }
    }
  }
</style>
