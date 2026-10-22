import { createApp, h, ref } from 'vue'
import { useAmapGeocoder } from '@/hooks/core/useAmapGeocoder'

createApp({
  setup() {
    const { geocodeAddress } = useAmapGeocoder()
    const result = ref('尚未解析')
    const loading = ref(false)
    async function locate(): Promise<void> {
      loading.value = true
      try {
        const location = await geocodeAddress('测试地址')
        result.value = location ? `${location.longitude},${location.latitude}` : '未找到地址'
      } catch (error) {
        result.value = error instanceof Error ? error.message : '地址解析失败，请重试'
      } finally {
        loading.value = false
      }
    }
    return () =>
      h('main', [
        h('button', { type: 'button', disabled: loading.value, onClick: locate }, '解析地址'),
        h('output', { 'data-testid': 'result' }, result.value)
      ])
  }
}).mount('#app')
