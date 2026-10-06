import { createApp, h, ref } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import language from '@/locales'
import { store } from '@/store'
import { setupGlobDirectives } from '@/directives'
import MasterDialog from '@mdm/views/components/operational-master/modules/master-dialog.vue'
import type { OperationalMasterConfig } from '@mdm/views/components/operational-master/modules/master-config'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const config: OperationalMasterConfig = {
  kind: 'project',
  routeName: 'MdmProject',
  title: '项目',
  description: '主数据初始化与复制验收',
  icon: 'ri:folder-line',
  eyebrow: 'PROJECT',
  codeKey: 'projectCode',
  nameKey: 'projectName',
  formSections: [
    {
      key: 'identity',
      title: '项目信息',
      description: '确认项目名称',
      fieldKeys: ['projectCode', 'projectName', 'remark']
    }
  ],
  fields: [
    { key: 'projectCode', label: '项目编码', systemGenerated: true },
    { key: 'projectName', label: '项目名称', required: true },
    { key: 'remark', label: '备注', type: 'textarea', span: 24 }
  ]
}
const dialog = ref<InstanceType<typeof MasterDialog>>()
const open = (copy: boolean) =>
  dialog.value?.handleOpen({
    config,
    tenantId: 'test-tenant',
    tenantOptions: [],
    groups: [],
    copy,
    row: copy
      ? {
          id: 'source',
          tenantId: 'source-tenant',
          enabled: true,
          projectCode: 'PR001',
          projectName: '原项目',
          remark: '原项目备注'
        }
      : undefined
  })
const app = createApp({
  render: () =>
    h('main', { class: 'p-4' }, [
      h('button', { type: 'button', onClick: () => open(false) }, '新增测试项目'),
      h('button', { type: 'button', onClick: () => open(true) }, '复制测试项目'),
      h(MasterDialog, { ref: dialog })
    ])
})
app.use(store)
app.use(language)
app.use(
  createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: { template: '<div />' } }]
  })
)
setupGlobDirectives(app)
app.mount('#master-model-preview')
