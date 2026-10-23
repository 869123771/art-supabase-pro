import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises'
import path from 'node:path'
import process from 'node:process'

const workspace = process.cwd()
const sourceRoot = path.join(workspace, 'supabase/functions')
const outputRoot = path.join(workspace, '.artifacts/cloudbase/edge-runtime')
const functionRoot = path.join(outputRoot, 'functions')

const entries = await readdir(sourceRoot, { withFileTypes: true })
const functionNames = entries
  .filter((entry) => entry.isDirectory() && entry.name !== '_shared')
  .map((entry) => entry.name)
  .sort()

await rm(outputRoot, { recursive: true, force: true })
await mkdir(outputRoot, { recursive: true })
await cp(sourceRoot, functionRoot, { recursive: true })

const rewriteRemoteSharedImports = async (directory: string) => {
  const children = await readdir(directory, { withFileTypes: true })
  for (const child of children) {
    const target = path.join(directory, child.name)
    if (child.isDirectory()) {
      await rewriteRemoteSharedImports(target)
      continue
    }
    if (!child.isFile() || !child.name.endsWith('.ts')) continue
    const relativeDirectory = path.relative(functionRoot, directory).replace(/\\/gu, '/')
    const sharedPrefix = relativeDirectory === '_shared' ? './' : '../_shared/'
    const source = await readFile(target, 'utf8')
    const rewritten = source
      .replace(
        /https:\/\/raw\.githubusercontent\.com\/869123771\/art-supabase-pro\/[0-9a-f]+\/supabase\/functions\/_shared\/([^'"\s]+)/gu,
        `${sharedPrefix}$1`
      )
      .replace(/^import\s+['"]jsr:@supabase\/functions-js\/edge-runtime\.d\.ts['"];?\s*$/gmu, '')
    if (rewritten !== source) await writeFile(target, rewritten, 'utf8')
  }
}

await rewriteRemoteSharedImports(functionRoot)

const router = `
const handlers = new Map<string, (request: Request) => Response | Promise<Response>>()
let registering = ''
const nativeServe = Deno.serve.bind(Deno)
const nativeFetch = globalThis.fetch.bind(globalThis)

const captureServe = (...args: unknown[]) => {
  const handler = typeof args[0] === 'function' ? args[0] : args[1]
  if (typeof handler !== 'function' || !registering) throw new Error('Invalid Deno.serve registration')
  handlers.set(registering, handler as (request: Request) => Response | Promise<Response>)
  return { finished: Promise.resolve(), ref() {}, unref() {}, shutdown: async () => {} }
}
Object.defineProperty(Deno, 'serve', { configurable: true, value: captureServe })

for (const functionName of ${JSON.stringify(functionNames)}) {
  registering = functionName
  await import(\`./functions/\${functionName}/index.ts\`)
  if (!handlers.has(functionName)) throw new Error(\`Function \${functionName} did not register a handler\`)
}
registering = ''
Object.defineProperty(Deno, 'serve', { configurable: true, value: nativeServe })

const configuredGatewayOrigin = String(Deno.env.get('SUPABASE_URL') || '')
const gatewayOrigin = configuredGatewayOrigin.endsWith('/')
  ? configuredGatewayOrigin.slice(0, -1)
  : configuredGatewayOrigin
const port = Number(Deno.env.get('PORT') || 9000)

globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
  const originalUrl = input instanceof Request ? input.url : String(input)
  let url: URL
  try {
    url = new URL(originalUrl)
  } catch {
    return nativeFetch(input, init)
  }
  if (url.origin !== gatewayOrigin) return nativeFetch(input, init)
  if (url.pathname === '/rest/v1' || url.pathname.startsWith('/rest/v1/')) {
    url.pathname = \`/v1/rdb/rest\${url.pathname.slice('/rest/v1'.length)}\`
  } else if (url.pathname.startsWith('/functions/v1/')) {
    const functionName = url.pathname.slice('/functions/v1/'.length).split('/')[0]
    url = new URL(\`http://127.0.0.1:\${port}/\${functionName}\`)
  }
  const request = input instanceof Request ? new Request(url, input) : url
  return nativeFetch(request, init)
}) as typeof fetch

nativeServe({ hostname: '0.0.0.0', port }, async (request) => {
  const url = new URL(request.url)
  if (url.pathname === '/health') {
    return Response.json({ ok: true, functions: handlers.size })
  }
  const functionName = url.searchParams.get('function') || url.pathname.split('/').filter(Boolean)[0] || ''
  const handler = handlers.get(functionName)
  if (!handler) return Response.json({ code: 'not_found', error: 'Function not found' }, { status: 404 })
  const result = await handler(request)
  const headers = new Headers(result.headers)
  headers.delete('access-control-allow-origin')
  headers.delete('access-control-allow-credentials')
  return new Response(result.body, { status: result.status, statusText: result.statusText, headers })
})
`

const serveShim = `
export const serve = (handler: (request: Request) => Response | Promise<Response>) =>
  Deno.serve(handler)
`

const importMap = {
  imports: {
    'https://deno.land/std@0.224.0/http/server.ts': './serve-shim.ts',
    'https://deno.land/std@0.201.0/http/server.ts': './serve-shim.ts',
    'https://esm.sh/@supabase/supabase-js@2': 'jsr:@supabase/supabase-js@2'
  }
}

const dockerfile = `FROM denoland/deno:2.5.4
WORKDIR /app
COPY . .
RUN deno cache --import-map=import_map.json router.ts
EXPOSE 80
CMD ["run", "--allow-env", "--allow-net", "--allow-read=/app", "--import-map=import_map.json", "router.ts"]
`

await Promise.all([
  writeFile(path.join(outputRoot, 'router.ts'), router.trimStart(), 'utf8'),
  writeFile(path.join(outputRoot, 'serve-shim.ts'), serveShim.trimStart(), 'utf8'),
  writeFile(
    path.join(outputRoot, 'import_map.json'),
    `${JSON.stringify(importMap, null, 2)}\n`,
    'utf8'
  ),
  writeFile(path.join(outputRoot, 'Dockerfile'), dockerfile, 'utf8'),
  writeFile(path.join(outputRoot, '.dockerignore'), '.git\nnode_modules\n', 'utf8')
])

process.stdout.write(`${JSON.stringify({ outputRoot, functions: functionNames.length })}\n`)
