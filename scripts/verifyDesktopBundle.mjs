import { existsSync, mkdtempSync, rmSync } from 'node:fs'
import { extname, isAbsolute, join, resolve } from 'node:path'
import { tmpdir } from 'node:os'
import { execFileSync, spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname } from 'node:path'

const projectRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const appName = 'Fed Chairman Game'
const defaultDmgPath = join(projectRoot, 'release', `${appName}.dmg`)
const defaultAppPath = join(projectRoot, 'src-tauri', 'target', 'release', 'bundle', 'macos', `${appName}.app`)
const requestedDmgPath = process.argv[2]
const bundlePath = requestedDmgPath
  ? isAbsolute(requestedDmgPath)
    ? requestedDmgPath
    : resolve(process.cwd(), requestedDmgPath)
  : existsSync(defaultAppPath)
    ? defaultAppPath
    : defaultDmgPath

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

async function launchSmoke(executablePath) {
  const child = spawn(executablePath, [], {
    stdio: 'ignore',
    detached: false,
  })

  let exitCode = null
  child.on('exit', (code) => {
    exitCode = code
  })

  await sleep(3500)
  if (exitCode !== null) {
    throw new Error(`Desktop app exited during launch smoke with code ${exitCode}.`)
  }

  child.kill('SIGTERM')
  await sleep(600)
  if (exitCode === null) {
    child.kill('SIGKILL')
  }
}

async function verifyAppBundle(appPath, { stripExtendedAttributes = false } = {}) {
  const infoPlistPath = join(appPath, 'Contents', 'Info.plist')
  const executablePath = join(appPath, 'Contents', 'MacOS', 'fed-chairman-game')

  if (stripExtendedAttributes) {
    execFileSync('xattr', ['-cr', appPath], { stdio: 'ignore' })
  }
  execFileSync('plutil', ['-lint', infoPlistPath], { stdio: 'inherit' })
  execFileSync('codesign', ['--verify', '--deep', '--strict', '--verbose=2', appPath], { stdio: 'inherit' })
  await launchSmoke(executablePath)

  console.log(`Verified ${appPath}`)
}

async function verifyDmgBundle(dmgPath) {
  const mountPoint = mkdtempSync(join(tmpdir(), 'fed-chairman-desktop-dmg-'))
  let attached = false

  try {
    execFileSync('hdiutil', ['verify', dmgPath], { stdio: 'inherit' })
    execFileSync('hdiutil', ['attach', '-nobrowse', '-readonly', '-mountpoint', mountPoint, dmgPath], {
      stdio: 'inherit',
    })
    attached = true

    const appPath = join(mountPoint, `${appName}.app`)
    await verifyAppBundle(appPath)
    console.log(`Verified ${dmgPath}`)
  } finally {
    if (attached) {
      execFileSync('hdiutil', ['detach', mountPoint], { stdio: 'ignore' })
    }
    rmSync(mountPoint, { recursive: true, force: true })
  }
}

async function verifyDesktopBundle() {
  if (process.platform !== 'darwin') {
    throw new Error('Desktop bundle verification is only supported on macOS.')
  }
  if (!existsSync(bundlePath)) {
    throw new Error(`Missing ${bundlePath}. Run npm run build or npm run package:mac first.`)
  }

  if (bundlePath.endsWith('.app')) {
    await verifyAppBundle(bundlePath, { stripExtendedAttributes: true })
    return
  }

  if (extname(bundlePath) === '.dmg') {
    await verifyDmgBundle(bundlePath)
    return
  }

  throw new Error(`Unsupported desktop bundle type: ${bundlePath}`)
}

verifyDesktopBundle().catch((error) => {
  console.error(error instanceof Error ? error.message : error)
  process.exitCode = 1
})
