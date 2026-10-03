import { createApp, h, ref } from 'vue'
import { addIcon } from '@iconify/vue'
import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

addIcon('quality:check', {
  width: 24,
  height: 24,
  body: '<path fill="currentColor" d="m9 16-4-4 1.4-1.4L9 13.2l8.6-8.6L19 6z"/>'
})
const enlarged = ref(false)
createApp({
  render: () =>
    h('main', { style: { padding: '24px' } }, [
      h('h1', '共享图标属性验收'),
      h(ArtSvgIcon, {
        icon: 'quality:check',
        'data-testid': 'decorative-icon',
        'aria-hidden': 'true'
      }),
      h(ArtSvgIcon, {
        icon: 'quality:check',
        'data-testid': 'named-icon',
        role: 'img',
        'aria-hidden': 'false',
        'aria-label': enlarged.value ? '已完成，大图标' : '已完成',
        class: enlarged.value ? 'expanded' : 'compact',
        style: { color: enlarged.value ? 'rgb(20, 120, 80)' : 'rgb(60, 70, 90)' },
        width: enlarged.value ? 48 : 24,
        height: enlarged.value ? 48 : 24
      }),
      h(
        'button',
        {
          type: 'button',
          onClick: () => {
            enlarged.value = !enlarged.value
          }
        },
        '切换尺寸'
      )
    ])
}).mount('#icon-preview')
