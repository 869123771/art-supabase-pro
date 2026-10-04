import { createApp, h } from 'vue'
import { ElMenu } from 'element-plus'
import { createMemoryHistory, createRouter } from 'vue-router'
import language from '@/locales'
import { store } from '@/store'
import { useSettingStore } from '@/store/modules/setting'
import type { AppRouteRecord } from '@/types/router'
import SidebarSubmenu from '@/components/core/layouts/art-menus/art-sidebar-menu/widget/SidebarSubmenu.vue'
import '@styles/core/tailwind.css'
import '@styles/index.scss'
import '@/components/core/layouts/art-menus/art-sidebar-menu/theme.scss'

const routes: AppRouteRecord[] = [
  {
    name: 'LongMenuPreview',
    path: '/preview-long-menu',
    component: '/preview-long-menu',
    meta: {
      title: '企业项目管理与跨部门业务协作综合工作台',
      icon: 'ri:home-line',
      showTextBadge: 'Beta'
    }
  },
  {
    name: 'ShortMenuPreview',
    path: '/preview-short-menu',
    component: '/preview-short-menu',
    meta: { title: '工作台', icon: 'ri:home-line' }
  }
]

const app = createApp({
  render: () =>
    h('main', { class: 'layout-sidebar p-2', style: { width: '230px' } }, [
      h(ElMenu, { class: 'el-menu-design', defaultActive: '/preview-long-menu' }, () =>
        h(SidebarSubmenu, { list: routes })
      )
    ])
})
app.use(store)
useSettingStore().menuOpen = true
app.use(language)
app.use(
  createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: { render: () => null } }]
  })
)
app.mount('#menu-preview')
