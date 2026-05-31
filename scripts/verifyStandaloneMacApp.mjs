import { existsSync, readdirSync, rmSync } from 'node:fs'
import { createServer as createTcpServer } from 'node:net'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { execFileSync, spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname } from 'node:path'

const projectRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const appName = 'Fed Chairman Game Standalone'
const zipPath = join(projectRoot, 'release', `${appName}.zip`)

function portAvailable(port) {
  return new Promise((resolve) => {
    const probe = createTcpServer()
    probe.once('error', () => resolve(false))
    probe.once('listening', () => probe.close(() => resolve(true)))
    probe.listen(port, '127.0.0.1')
  })
}

async function findPort() {
  for (let port = 4291; port < 4391; port += 1) {
    if (await portAvailable(port)) {
      return port
    }
  }
  throw new Error('No verification port is available.')
}

async function waitForOk(url) {
  let lastError
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try {
      const response = await fetch(url, { method: 'HEAD' })
      if (response.ok) {
        return response
      }
      lastError = new Error(`${url} returned ${response.status}`)
    } catch (error) {
      lastError = error
    }
    await new Promise((resolve) => setTimeout(resolve, 150))
  }
  throw lastError instanceof Error ? lastError : new Error(`Timed out waiting for ${url}`)
}

async function verify() {
  if (process.platform !== 'darwin') {
    throw new Error('Standalone .app verification is only supported on macOS.')
  }
  if (!existsSync(zipPath)) {
    throw new Error(`Missing ${zipPath}. Run npm run package:mac:standalone first.`)
  }

  const extractRoot = execFileSync('mktemp', ['-d'], { encoding: 'utf8' }).trim()
  const extractedApp = join(extractRoot, `${appName}.app`)
  const port = await findPort()
  let child

  try {
    execFileSync('ditto', ['-x', '-k', zipPath, extractRoot], { stdio: 'ignore' })
    execFileSync('plutil', ['-lint', join(extractedApp, 'Contents', 'Info.plist')], { stdio: 'inherit' })
    execFileSync('codesign', ['--verify', '--deep', '--strict', '--verbose=2', extractedApp], { stdio: 'inherit' })

    child = spawn(join(extractedApp, 'Contents', 'MacOS', appName), [], {
      env: {
        ...process.env,
        FED_CHAIRMAN_PORT: String(port),
        FED_CHAIRMAN_NO_OPEN: '1',
      },
      stdio: 'ignore',
    })

    await waitForOk(`http://127.0.0.1:${port}/`)
    const assetsDir = join(extractedApp, 'Contents', 'Resources', 'app', 'dist', 'assets')
    const assetName = readdirSync(assetsDir).find((name) => name.startsWith('index-') && name.endsWith('.js'))
    if (!assetName) {
      throw new Error('Could not find built index asset in standalone app.')
    }
    const assetResponse = await waitForOk(`http://127.0.0.1:${port}/assets/${assetName}`)
    const contentType = assetResponse.headers.get('content-type') ?? ''
    if (!contentType.includes('text/javascript')) {
      throw new Error(`Expected JavaScript content type, received ${contentType}`)
    }
    console.log(`Verified ${zipPath}`)
  } finally {
    if (child && !child.killed) {
      child.kill('SIGTERM')
    }
    rmSync(extractRoot, { recursive: true, force: true })
  }
}

verify().catch((error) => {
  console.error(error instanceof Error ? error.message : error)
  process.exitCode = 1
})
