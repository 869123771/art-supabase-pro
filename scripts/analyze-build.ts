import { build } from 'vite'

process.env.VITE_BUILD_ANALYZE = 'true'

await build({ mode: 'production' })
