import { inject } from 'vue'

export function useAipexbase() {
  const client = inject('aipexbase')

  if (!client) {
    throw new Error('Aipexbase client not found. Make sure the plugin is installed.')
  }

  return client
}
