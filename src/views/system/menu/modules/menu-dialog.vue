<template>
  <ElDialog
    :title="dialogTitle"
    :model-value="visible"
    @update:model-value="handleCancel"
    width="860px"
    align-center
    class="menu-dialog"
    destroy-on-close
  >
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="rules"
      :span="width > 640 ? 12 : 24"
      :gutter="20"
      label-width="100px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #type>
        <ElRadioGroup v-model="form.type" :disabled="disableMenuType">
          <ElRadioButton value="folder" label="menu">目录</ElRadioButton>
          <ElRadioButton value="menu" label="menu">菜单</ElRadioButton>
          <ElRadioButton value="button" label="button">按钮</ElRadioButton>
        </ElRadioGroup>
      </template>
    </ArtForm>

    <template #footer>
      <span class="dialog-footer">
        <ElButton @click="handleCancel">取 消</ElButton>
        <ElButton type="primary" @click="handleSubmit" :loading="loading">确 定</ElButton>
      </span>
    </template>
  </ElDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import { ElIcon, ElTooltip } from 'element-plus'
  import { QuestionFilled } from '@element-plus/icons-vue'
  import { formatMenuTitle } from '@/utils/router'
  import type { AppRouteRecord } from '@/types/router'
  import type { FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtForm from '@/components/core/forms/art-form/index.vue'
  import { useWindowSize } from '@vueuse/core'

  import { isEmpty } from 'lodash-es'
  import { addRMenu, editMenu } from '@/api/system-manage'

  const { width } = useWindowSize()

  /**
   * 创建带 tooltip 的表单标签
   * @param label 标签文本
   * @param tooltip 提示文本
   * @returns 渲染函数
   */
  const createLabelTooltip = (label: string, tooltip: string | (() => any)) => {
    return () =>
      h('span', { class: 'flex items-center' }, [
        h('span', label),
        h(
          ElTooltip,
          { placement: 'top' },
          {
            // 👇 tooltip 内容插槽
            content: () =>
              typeof tooltip === 'function'
                ? tooltip()
                : h('span', { class: 'whitespace-pre-line' }, tooltip),

            // 👇 触发器
            default: () => h(ElIcon, { class: 'ml-0.5 cursor-help' }, () => h(QuestionFilled))
          }
        )
      ])
  }

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

  interface Props {
    visible: boolean
    editData?: AppRouteRecord | any
    type?: 'folder' | 'menu' | 'button'
    lockType?: boolean
  }

  interface Emits {
    (e: 'update:visible', value: boolean): void
    (e: 'submit', data: MenuFormData): void
  }

  const props = withDefaults(defineProps<Props>(), {
    visible: false,
    type: 'menu',
    lockType: false,
    editData: {}
  })

  const emit = defineEmits<Emits>()

  const formRef = ref()

  const loading = ref(false)

  const form = reactive<MenuFormData & { type: 'folder' | 'menu' | 'button' }>({
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

  const select = ref<MenuFormSelectData>({
    menuTree: []
  })

  const isEdit = computed(() => form.id)

  const rules = computed<FormRules>(() => {
    const titleMessage = {
      button: '输入权限标识',
      menu: '输入菜单名称',
      folder: '输入目录名称'
    }
    return {
      name: [
        { required: true, message: '请输入名称', trigger: 'blur' },
        { min: 2, max: 20, message: '长度在 2 到 20 个字符', trigger: 'blur' }
      ],
      path: [{ required: true, message: '请输入路由地址', trigger: 'blur' }],
      title: [{ required: true, message: titleMessage[form.type], trigger: 'blur' }]
    }
  })

  /**
   * 表单项配置
   */
  const formItems = computed<FormItem[]>(() => {
    const baseItems: FormItem[] = [{ label: '菜单类型', key: 'type', span: 24 }]
    // Switch 组件的 span：小屏幕 12，大屏幕 6
    const switchSpan = width.value < 640 ? 12 : 6
    if (['folder'].includes(form.type)) {
      return [
        ...baseItems,
        {
          label: '父级菜单',
          key: 'parentId',
          type: 'treeselect',
          props: {
            clearable: true,
            filterable: true,
            data: select.value.menuTree,
            props: {
              label: (data: AppRouteRecord) => formatMenuTitle(data.meta?.title),
              value: 'id'
            }
          }
        },
        { label: '目录名称', key: 'title', type: 'input', props: { placeholder: '目录名称' } },
        {
          label: createLabelTooltip(
            '路由地址',
            '一级菜单：以 / 开头的绝对路径（如 /dashboard）\n二级及以下：相对路径（如 console、user）'
          ),
          key: 'path',
          type: 'input',
          props: { placeholder: '如：/dashboard 或 console' }
        },
        { label: '权限标识', key: 'name', type: 'input', props: { placeholder: '如：User' } },
        {
          label: createLabelTooltip(
            '组件路径',
            '一级父级菜单：填写 /index/index\n具体页面：填写组件路径（如 /system/user）'
          ),
          key: 'component',
          type: 'input',
          props: { placeholder: '如：/system/user 或留空' }
        },
        {
          label: createLabelTooltip('图标', () =>
            h('div', { class: 'leading-5' }, [
              h(
                'a',
                {
                  href: 'https://remixicon.com/',
                  target: '_blank',
                  class: 'text-primary underline inline-block'
                },
                'Remix Icon 官网 '
              )
            ])
          ),
          key: 'icon',
          type: 'input',
          props: { placeholder: '如：ri:user-line' }
        },
        {
          label: createLabelTooltip('菜单排序', '值越小越靠前'),
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
        { label: '显示徽章', key: 'showBadge', type: 'switch', span: switchSpan }
      ]
    }
    if (['menu'].includes(form.type)) {
      return [
        ...baseItems,
        {
          label: '父级菜单',
          key: 'parentId',
          type: 'treeselect',
          props: {
            clearable: true,
            filterable: true,
            data: select.value.menuTree,
            props: {
              label: (data: AppRouteRecord) => formatMenuTitle(data.meta?.title),
              value: 'id'
            }
          }
        },
        { label: '菜单名称', key: 'title', type: 'input', props: { placeholder: '菜单名称' } },
        {
          label: createLabelTooltip(
            '路由地址',
            '一级菜单：以 / 开头的绝对路径（如 /dashboard）\n二级及以下：相对路径（如 console、user）'
          ),
          key: 'path',
          type: 'input',
          props: { placeholder: '如：/dashboard 或 console' }
        },
        { label: '权限标识', key: 'name', type: 'input', props: { placeholder: '如：User' } },
        {
          label: createLabelTooltip(
            '组件路径',
            '一级父级菜单：填写 /index/index\n具体页面：填写组件路径（如 /system/user）'
          ),
          key: 'component',
          type: 'input',
          props: { placeholder: '如：/system/user 或留空' }
        },
        {
          label: createLabelTooltip('图标', () =>
            h('div', { class: 'leading-5' }, [
              h(
                'a',
                {
                  href: 'https://remixicon.com/',
                  target: '_blank',
                  class: 'text-primary underline inline-block'
                },
                'Remix Icon 官网 '
              )
            ])
          ),
          key: 'icon',
          type: 'input',
          props: { placeholder: '如：ri:user-line' }
        },
        {
          label: createLabelTooltip('菜单排序', '值越小越靠前'),
          key: 'sort',
          type: 'number',
          props: { min: 1, controlsPosition: 'right', style: { width: '100%' } }
        },
        /*{
          label: createLabelTooltip(
            '角色权限',
            '仅用于前端权限模式：配置角色标识（如 R_SUPER、R_ADMIN）\n后端权限模式：无需配置'
          ),
          key: 'roles',
          type: 'inputtag',
          props: { placeholder: '输入角色标识后按回车，如：R_SUPER' }
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
          label: createLabelTooltip(
            '激活路径',
            '用于详情页等隐藏菜单，指定高亮显示的父级菜单路径\n例如：用户详情页高亮显示"用户管理"菜单'
          ),
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
          label: createLabelTooltip('权限排序', '值越小越靠前'),
          key: 'sort',
          type: 'number',
          props: { min: 1, controlsPosition: 'right', style: { width: '100%' } }
        }
      ]
    }
  })

  const dialogTitle = computed(() => {
    const typeMap = {
      folder: '目录',
      menu: '菜单',
      button: '按钮'
    }
    const type = typeMap[form.type]
    return isEdit.value ? `编辑${type}` : `新建${type}`
  })

  /**
   * 是否禁用菜单类型切换
   */
  const disableMenuType = computed(() => {
    return props.lockType
  })

  /**
   * 重置表单数据
   */
  const handleResetFields = async (): Promise<void> => {
    await nextTick()
    const { ref } = formRef.value
    ref.value?.resetFields()
  }

  /**
   * 加载表单数据（编辑模式）
   */
  const loadFormData = (): void => {
    const {
      id,
      parentId = form.parentId,
      type,
      name,
      sort,
      path,
      component,
      meta = {}
    } = props.editData ?? {}
    Object.assign(form, {
      id,
      parentId,
      type: type || props.type,
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
  const handleSubmit = async (): Promise<void> => {
    if (!formRef.value) return

    try {
      await formRef.value.validate()
    } catch {
      ElMessage.error('表单校验失败，请检查输入')
    }
    try {
      loading.value = true
      const { id, parentId, path, component, name, type, sort, ...rest } = toRaw(form)

      const params: AppRouteRecord = {
        parentId: parentId ?? null,
        path,
        component,
        name,
        type,
        sort,
        meta: { ...rest }
      }
      if (isEmpty(props.editData)) {
        await addRMenu(params)
      } else {
        await editMenu({ ...params, id })
      }
      emit('submit', { ...form })
      handleCancel()
    } finally {
      loading.value = false
    }
  }

  /**
   * 取消操作
   */
  const handleCancel = (): void => {
    emit('update:visible', false)
    handleResetFields()
  }

  const handleSetParent = (row: MenuFormData = {} as MenuFormData): void => {
    form.parentId = row.id ?? null
    select.value = {
      ...unref(select),
      menuTree: row.menuTree
    }
  }

  /**
   * 监听对话框显示状态
   */
  watch(
    () => props.visible,
    (newVal) => {
      if (newVal) {
        loadFormData()
        handleResetFields()
      }
    }
  )

  defineExpose({
    handleSetParent
  })
</script>
