export interface MenuLabelSource {
  name?: unknown
  meta?: { title?: unknown } | null
}

/** Resolves the user-facing title shared by menu trees and menu-backed selectors. */
export function resolveMenuLabel(menu: MenuLabelSource, fallback = '未命名菜单'): string {
  const title = String(menu.meta?.title ?? '').trim()
  if (title) return title

  const name = String(menu.name ?? '').trim()
  return name || fallback
}
