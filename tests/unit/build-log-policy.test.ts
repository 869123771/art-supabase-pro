import assert from 'node:assert/strict'
import test from 'node:test'
import { getKnownFileViewerExternalization } from '../../scripts/build-log-policy'

test('build log policy recognizes known lazy file-viewer transitive warnings', () => {
  const warning = getKnownFileViewerExternalization({
    message:
      'Module "util" has been externalized for browser compatibility, imported by "D:/repo/node_modules/.pnpm/avsc@5.7.9/node_modules/avsc/lib/types.js".'
  })

  assert.equal(warning, 'util:avsc')
})

test('build log policy keeps unknown browser externalizations visible', () => {
  assert.equal(
    getKnownFileViewerExternalization({
      message:
        'Module "fs" has been externalized for browser compatibility, imported by "D:/repo/node_modules/.pnpm/new-package@1.0.0/node_modules/new-package/index.js".'
    }),
    null
  )
  assert.equal(getKnownFileViewerExternalization({ message: 'Circular dependency detected' }), null)
})
