<template>
  <ArtDialog ref="dialogRef" size="lg" :dialog-props="{ appendToBody: true }">
    <div class="number-rule-create">
      <section class="number-rule-create__form art-card-xs">
        <header class="number-rule-create__header">
          <div>
            <ArtSectionTitle :show-line="false">批量配置租户规则</ArtSectionTitle>
            <p>先从树形菜单定位业务功能，再把同一套编号规范一次分配给多个租户。</p>
          </div>
          <ElTag type="primary" round>{{ selectedTenantCount }} 个租户</ElTag>
        </header>

        <ArtForm
          ref="formRef"
          v-model="form.data"
          :items="form.items"
          :rules="form.rules"
          :span="12"
          :gutter="20"
          label-position="top"
          label-width="auto"
          :show-reset="false"
          :show-submit="false"
          :validate-on-rule-change="false"
        >
          <template #template>
            <ElInput
              v-model="form.data.template"
              maxlength="80"
              show-word-limit
              placeholder="例如：YD{YYYYMM}-{SEQ:3}"
            />
            <div class="number-rule-create__tokens" aria-label="可用模板令牌">
              <ElButton
                v-for="token in templateTokens"
                :key="token"
                size="small"
                plain
                @click="appendToken(token)"
              >
                {{ token }}
              </ElButton>
            </div>
          </template>
        </ArtForm>
      </section>

      <aside class="number-rule-create__summary">
        <section class="number-rule-create__preview art-card-xs">
          <ArtSectionTitle :show-line="false">配置预览</ArtSectionTitle>
          <code translate="no">{{ previewText }}</code>
          <dl>
            <div>
              <dt>菜单路径</dt>
              <dd>{{ selectedMenuPath || '请先选择菜单' }}</dd>
            </div>
            <div>
              <dt>编号字段</dt>
              <dd>{{ selectedScene?.fieldLabel || '待选择' }}</dd>
            </div>
            <div>
              <dt>批量范围</dt>
              <dd>{{ selectedTenantCount }} 个租户</dd>
            </div>
          </dl>
        </section>

        <ElAlert
          type="info"
          :closable="false"
          show-icon
          title="同一租户、同一编号功能只有一条规则；已有规则会同步更新，缺失规则会自动创建。"
        />
      </aside>
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { FormRules } from 'element-plus'
  import { ElMessage } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { addDocumentNumberRules, fetchDocumentNumberSceneList } from '@/api/document-number'
  import { fetchGetEnableMenuList, fetchGetEnableTenantList } from '@/api/system-manage'
  import { renderDocumentNumber, validateDocumentNumberTemplate } from '@/utils/document-number'
  import TreeUtils from '@/utils/tree'
  import { useUserStore } from '@/store/modules/user'
  import type { AppRouteRecord } from '@/types/router'

  type NumberScene = Api.SystemManage.DocumentNumberSceneItem

  interface CreateFormModel {
    menuId: string
    ruleKey: string
    tenantIds: string[]
    autoEnabled: boolean
    template: string
    resetCycle: Api.SystemManage.DocumentNumberResetCycle
    sequenceStart: number
    timezone: string
    remark: string
  }

  interface FormExpose {
    validate: () => Promise<boolean | void>
    clearValidate: () => void
  }

  interface MenuNode extends AppRouteRecord {
    disabled?: boolean
    children?: MenuNode[]
  }

  interface FormGroup {
    data: CreateFormModel
    scenes: NumberScene[]
    menus: AppRouteRecord[]
    menuTree: MenuNode[]
    tenantOptions: Array<{ label: string; value: string }>
    items: ComputedRef<FormItem[]>
    rules: ComputedRef<FormRules<CreateFormModel>>
  }

  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<FormExpose>()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const treeUtils = new TreeUtils({ idKey: 'id', parentKey: 'parentId', childrenKey: 'children' })

  const createInitialForm = (): CreateFormModel => ({
    menuId: '',
    ruleKey: '',
    tenantIds: [],
    autoEnabled: true,
    template: 'YD{YYYYMM}-{SEQ:3}',
    resetCycle: 'month',
    sequenceStart: 1,
    timezone: 'Asia/Shanghai',
    remark: ''
  })

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    scenes: [] as NumberScene[],
    menus: [] as AppRouteRecord[],
    menuTree: [] as MenuNode[],
    tenantOptions: [] as Array<{ label: string; value: string }>,
    items: computed<FormItem[]>(() => [
      { label: '业务归属', key: 'businessSection', type: 'divider', span: 24 },
      {
        label: '所属菜单',
        key: 'menuId',
        type: 'treeSelect',
        span: 12,
        props: {
          data: form.menuTree,
          clearable: true,
          filterable: true,
          checkStrictly: true,
          placeholder: '按菜单树选择功能页面',
          onChange: handleMenuChange,
          props: {
            label: (node: MenuNode) => String(node.meta?.title || node.name || '未命名菜单'),
            value: 'id',
            disabled: 'disabled'
          }
        },
        description: '目录仅用于定位，需选择已经接入编号字段的功能页。'
      },
      {
        label: '编号功能',
        key: 'ruleKey',
        type: 'select',
        span: 12,
        props: {
          clearable: true,
          disabled: !form.data.menuId,
          placeholder: form.data.menuId ? '请选择编号字段' : '请先选择所属菜单',
          onChange: handleSceneChange,
          options: availableScenes.value.map((scene: NumberScene) => ({
            label: `${scene.ruleName} · ${scene.fieldLabel}`,
            value: scene.ruleKey
          }))
        },
        description: selectedScene.value
          ? `绑定字段：${selectedScene.value.targetTable}.${selectedScene.value.targetColumn}`
          : '只显示该菜单已经接入统一编号引擎的字段。'
      },
      {
        label: '分配租户',
        key: 'tenantIds',
        type: 'select',
        span: 24,
        props: {
          multiple: true,
          filterable: true,
          collapseTags: true,
          collapseTagsTooltip: true,
          maxCollapseTags: 3,
          placeholder: '可一次选择多个租户',
          options: form.tenantOptions
        },
        description: '一次保存即可批量配置；已有租户规则会更新，缺失的会自动创建。'
      },
      { label: '生成策略', key: 'strategySection', type: 'divider', span: 24 },
      {
        label: '自动编码',
        key: 'autoEnabled',
        type: 'switch',
        span: 12,
        description: '关闭后由业务人员在对应功能页手工填写编号。'
      },
      {
        label: '重置周期',
        key: 'resetCycle',
        type: 'select',
        span: 12,
        props: {
          options: getDictMap.value.documentNumberResetCycle ?? [],
          placeholder: '请选择重置周期'
        }
      },
      {
        label: '编号模板',
        key: 'template',
        type: 'input',
        span: 24,
        description: '日期令牌可以自由组合；SEQ 后的数字表示流水号补零长度。'
      },
      {
        label: '流水起始值',
        key: 'sequenceStart',
        type: 'number',
        span: 12,
        props: { min: 1, max: 999999999999, step: 1, stepStrictly: true, style: { width: '100%' } }
      },
      {
        label: '业务时区',
        key: 'timezone',
        type: 'input',
        span: 12,
        props: { maxlength: 64, placeholder: '例如：Asia/Shanghai' }
      },
      {
        label: '维护说明',
        key: 'remark',
        type: 'input',
        span: 24,
        props: { type: 'textarea', rows: 2, maxlength: 255, showWordLimit: true }
      }
    ]),
    rules: computed<FormRules<CreateFormModel>>(() => ({
      menuId: [{ required: true, message: '请选择所属菜单', trigger: 'change' }],
      ruleKey: [{ required: true, message: '请选择编号功能', trigger: 'change' }],
      tenantIds: [
        { required: true, type: 'array', min: 1, message: '请选择至少一个租户', trigger: 'change' }
      ],
      template: [
        { required: true, message: '请输入编号模板', trigger: 'blur' },
        {
          validator: (_rule, value: string, callback) => {
            const message = validateDocumentNumberTemplate(value)
            callback(message ? new Error(message) : undefined)
          },
          trigger: 'blur'
        }
      ],
      resetCycle: [{ required: true, message: '请选择重置周期', trigger: 'change' }],
      sequenceStart: [{ required: true, message: '请输入流水起始值', trigger: 'blur' }],
      timezone: [{ required: true, message: '请输入业务时区', trigger: 'blur' }]
    }))
  })

  const availableScenes = computed<NumberScene[]>(() =>
    form.scenes.filter((scene: NumberScene) => scene.menuId === form.data.menuId)
  )
  const selectedScene = computed<NumberScene | undefined>(() =>
    form.scenes.find((scene: NumberScene) => scene.ruleKey === form.data.ruleKey)
  )
  const selectedTenantCount = computed(() => form.data.tenantIds.length)
  const selectedMenuPath = computed(() => {
    if (!form.data.menuId) return ''
    return treeUtils
      .getAncestors<MenuNode>(form.menuTree, form.data.menuId)
      .map((menu: MenuNode) => String(menu.meta?.title || menu.name || '未命名菜单'))
      .join(' / ')
  })
  const previewText = computed(() => {
    if (!form.data.autoEnabled) return '手工填写'
    try {
      return renderDocumentNumber(form.data.template, form.data.sequenceStart, form.data.timezone)
    } catch {
      return '模板或时区无效'
    }
  })
  const templateTokens = [
    '{YYYYMMDD}',
    '{YYYYMM}',
    '{YYMM}',
    '{YYYY}',
    '{YY}',
    '{MM}',
    '{DD}',
    '{SEQ:3}',
    '{SEQ:4}',
    '{SEQ:6}'
  ]

  const buildMenuTree = (): void => {
    const fullTree = treeUtils.listToTree<MenuNode>(form.menus)
    const selectableIds = new Set(form.scenes.map((scene: NumberScene) => scene.menuId))

    const keepRegisteredBranches = (nodes: MenuNode[]): MenuNode[] =>
      nodes.flatMap((node) => {
        const children = keepRegisteredBranches(node.children ?? [])
        const selectable = selectableIds.has(String(node.id))
        if (!selectable && !children.length) return []
        return [{ ...node, children, disabled: false }]
      })

    form.menuTree = keepRegisteredBranches(fullTree)
  }

  const handleMenuChange = (): void => {
    form.data.ruleKey = ''
  }

  const handleSceneChange = (ruleKey: string): void => {
    const scene = form.scenes.find((item: NumberScene) => item.ruleKey === ruleKey)
    if (!scene) return
    Object.assign(form.data, {
      template: scene.defaultTemplate,
      resetCycle: scene.defaultResetCycle,
      remark: scene.remark ?? ''
    })
  }

  const appendToken = (token: string): void => {
    if (token.startsWith('{SEQ:')) {
      form.data.template = form.data.template.replace(/\{SEQ:[1-9][0-9]?\}/, '')
    }
    form.data.template += token
  }

  const initialize = async (): Promise<void> => {
    const [sceneResult, menuResult, tenantResult] = await Promise.all([
      fetchDocumentNumberSceneList(),
      fetchGetEnableMenuList(),
      fetchGetEnableTenantList()
    ])
    form.scenes = sceneResult.data ?? []
    form.menus = (menuResult.data ?? []).filter((menu) => menu.type !== 'button')
    form.tenantOptions = (tenantResult.data ?? []).map((tenant) => ({
      label: `${tenant.tenantName}（${tenant.tenantCode}）`,
      value: String(tenant.id)
    }))
    buildMenuTree()
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    const scene = selectedScene.value
    if (!scene) return false

    try {
      const result = await addDocumentNumberRules({
        tenantIds: form.data.tenantIds,
        scene,
        autoEnabled: form.data.autoEnabled,
        template: form.data.template,
        resetCycle: form.data.resetCycle,
        sequenceStart: form.data.sequenceStart,
        timezone: form.data.timezone,
        remark: form.data.remark
      })
      const created = result.data?.created ?? 0
      const updated = result.data?.updated ?? 0
      ElMessage.success(`批量配置完成：新建 ${created} 个，更新 ${updated} 个租户规则`)
      emit('success')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (): Promise<void> => {
    Object.assign(form.data, createInitialForm())
    await dialogRef.value?.handleOpen(undefined, {
      title: '新增编号规则',
      contentMaxHeight: '76vh',
      confirmText: '批量配置',
      loading: true,
      onOpen: async (_data, api) => {
        try {
          await initialize()
          await nextTick()
          formRef.value?.clearValidate()
        } finally {
          api.setLoading(false)
        }
      },
      onConfirm: handleSubmit
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .number-rule-create {
    display: flex;
    gap: 12px;
    align-items: flex-start;

    &__form {
      flex: 1;
      min-width: 0;
      overflow: hidden;
    }

    &__header {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
      padding: 16px;
      border-bottom: 1px solid var(--el-border-color-lighter);

      :deep(.art-section-title) {
        margin: 0 0 4px;
      }
      p {
        margin: 0;
        font-size: 12px;
        color: var(--art-text-gray-500);
      }
    }

    :deep(.art-form) {
      padding: 12px 16px 4px !important;
    }

    &__tokens {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      margin-top: 8px;
      .el-button + .el-button {
        margin-left: 0;
      }
    }

    &__summary {
      position: sticky;
      top: 0;
      display: flex;
      flex: 0 0 268px;
      flex-direction: column;
      gap: 12px;
      width: 268px;
    }

    &__preview {
      padding: 14px;
    }
    &__preview > code {
      display: block;
      padding: 13px 10px;
      overflow-wrap: anywhere;
      font-size: 15px;
      font-weight: 700;
      color: var(--el-color-primary);
      text-align: center;
      background: var(--el-color-primary-light-9);
      border: 1px solid var(--el-color-primary-light-7);
      border-radius: var(--art-control-radius);
    }

    dl {
      margin: 12px 0 0;
    }
    dl div {
      padding: 8px 0;
      border-bottom: 1px solid var(--el-border-color-lighter);
    }
    dl div:last-child {
      border-bottom: 0;
    }
    dt {
      font-size: 11px;
      color: var(--art-text-gray-500);
    }
    dd {
      margin: 4px 0 0;
      line-height: 1.5;
      color: var(--art-text-gray-800);
    }
  }

  @media (max-width: 900px) {
    .number-rule-create {
      &__summary {
        display: none;
      }
    }
  }
</style>
