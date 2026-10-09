import { createApp, h, ref } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import language from '@/locales'
import { store } from '@/store'
import { useUserStore } from '@/store/modules/user'
import { setupGlobDirectives } from '@/directives'
import PersonDialog from '@mdm/views/production/modules/person-dialog.vue'
import DepartmentDialog from '@mdm/views/production/modules/department-dialog.vue'
import TemplateDialog from '@mdm/views/production/operation-template/modules/template-dialog.vue'
import ShiftScheduleDialog from '@mdm/views/production/shift-scheduling/modules/shift-schedule-dialog.vue'
import { createDepartment } from '@mdm/views/production/modules/production-model'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const mode = new URLSearchParams(location.search).get('mode')
const department = mode === 'department'
const app = createApp({
  setup() {
    if (mode === 'template') {
      const editor = ref<InstanceType<typeof TemplateDialog>>()
      return () =>
        h('main', { class: 'p-4' }, [
          h(
            'button',
            { type: 'button', onClick: () => editor.value?.handleOpen({ mode: 'add' }) },
            '打开编辑'
          ),
          h(TemplateDialog, { ref: editor })
        ])
    }
    if (mode === 'shift') {
      const editor = ref<InstanceType<typeof ShiftScheduleDialog>>()
      return () =>
        h('main', { class: 'p-4' }, [
          h(
            'button',
            {
              type: 'button',
              onClick: () =>
                editor.value?.handleOpen({
                  mode: 'add',
                  department: {
                    ...createDepartment(),
                    id: 'test-department',
                    tenantId: 'test-tenant',
                    name: '测试产线',
                    code: 'LINE-01'
                  }
                })
            },
            '打开编辑'
          ),
          h(ShiftScheduleDialog, { ref: editor })
        ])
    }
    const person = ref<InstanceType<typeof PersonDialog>>()
    const organization = ref<InstanceType<typeof DepartmentDialog>>()
    return () =>
      h('main', { class: 'p-4' }, [
        h(
          'button',
          {
            type: 'button',
            onClick: () =>
              department
                ? organization.value?.handleOpen({ departments: [] })
                : person.value?.handleOpen({ departments: [] })
          },
          '打开编辑'
        ),
        department ? h(DepartmentDialog, { ref: organization }) : h(PersonDialog, { ref: person })
      ])
  }
})
app.use(store)
app.use(language)
const router = createRouter({
  history: createMemoryHistory(),
  routes: [{ path: '/:pathMatch(.*)*', component: {} }]
})
app.use(router)
setupGlobDirectives(app)
useUserStore(store).setUserInfo({
  userId: 'identity-test',
  tenantId: 'test-tenant',
  platformSuper: false
})
await router.isReady()
app.mount('#app')
