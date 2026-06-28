<template>
  <ArtDialog width="860px" ref="dialogRef" show-fullscreen-button>
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="rules"
      :span="width > 640 ? 12 : 24"
      :gutter="20"
      label-width="100px"
      :validate-on-rule-change="false"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import { formatMenuTitle } from '@/utils/router'
  import type { AppRouteRecord } from '@/types/router'
  import type { FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtForm from '@/components/core/forms/art-form/index.vue'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import { useWindowSize } from '@vueuse/core'

  import { addRMenu, editMenu } from '@/api/system-manage'
  import { useUserStore } from '@/store/modules/user'

  const { width } = useWindowSize()

  interface MenuFormData extends MenuFormSelectData {
    id?: string
    parentId?: string | null
    name: string
    title: string
    path: string
    component: string
    icon: string
    isEnable: boolean
    sort: number
    keepAlive: boolean
    isHide: boolean
    isHideTab: boolean
    link: string
    isIframe: boolean
    showBadge: boolean
    showTextBadge: string
    fixedTab: boolean
    activePath: string
    roles: string[]
    isFullPage: boolean
  }

  interface MenuFormSelectData {
    menuTree?: any
  }

  interface MenuDialogOpenData {
    row?: AppRouteRecord | any
    type?: 'folder' | 'menu' | 'button'
    parent?: AppRouteRecord | MenuFormData
    menuTree?: AppRouteRecord[]
  }

  interface Emits {
    (e: 'submit', data: MenuFormData): void
  }

  type MenuType = 'folder' | 'menu' | 'button'
  type MenuFormModel = MenuFormData & { type: MenuType }

  const emit = defineEmits<Emits>()
  const dialogRef = ref<ArtDialogExpose<MenuDialogOpenData>>()
  const formRef = ref()

  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)

  const createInitialForm = (): MenuFormModel => ({
    id: undefined,
    type: 'menu',
    parentId: '',
    name: '',
    path: '',
    title: '',
    component: '',
    icon: '',
    isEnable: true,
    sort: 1,
    keepAlive: true,
    isHide: false,
    isHideTab: false,
    link: '',
    isIframe: false,
    showBadge: false,
    showTextBadge: '',
    fixedTab: false,
    activePath: '',
    roles: [],
    isFullPage: false
  })

  const form = ref<MenuFormModel>(createInitialForm())

  const select = ref<MenuFormSelectData>({
    menuTree: []
  })

  const hasParentId = (parentId?: string | null): boolean => parentId != null && parentId !== ''

  const resolveFolderComponent = (parentId?: string | null): string =>
    hasParentId(parentId) ? '' : '/index/index'

  const syncComponentByType = (): void => {
    if (form.value.type === 'folder') {
      form.value.component = resolveFolderComponent(form.value.parentId)
      return
    }

    if (form.value.type === 'button') {
      form.value.path = ''
      form.value.component = ''
    }
  }

  const rules = computed<FormRules>(() => {
    const titleMessage = {
      button: '输入权限标识',
      menu: '输入菜单名称',
      folder: '输入目录名称'
    }
    return {
      name: [
        { required: true, message: '请输入名称', trigger: 'blur' },
        { min: 2, max: 50, message: '长度在 2 到 50 个字符', trigger: 'blur' }
      ],
      path:
        form.value.type === 'button'
          ? []
          : [{ required: true, message: '请输入路由地址', trigger: 'blur' }],
      title: [{ required: true, message: titleMessage[form.value.type], trigger: 'blur' }]
    }
  })

  /**
   * 表单项配置
   */
  const formItems = computed<FormItem[]>(() => {
    const baseItems: FormItem[] = [
      {
        label: '菜单类型',
        key: 'type',
        type: 'radioGroup',
        span: 24,
        description: '新建时可直接选择类型。按钮权限仍需挂在具体菜单下。',
        props: {
          optionType: 'button',
          validateEvent: false,
          onChange: handleMenuTypeChange,
          options: getDictMap.value.menuType ?? []
        }
      }
    ]
    // Switch 组件的 span：小屏幕 12，大屏幕 6
    const switchSpan = width.value < 640 ? 12 : 6
    if (['folder'].includes(form.value.type)) {
      return [
        ...baseItems,
        {
          label: '父级菜单',
          key: 'parentId',
          type: 'treeSelect',
          props: {
            clearable: true,
            filterable: true,
            placeholder: '不选择则创建为顶级菜单',
            checkStrictly: true,
            onChange: handleParentChange,
            data: select.value.menuTree,
            props: {
              label: (data: AppRouteRecord) => formatMenuTitle(data.meta?.title),
              value: 'id'
            }
          }
        },
        { label: '目录名称', key: 'title', type: 'input', props: { placeholder: '目录名称' } },
        {
          label: '路由地址',
          help: () =>
            [
              '一级菜单：以 / 开头的绝对路径（如 /dashboard）',
              '二级及以下：相对路径（如 console、user）'
            ].map((value) => h('p', value)),
          key: 'path',
          type: 'input',
          props: { placeholder: '如：/dashboard 或 console' }
        },
        { label: '权限标识', key: 'name', type: 'input', props: { placeholder: '如：User' } },
        {
          label: '组件路径',
          help: () =>
            ['一级父级菜单：填写 /index/index', '具体页面：填写组件路径（如 /system/user）'].map(
              (value) => h('p', value)
            ),
          key: 'component',
          type: 'input',
          props: {
            disabled: true,
            placeholder: '一级父级菜单固定为 /index/index'
          }
        },
        {
          label: '图标',
          help: '支持搜索并选择 Remix Icon 图标',
          key: 'icon',
          type: 'iconPicker',
          props: { placeholder: '请选择菜单图标' }
        },
        {
          label: '菜单排序',
          help: '值越小越靠前',
          key: 'sort',
          type: 'number',
          props: { min: 1, controlsPosition: 'right', style: { width: '100%' } }
        },
        {
          label: '文本徽章',
          key: 'showTextBadge',
          type: 'input',
          props: { placeholder: '如：New、Hot' }
        },
        { label: '是否启用', key: 'isEnable', type: 'switch', span: switchSpan },
        { label: '隐藏菜单', key: 'isHide', type: 'switch', span: switchSpan },
        { label: '显示徽章', key: 'showBadge', type: 'switch', span: switchSpan }
      ]
    }
    if (['menu'].includes(form.value.type)) {
      return [
        ...baseItems,
        {
          label: '父级菜单',
          key: 'parentId',
          type: 'treeSelect',
          props: {
            clearable: true,
            filterable: true,
            placeholder: '不选择则创建为顶级菜单',
            checkStrictly: true,
            data: select.value.menuTree,
            props: {
              label: (data: AppRouteRecord) => formatMenuTitle(data.meta?.title),
              value: 'id'
            }
          }
        },
        { label: '菜单名称', key: 'title', type: 'input', props: { placeholder: '菜单名称' } },
        {
          label: '路由地址',
          help: () =>
            [
              '一级菜单：以 / 开头的绝对路径（如 /dashboard）',
              '二级及以下：相对路径（如 console、user）'
            ].map((value) => h('p', value)),
          key: 'path',
          type: 'input',
          props: { placeholder: '如：/dashboard 或 console' }
        },
        { label: '权限标识', key: 'name', type: 'input', props: { placeholder: '如：User' } },
        {
          label: '组件路径',
          help: () =>
            ['一级父级菜单：填写 /index/index', '具体页面：填写组件路径（如 /system/user）'].map(
              (value) => h('p', value)
            ),
          key: 'component',
          type: 'input',
          props: { placeholder: '如：/system/user 或留空' }
        },
        {
          label: '图标',
          help: '支持搜索并选择 Remix Icon 图标',
          key: 'icon',
          type: 'iconPicker',
          props: { placeholder: '请选择菜单图标' }
        },
        {
          label: '菜单排序',
          help: '值越小越靠前',
          key: 'sort',
          type: 'number',
          props: { min: 1, controlsPosition: 'right', style: { width: '100%' } }
        },
        /*{
          label: '角色权限',
          help: () =>
            [
                '仅用于前端权限模式：配置角色标识',
              '后端权限模式：无需配置'
            ].map((value) => h('p', value)),
          key: 'roles',
          type: 'inputTag',
          props: { placeholder: '输入角色标识后按回车' }
        },*/
        {
          label: '外部链接',
          key: 'link',
          type: 'input',
          props: { placeholder: '如：https://www.example.com' }
        },
        {
          label: '文本徽章',
          key: 'showTextBadge',
          type: 'input',
          props: { placeholder: '如：New、Hot' }
        },
        {
          label: '激活路径',
          help: () =>
            [
              '用于详情页等隐藏菜单，指定高亮显示的父级菜单路径',
              '例如：用户详情页高亮显示"用户管理"菜单'
            ].map((value) => h('p', value)),
          key: 'activePath',
          type: 'input',
          props: { placeholder: '如：/system/user' }
        },
        { label: '是否启用', key: 'isEnable', type: 'switch', span: switchSpan },
        { label: '页面缓存', key: 'keepAlive', type: 'switch', span: switchSpan },
        { label: '隐藏菜单', key: 'isHide', type: 'switch', span: switchSpan },
        { label: '是否内嵌', key: 'isIframe', type: 'switch', span: switchSpan },
        { label: '显示徽章', key: 'showBadge', type: 'switch', span: switchSpan },
        { label: '固定标签', key: 'fixedTab', type: 'switch', span: switchSpan },
        { label: '标签隐藏', key: 'isHideTab', type: 'switch', span: switchSpan },
        { label: '全屏页面', key: 'isFullPage', type: 'switch', span: switchSpan }
      ]
    } else {
      return [
        ...baseItems,
        {
          label: '权限名称',
          key: 'title',
          type: 'input',
          props: { placeholder: '如：新增、编辑、删除' }
        },
        {
          label: '权限标识',
          key: 'name',
          type: 'input',
          props: { placeholder: '如：add、edit、delete' }
        },
        {
          label: '权限排序',
          help: '值越小越靠前',
          key: 'sort',
          type: 'number',
          props: { min: 1, controlsPosition: 'right', style: { width: '100%' } }
        }
      ]
    }
  })

  const handleMenuTypeChange = async (
    value: string | number | boolean | undefined
  ): Promise<void> => {
    if (value !== 'folder' && value !== 'menu' && value !== 'button') return

    syncComponentByType()
    await nextTick()
    formRef.value?.clearValidate()
  }

  const handleParentChange = (): void => {
    syncComponentByType()
  }

  /**
   * 重置表单数据
   */
  const handleResetFields = async (): Promise<void> => {
    await nextTick()
    formRef.value?.clearValidate()
  }

  /**
   * 加载表单数据（编辑模式）
   */
  const loadFormData = (
    row: AppRouteRecord | Record<string, never>,
    defaultType: MenuType
  ): void => {
    const {
      id,
      parentId = form.value.parentId,
      type,
      name,
      sort,
      path,
      component,
      meta: routeMeta = {}
    } = row
    const meta = routeMeta as NonNullable<AppRouteRecord['meta']>
    Object.assign(form.value, {
      id,
      parentId,
      type: type || defaultType,
      title: formatMenuTitle(meta?.title || ''),
      name,
      sort,
      path,
      component,
      icon: meta.icon ?? '',
      keepAlive: meta.keepAlive ?? false,
      isHide: meta.isHide ?? false,
      isHideTab: meta.isHideTab ?? false,
      isEnable: meta.isEnable ?? true,
      link: meta.link ?? '',
      isIframe: meta.isIframe ?? false,
      showBadge: meta.showBadge ?? false,
      showTextBadge: meta.showTextBadge ?? '',
      fixedTab: meta.fixedTab ?? false,
      activePath: meta.activePath ?? '',
      isFullPage: meta.isFullPage ?? false
    })
  }

  /**
   * 提交表单
   */
  const handleSubmit = async (): Promise<boolean> => {
    if (!formRef.value) return false

    try {
      await formRef.value.validate()
    } catch {
      ElMessage.error('表单校验失败，请检查输入')
      return false
    }

    try {
      const { id, parentId, path, component = '', name, type, sort, ...rest } = toRaw(form.value)
      const submitPath = type === 'button' ? '' : path
      const submitComponent =
        type === 'folder' ? resolveFolderComponent(parentId) : type === 'button' ? '' : component
      const params: AppRouteRecord = {
        parentId: parentId ?? null,
        path: submitPath,
        component: submitComponent,
        name,
        type,
        sort,
        meta: { ...rest }
      }
      if (id == null) {
        await addRMenu(params)
      } else {
        await editMenu({ ...params, id })
      }
      emit('submit', { ...form.value })
      return true
    } catch {
      return false
    }
  }

  const handleSetParent = (row: MenuFormData = {} as MenuFormData): void => {
    form.value.parentId = row.id ?? null
    select.value = {
      ...unref(select),
      menuTree: row.menuTree
    }
  }

  const initializeForm = async (data: MenuDialogOpenData = {}): Promise<void> => {
    Object.assign(form.value, createInitialForm())
    handleSetParent({
      ...(data.parent ?? {}),
      menuTree: data.menuTree ?? []
    } as MenuFormData)
    loadFormData(data.row ?? {}, data.type ?? 'menu')
    syncComponentByType()
    await handleResetFields()
  }

  const handleReset = async (): Promise<void> => {
    Object.assign(form.value, createInitialForm())
    select.value = { menuTree: [] }
    await handleResetFields()
  }

  const handleOpen = async (data: MenuDialogOpenData = {}): Promise<void> => {
    await initializeForm(data)
    await dialogRef.value?.handleOpen(data, {
      title: `${data.row?.id != null ? '编辑' : '新增'}${
        { folder: '目录', menu: '菜单', button: '权限' }[form.value.type]
      }`,
      dialogProps: {
        class: 'menu-dialog'
      },
      onConfirm: handleSubmit,
      onReset: () => {
        handleReset()
      }
    })
  }

  defineExpose({
    handleOpen,
    handleSubmit,
    handleReset,
    handleSetParent
  })
</script>
