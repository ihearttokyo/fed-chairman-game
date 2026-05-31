import { createServer } from 'node:net'
import { spawn } from 'node:child_process'
import { existsSync, readdirSync, statSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const projectRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const preferredPort = Number(process.env.FED_CHAIRMAN_PORT ?? 4173)
const host = '127.0.0.1'
const viteBin = join(projectRoot, 'node_modules', '.bin', process.platform === 'win32' ? 'vite.cmd' : 'vite')

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: projectRoot,
      stdio: options.stdio ?? 'inherit',
      shell: process.platform === 'win32',
    })
    child.on('error', reject)
    child.on('exit', (code) => {
      if (code === 0) {
        resolve()
        return
      }
      reject(new Error(`${command} ${args.join(' ')} exited with ${code ?? 'no code'}`))
    })
  })
}

function isPortAvailable(port) {
  return new Promise((resolve) => {
    const server = createServer()
    server.once('error', () => resolve(false))
    server.once('listening', () => {
      server.close(() => resolve(true))
    })
    server.listen(port, host)
  })
}

async function findPort(startPort) {
  for (let port = startPort; port < startPort + 50; port += 1) {
    if (await isPortAvailable(port)) {
      return port
    }
  }
  throw new Error(`No available localhost port found from ${startPort} to ${startPort + 49}.`)
}

function newestSourceMtime() {
  const roots = ['index.html', 'src', 'public', 'vite.config.ts', 'package-lock.json']
  let newest = 0
  const visit = (path) => {
    const stats = statSync(path)
    newest = Math.max(newest, stats.mtimeMs)
    if (!stats.isDirectory()) {
      return
    }
    for (const entry of readdirSync(path)) {
      if (entry === '.DS_Store') {
        continue
      }
      visit(join(path, entry))
    }
  }
  for (const root of roots) {
    const absolute = join(projectRoot, root)
    if (existsSync(absolute)) {
      visit(absolute)
    }
  }
  return newest
}

function shouldBuild() {
  const distIndex = join(projectRoot, 'dist', 'index.html')
  if (process.argv.includes('--rebuild') || !existsSync(distIndex)) {
    return true
  }
  return statSync(distIndex).mtimeMs < newestSourceMtime()
}

function openUrl(url) {
  if (process.platform === 'darwin') {
    return run('open', [url], { stdio: 'ignore' })
  }
  if (process.platform === 'win32') {
    return run('cmd', ['/c', 'start', '', url], { stdio: 'ignore' })
  }
  return run('xdg-open', [url], { stdio: 'ignore' })
}

async function main() {
  if (!existsSync(viteBin)) {
    console.error('Dependencies are missing. Run npm install once, then launch again.')
    process.exitCode = 1
    return
  }

  if (shouldBuild()) {
    console.log('Building Fed Chairman Game...')
    await run('npm', ['run', 'build'])
  }

  const port = await findPort(preferredPort)
  const url = `http://${host}:${port}/`
  const server = spawn(viteBin, ['preview', '--host', host, '--port', String(port), '--strictPort'], {
    cwd: projectRoot,
    stdio: 'inherit',
    shell: process.platform === 'win32',
  })

  const shutdown = () => {
    server.kill('SIGTERM')
  }
  process.on('SIGINT', shutdown)
  process.on('SIGTERM', shutdown)
  server.on('exit', (code) => {
    process.exitCode = code ?? 0
  })

  await new Promise((resolve) => setTimeout(resolve, 900))
  console.log(`Opening ${url}`)
  await openUrl(url).catch(() => {
    console.log(`Open this URL manually: ${url}`)
  })
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error)
  process.exitCode = 1
})
