<template>
  <div
    class="art-turnstile-captcha"
    :class="{ 'is-interaction-only': props.appearance === 'interaction-only' }"
  >
    <div ref="containerRef" class="art-turnstile-captcha__widget"></div>
  </div>
</template>

<script setup lang="ts">
  defineOptions({ name: 'ArtTurnstileCaptcha' })

  type TurnstileTheme = 'light' | 'dark' | 'auto'
  type TurnstileSize = 'normal' | 'compact' | 'flexible'
  type TurnstileAppearance = 'always' | 'execute' | 'interaction-only'
  type TurnstileExecution = 'render' | 'execute'

  interface TurnstileRenderOptions {
    sitekey: string
    theme?: TurnstileTheme
    size?: TurnstileSize
    appearance?: TurnstileAppearance
    execution?: TurnstileExecution
    callback?: (token: string) => void
    'expired-callback'?: () => void
    'error-callback'?: () => void
    'timeout-callback'?: () => void
  }

  interface TurnstileApi {
    render: (container: HTMLElement, options: TurnstileRenderOptions) => string
    reset: (widgetId?: string) => void
    remove: (widgetId?: string) => void
    execute: (widgetId?: string) => void
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
    appearance?: TurnstileAppearance
    execution?: TurnstileExecution
  }

  const props = withDefaults(defineProps<Props>(), {
    theme: 'auto',
    size: 'normal',
    appearance: 'always',
    execution: 'render'
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
  let executeResolver: ((token: string) => void) | undefined
  let executeRejecter: ((error: Error) => void) | undefined

  const clearExecutePromise = (): void => {
    executeResolver = undefined
    executeRejecter = undefined
  }

  const handleVerify = (token: string): void => {
    executeResolver?.(token)
    clearExecutePromise()
    emit('verify', token)
  }

  const handleExecutionError = (type: 'error' | 'timeout'): void => {
    executeRejecter?.(
      new Error(
        type === 'timeout' ? 'Turnstile verification timed out' : 'Turnstile verification failed'
      )
    )
    clearExecutePromise()
    if (type === 'timeout') {
      emit('timeout')
      return
    }
    emit('error')
  }

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
      appearance: props.appearance,
      execution: props.execution,
      callback: handleVerify,
      'expired-callback': () => emit('expired'),
      'error-callback': () => handleExecutionError('error'),
      'timeout-callback': () => handleExecutionError('timeout')
    })
  }

  const reset = (): void => {
    clearExecutePromise()
    if (widgetId.value && window.turnstile) {
      window.turnstile.reset(widgetId.value)
    }
  }

  const execute = async (): Promise<string> => {
    await render()

    if (!widgetId.value || !window.turnstile) {
      throw new Error('Turnstile is not ready')
    }

    return await new Promise<string>((resolve, reject) => {
      executeResolver = resolve
      executeRejecter = reject
      window.turnstile?.execute(widgetId.value)
    })
  }

  watch(
    () => [props.sitekey, props.theme, props.size, props.appearance, props.execution],
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
    remove,
    execute
  })
</script>

<style scoped lang="scss">
  .art-turnstile-captcha {
    flex: 1 1 100%;
    width: 100%;
    min-height: 65px;

    &__widget {
      display: flex;
      justify-content: center;
      width: 100%;

      :deep(> div) {
        width: 100% !important;
      }

      :deep(iframe) {
        width: 100% !important;
        max-width: 100%;
      }
    }

    &.is-interaction-only {
      min-height: 0;
    }
  }
</style>
