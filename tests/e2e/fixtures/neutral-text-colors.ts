import 'element-plus/theme-chalk/src/index.scss'
import '@/assets/styles/core/tailwind.css'
import { createApp, h } from 'vue'
import '@/assets/styles/index.scss'
createApp({
  render: () =>
    h(
      'main',
      { class: 'p-4 bg-[var(--el-bg-color)]' },
      ['bg-color', 'fill-color-lighter'].map((background) =>
        h(
          'section',
          { style: { backgroundColor: 'var(--el-' + background + ')' } },
          ['primary', 'regular', 'secondary', 'placeholder'].map((role) =>
            h(
              'p',
              { class: 'neutral-text', style: { color: 'var(--el-text-color-' + role + ')' } },
              background + ' ' + role
            )
          )
        )
      )
    )
}).mount('#app')
