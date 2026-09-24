import type { InjectionKey, Ref } from 'vue'

export interface ArtDialogFocusContext {
  focusMode: Readonly<Ref<boolean>>
  registerForm: () => () => void
}

export const artDialogFocusKey: InjectionKey<ArtDialogFocusContext> = Symbol('artDialogFocus')
