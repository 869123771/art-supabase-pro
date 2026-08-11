import { get } from 'lodash-es'

/**
 * Format a common business option as `name（code）`, falling back to the name.
 * Dynamic field access stays in this shared boundary instead of being cast in each page.
 */
export function formatNameCodeOption(option: object, nameKey: string, codeKey: string): string {
  const name = String(get(option, nameKey) ?? '')
  const code = String(get(option, codeKey) ?? '')
  return code ? `${name}（${code}）` : name
}
