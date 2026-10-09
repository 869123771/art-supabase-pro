import { createApp, h } from 'vue'
import { ElAlert, ElButton, ElTag } from 'element-plus'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const types = ['success', 'warning', 'danger'] as const
createApp({
  render: () =>
    h(
      'main',
      { class: 'grid gap-4 p-4 bg-[var(--el-bg-color)]' },
      types.map((type) =>
        h('section', { class: 'grid gap-3', 'aria-label': type }, [
          h('div', { class: 'flex flex-wrap gap-3' }, [
            ...(['light', 'plain', 'dark'] as const).map((effect) =>
              h(ElTag, { type, effect }, () => `${type} ${effect}`)
            ),
            h(ElButton, { type }, () => `${type} 操作`),
            h(ElButton, { type, plain: true }, () => `${type} 次要操作`),
            h(ElButton, { type, dashed: true }, () => `${type} 虚线操作`)
          ]),
          ...(['light', 'dark'] as const).map((effect) =>
            h(ElAlert, {
              type: type === 'danger' ? 'error' : type,
              title: `${type} ${effect} 提示`,
              description: '公共状态文字应当清晰可读',
              effect,
              closable: false
            })
          )
        ])
      )
    )
}).mount('#semantic-colors')
