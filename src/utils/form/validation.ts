import { nextTick, type Ref } from 'vue'

export interface ValidatableFormRef {
  clearValidate: () => void
  validate: () => Promise<unknown>
}

type FormRef = Ref<ValidatableFormRef | undefined>
type FormRootRef = Ref<HTMLElement | undefined>

export function clearFormRefsValidation(formRefs: readonly FormRef[]): void {
  formRefs.forEach((formRef) => formRef.value?.clearValidate())
}

export function focusFirstInvalidFormField(rootRef: FormRootRef): void {
  const invalidItem = rootRef.value?.querySelector<HTMLElement>('.el-form-item.is-error')
  if (!invalidItem) return

  invalidItem.scrollIntoView({ behavior: 'smooth', block: 'center' })
  invalidItem
    .querySelector<HTMLElement>(
      'input:not([type="hidden"]):not([disabled]), textarea:not([disabled]), button:not([disabled]), [tabindex]:not([tabindex="-1"])'
    )
    ?.focus()
}

export async function validateFormRefs(
  formRefs: readonly FormRef[],
  rootRef: FormRootRef
): Promise<boolean> {
  for (const formRef of formRefs) {
    try {
      await formRef.value?.validate()
    } catch {
      await nextTick()
      focusFirstInvalidFormField(rootRef)
      return false
    }
  }

  return true
}
