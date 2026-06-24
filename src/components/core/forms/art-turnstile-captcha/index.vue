<template>
  <div class="art-turnstile-captcha">
    <div ref="containerRef" class="art-turnstile-captcha__widget"></div>
  </div>
</template>

<script setup lang="ts">
  defineOptions({ name: 'ArtTurnstileCaptcha' })

  type TurnstileTheme = 'light' | 'dark' | 'auto'
  type TurnstileSize = 'normal' | 'compact' | 'flexible'

  interface TurnstileRenderOptions {
    sitekey: string
    theme?: TurnstileTheme
    size?: TurnstileSize
    callback?: (token: string) => void
    'expired-callback'?: () => void
    'error-callback'?: () => void
    'timeout-callback'?: () => void
  }

  interface TurnstileApi {
    render: (container: HTMLElement, options: TurnstileRenderOptions) => string
    reset: (widgetId?: string) => void
    remove: (widgetId?: string) => void
  }

  declare global {
    interface Window {
      turnstile?: TurnstileApi
    }
  }

  interface Props {
    sitekey: string
    theme?: TurnstileTheme
    size?: TurnstileSize
  }

  const props = withDefaults(defineProps<Props>(), {
    theme: 'auto',
    size: 'normal'
  })

  const emit = defineEmits<{
    verify: [token: string]
    expired: []
    error: []
    timeout: []
  }>()

  const SCRIPT_ID = 'cloudflare-turnstile-script'
  const SCRIPT_SRC = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'

  const containerRef = ref<HTMLElement>()
  const widgetId = ref<string>()
  let scriptPromise: Promise<void> | null = null

  const loadTurnstileScript = (): Promise<void> => {
    if (typeof window === 'undefined') return Promise.resolve()
    if (window.turnstile) return Promise.resolve()
    if (scriptPromise) return scriptPromise

    scriptPromise = new Promise((resolve, reject) => {
      const existingScript = document.getElementById(SCRIPT_ID) as HTMLScriptElement | null
      if (existingScript) {
        existingScript.addEventListener('load', () => resolve(), { once: true })
        existingScript.addEventListener('error', () => reject(new Error('Turnstile load failed')), {
          once: true
        })
        return
      }

      const script = document.createElement('script')
      script.id = SCRIPT_ID
      script.src = SCRIPT_SRC
      script.async = true
      script.defer = true
      script.onload = () => resolve()
      script.onerror = () => reject(new Error('Turnstile load failed'))
      document.head.appendChild(script)
    })

    return scriptPromise
  }

  const remove = (): void => {
    if (widgetId.value && window.turnstile) {
      window.turnstile.remove(widgetId.value)
    }
    widgetId.value = undefined
  }

  const render = async (): Promise<void> => {
    if (!props.sitekey || !containerRef.value) return

    await loadTurnstileScript()
    if (!window.turnstile || !containerRef.value) return

    remove()
    widgetId.value = window.turnstile.render(containerRef.value, {
      sitekey: props.sitekey,
      theme: props.theme,
      size: props.size,
      callback: (token: string) => emit('verify', token),
      'expired-callback': () => emit('expired'),
      'error-callback': () => emit('error'),
      'timeout-callback': () => emit('timeout')
    })
  }

  const reset = (): void => {
    if (widgetId.value && window.turnstile) {
      window.turnstile.reset(widgetId.value)
    }
  }

  watch(
    () => [props.sitekey, props.theme, props.size],
    () => {
      void render()
    }
  )

  onMounted(() => {
    void render()
  })

  onBeforeUnmount(() => {
    remove()
  })

  defineExpose({
    reset,
    remove
  })
</script>

<style scoped lang="scss">
  .art-turnstile-captcha {
    min-height: 65px;

    &__widget {
      display: flex;
      justify-content: center;
      width: 100%;
    }
  }
</style>
