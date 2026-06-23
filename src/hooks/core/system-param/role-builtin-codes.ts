import { readonly, ref } from 'vue'
import { readSystemParamValue } from './read-system-param'
import { SYSTEM_PARAM_DEFAULTS } from '@/config/system-param-defaults'

const DEFAULT_REGISTER_TENANT_CODE_KEY = 'system.role.default_register_tenant_code'
const DEFAULT_REGISTER_ROLE_CODE_KEY = 'system.role.default_register_role_code'
const SUPER_ROLE_CODE_KEY = 'system.role.super_role_code'

const { DEFAULT_REGISTER_TENANT_CODE, DEFAULT_REGISTER_ROLE_CODE, SUPER_ROLE_CODE } =
  SYSTEM_PARAM_DEFAULTS

const defaultRegisterTenantCode = ref<string>(DEFAULT_REGISTER_TENANT_CODE)
const defaultRegisterRoleCode = ref<string>(DEFAULT_REGISTER_ROLE_CODE)
const superRoleCode = ref<string>(SUPER_ROLE_CODE)

const parseNonEmptyString = (value: string): string | undefined => {
  const trimmedValue = value.trim()
  return trimmedValue || undefined
}

export const loadRoleBuiltinCodes = async (): Promise<void> => {
  const [nextDefaultRegisterTenantCode, nextDefaultRegisterRoleCode, nextSuperRoleCode] =
    await Promise.all([
      readSystemParamValue<string>({
        key: DEFAULT_REGISTER_TENANT_CODE_KEY,
        fallback: DEFAULT_REGISTER_TENANT_CODE,
        parse: parseNonEmptyString
      }),
      readSystemParamValue<string>({
        key: DEFAULT_REGISTER_ROLE_CODE_KEY,
        fallback: DEFAULT_REGISTER_ROLE_CODE,
        parse: parseNonEmptyString
      }),
      readSystemParamValue<string>({
        key: SUPER_ROLE_CODE_KEY,
        fallback: SUPER_ROLE_CODE,
        parse: parseNonEmptyString
      })
    ])

  defaultRegisterTenantCode.value = nextDefaultRegisterTenantCode
  defaultRegisterRoleCode.value = nextDefaultRegisterRoleCode
  superRoleCode.value = nextSuperRoleCode
}

export const useRoleBuiltinCodeParams = () => ({
  defaultRegisterTenantCode: readonly(defaultRegisterTenantCode),
  defaultRegisterRoleCode: readonly(defaultRegisterRoleCode),
  superRoleCode: readonly(superRoleCode),
  loadRoleBuiltinCodes
})
