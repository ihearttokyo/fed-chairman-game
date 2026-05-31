import {
  chmodSync,
  copyFileSync,
  cpSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from 'node:fs'
import { basename, dirname, join } from 'node:path'
import { tmpdir } from 'node:os'
import { execFileSync, spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const projectRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const releaseDir = join(projectRoot, 'release')
const appName = 'Fed Chairman Game Standalone'
const finalAppDir = join(releaseDir, `${appName}.app`)
const zipPath = join(releaseDir, `${appName}.zip`)

function bundlePaths(appDir) {
  const contentsDir = join(appDir, 'Contents')
  const macOsDir = join(contentsDir, 'MacOS')
  const frameworksDir = join(contentsDir, 'Frameworks')
  const resourcesDir = join(contentsDir, 'Resources')
  const appResourcesDir = join(resourcesDir, 'app')

  return {
    appDir,
    contentsDir,
    macOsDir,
    frameworksDir,
    resourcesDir,
    appResourcesDir,
    executablePath: join(macOsDir, appName),
    nodePath: join(macOsDir, 'node'),
  }
}

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: projectRoot,
      stdio: 'inherit',
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

function xmlEscape(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;')
}

function serverScript() {
  return `import { createReadStream, existsSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { createServer as createTcpServer } from 'node:net'
import { dirname, extname, join, normalize } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawn } from 'node:child_process'

const appRoot = dirname(fileURLToPath(import.meta.url))
const distRoot = join(appRoot, 'dist')
const host = '127.0.0.1'
const preferredPort = Number(process.env.FED_CHAIRMAN_PORT ?? 4173)
const mimeTypes = new Map([
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.css', 'text/css; charset=utf-8'],
  ['.svg', 'image/svg+xml'],
  ['.json', 'application/json; charset=utf-8'],
])

function portAvailable(port) {
  return new Promise((resolve) => {
    const probe = createTcpServer()
    probe.once('error', () => resolve(false))
    probe.once('listening', () => probe.close(() => resolve(true)))
    probe.listen(port, host)
  })
}

async function findPort(startPort) {
  for (let port = startPort; port < startPort + 50; port += 1) {
    if (await portAvailable(port)) {
      return port
    }
  }
  throw new Error('No local port is available for Fed Chairman Game.')
}

function sendFile(response, path) {
  response.writeHead(200, {
    'Content-Type': mimeTypes.get(extname(path)) ?? 'application/octet-stream',
    'Cache-Control': path.endsWith('index.html') ? 'no-cache' : 'public, max-age=31536000, immutable',
  })
  createReadStream(path).pipe(response)
}

function resolveRequestPath(requestUrl) {
  const parsed = new URL(requestUrl, 'http://localhost')
  const pathname = decodeURIComponent(parsed.pathname)
  const candidate = normalize(join(distRoot, pathname))
  if (!candidate.startsWith(distRoot)) {
    return null
  }
  if (existsSync(candidate) && statSync(candidate).isFile()) {
    return candidate
  }
  return join(distRoot, 'index.html')
}

function openUrl(url) {
  const child = spawn('open', [url], { stdio: 'ignore' })
  child.on('error', () => {
    console.log('Open this URL manually:', url)
  })
}

const port = await findPort(preferredPort)
const server = createServer((request, response) => {
  const filePath = resolveRequestPath(request.url ?? '/')
  if (!filePath || !existsSync(filePath)) {
    response.writeHead(404)
    response.end('Not found')
    return
  }
  sendFile(response, filePath)
})

server.listen(port, host, () => {
  const url = \`http://\${host}:\${port}/\`
  console.log('Fed Chairman Game running at', url)
  if (process.env.FED_CHAIRMAN_NO_OPEN !== '1') {
    openUrl(url)
  }
})

process.on('SIGTERM', () => server.close())
process.on('SIGINT', () => server.close())
`
}

function otoolDependencies(binaryPath) {
  const output = execFileSync('otool', ['-L', binaryPath], { encoding: 'utf8' })
  return output
    .split('\n')
    .slice(1)
    .map((line) => line.trim().split(' ')[0])
    .filter(Boolean)
}

function isSystemLibrary(path) {
  return path.startsWith('/usr/lib/') || path.startsWith('/System/Library/')
}

function resolveDependency(dependency, sourcePath) {
  if (dependency.startsWith('@loader_path/')) {
    return join(dirname(sourcePath), dependency.slice('@loader_path/'.length))
  }
  if (dependency.startsWith('@rpath/')) {
    const name = dependency.slice('@rpath/'.length)
    const candidates = [
      join(dirname(sourcePath), name),
      join(dirname(process.execPath), '..', 'lib', name),
      join('/opt/homebrew/opt/node@24/lib', name),
      join('/opt/homebrew/opt/node/lib', name),
    ]
    return candidates.find((candidate) => existsSync(candidate)) ?? null
  }
  return dependency.startsWith('/') ? dependency : null
}

function rewriteDependency(targetPath, oldPath, libraryName) {
  execFileSync(
    'install_name_tool',
    ['-change', oldPath, `@executable_path/../Frameworks/${libraryName}`, targetPath],
    { stdio: 'ignore' },
  )
}

function copyRuntimeDependencies(entryPath, paths) {
  const copied = new Map()
  const queue = [{ source: entryPath, bundled: paths.nodePath }]

  while (queue.length > 0) {
    const current = queue.shift()
    if (!current) {
      continue
    }
    for (const dependency of otoolDependencies(current.bundled)) {
      if (isSystemLibrary(dependency)) {
        continue
      }
      const resolved = resolveDependency(dependency, current.source)
      if (!resolved || !existsSync(resolved)) {
        continue
      }
      const libraryName = basename(resolved)
      const bundledLibrary = join(paths.frameworksDir, libraryName)
      if (!copied.has(resolved)) {
        copyFileSync(resolved, bundledLibrary)
        chmodExecutable(bundledLibrary)
        copied.set(resolved, bundledLibrary)
        queue.push({ source: resolved, bundled: bundledLibrary })
      }
      rewriteDependency(current.bundled, dependency, libraryName)
    }
  }

  for (const bundledLibrary of copied.values()) {
    const libraryName = basename(bundledLibrary)
    execFileSync('install_name_tool', ['-id', `@executable_path/../Frameworks/${libraryName}`, bundledLibrary], {
      stdio: 'ignore',
    })
  }
}

function signPath(path) {
  execFileSync('codesign', ['--force', '--sign', '-', path], { stdio: 'ignore' })
}

function adHocSignApp(paths) {
  try {
    execFileSync('xattr', ['-cr', paths.appDir], { stdio: 'ignore' })
    for (const library of readdirSync(paths.frameworksDir)) {
      signPath(join(paths.frameworksDir, library))
    }
    signPath(paths.nodePath)
    signPath(paths.appDir)
    execFileSync('codesign', ['--verify', '--deep', '--strict', paths.appDir], { stdio: 'ignore' })
    return true
  } catch {
    console.warn('Ad-hoc codesign failed; the app bundle and zip were still created.')
    return false
  }
}

function writeInfoPlist(paths) {
  writeFileSync(
    join(paths.contentsDir, 'Info.plist'),
    `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Fed Chairman Game</string>
  <key>CFBundleExecutable</key>
  <string>${xmlEscape(appName)}</string>
  <key>CFBundleIdentifier</key>
  <string>local.fed-chairman-game.standalone</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Fed Chairman Game</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
`,
  )
}

function writeLauncher(paths) {
  writeFileSync(
    paths.executablePath,
    `#!/bin/zsh
set -e

APP_EXECUTABLE="$0"
APP_CONTENTS="$(cd "$(dirname "$APP_EXECUTABLE")/.." && pwd)"
exec "$APP_CONTENTS/MacOS/node" "$APP_CONTENTS/Resources/app/server.mjs"
`,
  )
  chmodExecutable(paths.executablePath)
}

function copyAppForRelease(paths) {
  if (existsSync(finalAppDir)) {
    rmSync(finalAppDir, { recursive: true, force: true })
  }
  if (existsSync(zipPath)) {
    rmSync(zipPath, { force: true })
  }
  execFileSync('ditto', ['--norsrc', '--noextattr', paths.appDir, finalAppDir], { stdio: 'ignore' })
  execFileSync('ditto', ['-c', '-k', '--keepParent', '--norsrc', '--noextattr', paths.appDir, zipPath], {
    cwd: dirname(paths.appDir),
    stdio: 'ignore',
  })
}

async function createStandaloneBundle() {
  if (process.platform !== 'darwin') {
    throw new Error('Standalone .app packaging is only supported on macOS.')
  }
  await run('npm', ['run', 'build'])

  const stagingRoot = mkdtempSync(join(tmpdir(), 'fed-chairman-game-standalone-'))
  const paths = bundlePaths(join(stagingRoot, `${appName}.app`))

  try {
    mkdirSync(paths.macOsDir, { recursive: true })
    mkdirSync(paths.frameworksDir, { recursive: true })
    mkdirSync(paths.appResourcesDir, { recursive: true })
    mkdirSync(releaseDir, { recursive: true })

    cpSync(join(projectRoot, 'dist'), join(paths.appResourcesDir, 'dist'), { recursive: true })
    copyFileSync(process.execPath, paths.nodePath)
    chmodExecutable(paths.nodePath)
    copyRuntimeDependencies(process.execPath, paths)
    writeFileSync(join(paths.appResourcesDir, 'server.mjs'), serverScript())
    writeInfoPlist(paths)
    writeLauncher(paths)

    const signed = adHocSignApp(paths)
    copyAppForRelease(paths)
    console.log(`Created ${finalAppDir}`)
    console.log(`Created ${zipPath}`)
    console.log(signed ? 'Ad-hoc signature verified in staging.' : 'Ad-hoc signature was not verified.')
  } finally {
    rmSync(stagingRoot, { recursive: true, force: true })
  }
}

function chmodExecutable(path) {
  chmodSync(path, 0o755)
}

createStandaloneBundle().catch((error) => {
  console.error(error instanceof Error ? error.message : error)
  process.exitCode = 1
})
