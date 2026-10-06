import { difference } from 'lodash-es'

/** Replace model fields without detaching consumers of the existing reactive object. */
export function replaceReactiveModel<T extends object>(current: T, next: object): T {
  for (const key of difference(Object.keys(current), Object.keys(next))) {
    Reflect.deleteProperty(current, key)
  }
  return Object.assign(current, next)
}
