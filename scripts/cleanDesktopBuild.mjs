import { rmSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const projectRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const generatedDesktopBundlePath = join(projectRoot, 'src-tauri', 'target', 'release', 'bundle')

rmSync(generatedDesktopBundlePath, { recursive: true, force: true })
