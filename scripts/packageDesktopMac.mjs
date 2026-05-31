import { existsSync, mkdtempSync, mkdirSync, rmSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { tmpdir } from 'node:os'
import { execFileSync, spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const projectRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const appName = 'Fed Chairman Game'
const builtAppPath = join(projectRoot, 'src-tauri', 'target', 'release', 'bundle', 'macos', `${appName}.app`)
const releaseDir = join(projectRoot, 'release')
const releaseDmgPath = join(releaseDir, `${appName}.dmg`)

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

function signCleanApp(appPath) {
  const executablePath = join(appPath, 'Contents', 'MacOS', 'fed-chairman-game')
  execFileSync('xattr', ['-cr', appPath], { stdio: 'ignore' })
  execFileSync('codesign', ['--force', '--sign', '-', executablePath], { stdio: 'inherit' })
  execFileSync('codesign', ['--force', '--deep', '--sign', '-', appPath], { stdio: 'inherit' })
  execFileSync('codesign', ['--verify', '--deep', '--strict', '--verbose=2', appPath], { stdio: 'inherit' })
}

function createCleanDmg(stagedAppPath, stagingRoot) {
  if (existsSync(releaseDmgPath)) {
    rmSync(releaseDmgPath, { force: true })
  }

  signCleanApp(stagedAppPath)
  execFileSync(
    'hdiutil',
    ['create', '-ov', '-format', 'UDZO', '-volname', appName, '-srcfolder', stagingRoot, releaseDmgPath],
    { stdio: 'inherit' },
  )
}

async function packageDesktopMac() {
  if (process.platform !== 'darwin') {
    throw new Error('Desktop DMG packaging is only supported on macOS.')
  }

  await run('npm', ['run', 'desktop:build'])
  if (!existsSync(builtAppPath)) {
    throw new Error(`Expected ${builtAppPath} after desktop build.`)
  }

  mkdirSync(releaseDir, { recursive: true })
  const stagingRoot = mkdtempSync(join(tmpdir(), 'fed-chairman-desktop-release-'))
  const stagedAppPath = join(stagingRoot, `${appName}.app`)

  try {
    execFileSync('ditto', ['--norsrc', '--noextattr', builtAppPath, stagedAppPath], { stdio: 'inherit' })
    createCleanDmg(stagedAppPath, stagingRoot)
    await run('npm', ['run', 'desktop:verify', '--', releaseDmgPath])
    console.log(`Created ${releaseDmgPath}`)
  } finally {
    rmSync(stagingRoot, { recursive: true, force: true })
  }
}

packageDesktopMac().catch((error) => {
  console.error(error instanceof Error ? error.message : error)
  process.exitCode = 1
})
