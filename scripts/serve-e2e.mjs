import { createReadStream, existsSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import path from 'node:path'

const host = '127.0.0.1'
const port = Number(process.env.E2E_PORT || 41737)
const root = path.resolve(process.cwd(), 'docs')
const buildBasePath = '/art-supabase-pro'
const contentTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.jpeg': 'image/jpeg',
  '.jpg': 'image/jpeg',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm',
  '.webp': 'image/webp'
}

createServer((request, response) => {
  const requestPath = decodeURIComponent(new URL(request.url || '/', `http://${host}`).pathname)
  const pathname = requestPath.startsWith(`${buildBasePath}/`)
    ? requestPath.slice(buildBasePath.length)
    : requestPath
  let filePath = path.resolve(root, `.${pathname === '/' ? '/index.html' : pathname}`)

  if (!filePath.startsWith(`${root}${path.sep}`) || !existsSync(filePath)) {
    response.writeHead(404).end('Not found')
    return
  }
  if (statSync(filePath).isDirectory()) filePath = path.join(filePath, 'index.html')

  const contentType =
    contentTypes[path.extname(filePath).toLowerCase()] || 'application/octet-stream'
  response.writeHead(200, { 'Content-Type': contentType })
  createReadStream(filePath).pipe(response)
}).listen(port, host, () => {
  console.log(`E2E static server listening on http://${host}:${port}`)
})
