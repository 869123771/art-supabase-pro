import { nextTick, shallowRef, type Component, type ShallowRef } from 'vue'

interface LazyComponentController {
  component: ShallowRef<Component | undefined>
  load: () => Promise<void>
}

/**
 * Defers downloading and mounting an imperative component until its first use.
 * Calling load again reuses the mounted component instance.
 */
export function useLazyComponent(
  loader: () => Promise<{ default: Component }>
): LazyComponentController {
  const component = shallowRef<Component>()

  const load = async (): Promise<void> => {
    if (!component.value) component.value = (await loader()).default
    await nextTick()
  }

  return { component, load }
}
