export function useScreenChartTheme() {
  const rootRef = ref<HTMLElement | null>(null)

  const readScreenColor = (name: string, fallback: string) => {
    if (!rootRef.value) return fallback
    return getComputedStyle(rootRef.value).getPropertyValue(name).trim() || fallback
  }

  return { rootRef, readScreenColor }
}
