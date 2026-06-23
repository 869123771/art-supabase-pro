import { usePasswordMinLengthParam } from './password-min-length'
import { useRoleBuiltinCodeParams } from './role-builtin-codes'

export function useSystemParam() {
  return {
    ...usePasswordMinLengthParam(),
    ...useRoleBuiltinCodeParams()
  }
}
