/**
 * Business modules are independent repositories with their own lockfiles. The platform host loads
 * their source directly, so these shared dependencies must resolve from the host root. Keeping the
 * policy in one tested module prevents duplicated Vue contexts, Pinia stores, Element Plus
 * injection state and transport clients in the integrated application.
 */
export const hostedModuleSharedDependencies = [
  '@element-plus/icons-vue',
  '@iconify/vue',
  '@supabase/supabase-js',
  '@vueuse/core',
  'dayjs',
  'element-plus',
  'lodash-es',
  'pinia',
  'vue',
  'vue-i18n',
  'vue-router'
] as const
