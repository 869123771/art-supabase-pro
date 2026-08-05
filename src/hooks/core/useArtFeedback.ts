import { ElMessageBox, type ElMessageBoxOptions, type MessageBoxData } from 'element-plus'

export interface ArtConfirmOptions extends Omit<
  ElMessageBoxOptions,
  'message' | 'title' | 'customClass'
> {
  title?: string
  customClass?: string
}

export interface ArtPromptOptions extends ArtConfirmOptions {
  allowEmpty?: boolean
  emptyMessage?: string
  initialValue?: string
  maxLength?: number
  maxLengthMessage?: string
  multiline?: boolean
  placeholder?: string
}

export type ArtReasonPromptOptions = Omit<ArtPromptOptions, 'allowEmpty' | 'multiline'>

const normalizeMessage = (message: string): string => message.trim()
const feedbackClassName = (customClass?: string): string =>
  ['art-feedback-message-box', customClass].filter(Boolean).join(' ')

export function useArtFeedback() {
  const confirmAction = (
    message: ElMessageBoxOptions['message'],
    titleOrOptions: string | ArtConfirmOptions = '操作确认',
    legacyOptions: ArtConfirmOptions = {}
  ): Promise<MessageBoxData> => {
    const options =
      typeof titleOrOptions === 'string'
        ? { ...legacyOptions, title: titleOrOptions }
        : titleOrOptions
    const { title = '操作确认', customClass, ...messageBoxOptions } = options

    return ElMessageBox.confirm(message, title, {
      type: 'warning',
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      ...messageBoxOptions,
      customClass: feedbackClassName(customClass)
    })
  }

  const confirm = (
    message: ElMessageBoxOptions['message'],
    options: ArtConfirmOptions = {}
  ): Promise<MessageBoxData> => confirmAction(message, options)

  const confirmDelete = (message: string, options: ArtConfirmOptions = {}) =>
    confirm(message, {
      title: '删除确认',
      type: 'warning',
      confirmButtonText: '删除',
      confirmButtonType: 'danger',
      ...options
    })

  const promptText = async (
    message: string,
    title: string,
    options: ArtPromptOptions = {}
  ): Promise<string> => {
    const maxLength = options.maxLength ?? 200
    const { value } = await ElMessageBox.prompt(message, title, {
      customClass: feedbackClassName(options.multiline ? 'is-multiline' : undefined),
      type: options.type ?? 'warning',
      confirmButtonText: options.confirmButtonText ?? '确定',
      cancelButtonText: options.cancelButtonText ?? '取消',
      inputType: options.multiline ? 'textarea' : 'text',
      inputValue: options.initialValue ?? '',
      inputPlaceholder: options.placeholder,
      inputValidator: (input) => {
        const normalized = normalizeMessage(input ?? '')
        if (!options.allowEmpty && !normalized) return options.emptyMessage ?? '内容不能为空'
        if (normalized.length > maxLength) {
          return options.maxLengthMessage ?? `内容不能超过 ${maxLength} 个字`
        }
        return true
      }
    })

    return normalizeMessage(String(value ?? ''))
  }

  const promptReason = (
    message: string,
    title: string,
    options: ArtReasonPromptOptions = {}
  ): Promise<string> =>
    promptText(message, title, {
      ...options,
      multiline: true,
      placeholder: options.placeholder ?? '请填写原因',
      emptyMessage: options.emptyMessage ?? '原因不能为空',
      maxLengthMessage: options.maxLengthMessage ?? `原因不能超过 ${options.maxLength ?? 200} 个字`
    })

  return {
    confirm,
    confirmAction,
    confirmDelete,
    promptText,
    promptReason
  }
}
