import { existsSync, mkdtempSync, rmSync } from 'node:fs'
import { isAbsolute, join, resolve } from 'node:path'
import { tmpdir } from 'node:os'
import { execFileSync, spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname } from 'node:path'

const projectRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const appName = 'Fed Chairman Game'
const defaultDmgPath = join(projectRoot, 'release', `${appName}.dmg`)
const tauriDmgPath = join(projectRoot, 'src-tauri', 'target', 'release', 'bundle', 'dmg', `${appName}_0.1.0_aarch64.dmg`)
const requestedDmgPath = process.argv[2]
const dmgPath = requestedDmgPath
  ? isAbsolute(requestedDmgPath)
    ? requestedDmgPath
    : resolve(process.cwd(), requestedDmgPath)
  : existsSync(defaultDmgPath)
    ? defaultDmgPath
    : tauriDmgPath

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

async function verifyDesktopBundle() {
  if (process.platform !== 'darwin') {
    throw new Error('Desktop bundle verification is only supported on macOS.')
  }
  if (!existsSync(dmgPath)) {
    throw new Error(`Missing ${dmgPath}. Run npm run desktop:build first.`)
  }

  const mountPoint = mkdtempSync(join(tmpdir(), 'fed-chairman-desktop-dmg-'))
  let attached = false

  try {
    execFileSync('hdiutil', ['verify', dmgPath], { stdio: 'inherit' })
    execFileSync('hdiutil', ['attach', '-nobrowse', '-readonly', '-mountpoint', mountPoint, dmgPath], {
      stdio: 'inherit',
    })
    attached = true

    const appPath = join(mountPoint, `${appName}.app`)
    const infoPlistPath = join(appPath, 'Contents', 'Info.plist')
    const executablePath = join(appPath, 'Contents', 'MacOS', 'fed-chairman-game')

    execFileSync('plutil', ['-lint', infoPlistPath], { stdio: 'inherit' })
    execFileSync('codesign', ['--verify', '--deep', '--strict', '--verbose=2', appPath], { stdio: 'inherit' })
    await launchSmoke(executablePath)

    console.log(`Verified ${dmgPath}`)
  } finally {
    if (attached) {
      execFileSync('hdiutil', ['detach', mountPoint], { stdio: 'ignore' })
    }
    rmSync(mountPoint, { recursive: true, force: true })
  }
}

verifyDesktopBundle().catch((error) => {
  console.error(error instanceof Error ? error.message : error)
  process.exitCode = 1
})
