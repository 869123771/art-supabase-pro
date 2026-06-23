import { readonly, ref } from 'vue'
import { readSystemParamValue } from './read-system-param'

const PASSWORD_MIN_LENGTH_KEY = 'security.password.min_length'
const DEFAULT_PASSWORD_MIN_LENGTH = 6

const passwordMinLength = ref(DEFAULT_PASSWORD_MIN_LENGTH)

const parsePositiveInteger = (value: string): number | undefined => {
  const parsed = Number(value)
  if (!Number.isInteger(parsed) || parsed <= 0) {
    return undefined
  }
  return parsed
}

export const loadPasswordMinLength = async (): Promise<number> => {
  passwordMinLength.value = await readSystemParamValue({
    key: PASSWORD_MIN_LENGTH_KEY,
    fallback: DEFAULT_PASSWORD_MIN_LENGTH,
    parse: (value) => parsePositiveInteger(value)
  })
  return passwordMinLength.value
}

export const getPasswordMinLengthMessage = (
  translate?: (key: string) => string,
  fallback = '密码长度不能少于 {min} 位'
): string => {
  const template = translate?.('register.rule.passwordLength') || fallback
  return template.includes('{min}')
    ? template.replace('{min}', String(passwordMinLength.value))
    : template.replace(/\d+/, String(passwordMinLength.value))
}

export const usePasswordMinLengthParam = () => ({
  passwordMinLength: readonly(passwordMinLength),
  loadPasswordMinLength,
  getPasswordMinLengthMessage
})
