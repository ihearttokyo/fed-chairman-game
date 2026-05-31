import { expect, test, type Page } from '@playwright/test'
import AxeBuilder from '@axe-core/playwright'
import { readFile, writeFile } from 'node:fs/promises'

async function expectNoSeriousA11yViolations(page: Page): Promise<void> {
  const results = await new AxeBuilder({ page }).analyze()
  const serious = results.violations.filter((violation) => violation.impact === 'serious' || violation.impact === 'critical')
  expect(serious).toEqual([])
}

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth + 1)
  expect(hasOverflow).toBe(false)
}

async function downloadFile(page: Page, name: string): Promise<string> {
  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.getByRole('button', { name, exact: true }).click(),
  ])
  const downloadPath = await download.path()
  expect(downloadPath).not.toBeNull()
  return downloadPath!
}

async function downloadText(page: Page, name: string): Promise<string> {
  return readFile(await downloadFile(page, name), 'utf8')
}

const policyButtons = {
  hold: /Hold; .*commit and advance one quarter/,
  cut25: /-25 bps; .*commit and advance one quarter/,
  raise25: /\+25 bps; .*commit and advance one quarter/,
} as const

async function playPolicyPath(page: Page, path: Array<keyof typeof policyButtons>): Promise<void> {
  for (const action of path) {
    const intended = page.getByRole('button', { name: policyButtons[action] })
    if (await intended.isEnabled()) {
      await intended.click()
      continue
    }
    await page.getByRole('button', { name: policyButtons.hold }).click()
  }
}

async function playHoldQuarters(page: Page, count: number): Promise<void> {
  for (let index = 0; index < count; index += 1) {
    const resultHeading = page.getByRole('heading', { name: /Reappointed|Not reappointed|Career complete/ })
    if (await resultHeading.isVisible()) {
      return
    }
    const hold = page.getByRole('button', { name: policyButtons.hold })
    await expect(hold).toBeEnabled()
    await hold.click()
    if (index + 1 >= 16) {
      await expect(page.getByRole('heading', { name: /Reappointed|Not reappointed|Career complete/ })).toBeVisible()
      return
    }
    await expect(page.getByText(`Quarter ${index + 1} of 16`)).toBeVisible()
  }
}

test('player can complete a full classic term and inspect exports', async ({ page }) => {
  test.setTimeout(45_000)
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'Classic Monetary Policy Mode' })).toBeVisible()
  await expectNoSeriousA11yViolations(page)
  await expectNoHorizontalOverflow(page)
  await page.getByRole('button', { name: 'Start term' }).click()
  await expect(page.getByRole('heading', { name: 'Policy Lever' })).toBeVisible()
  await expect(page.getByText('One-click decisions')).toBeHidden()
  await expect(page.locator('.commit-preview')).toHaveCount(0)
  await expect(page.locator('.policy-commit-map')).toHaveCount(0)
  const bpsStackFits = await page.locator('.policy-bps-stack').evaluate((node) => node.scrollWidth <= node.clientWidth + 1)
  expect(bpsStackFits).toBe(true)
  await expect(page.getByLabel('Full career policy path summary')).toBeVisible()
  await expect(page.getByLabel('Custom bps')).toBeVisible()
  const newsBeforeChart = await page.evaluate(() => {
    const news = document.querySelector('#news-title')?.closest('section')
    const chart = document.querySelector('#chart-title')?.closest('section')
    if (!news || !chart) {
      return false
    }
    return Boolean(news.compareDocumentPosition(chart) & Node.DOCUMENT_POSITION_FOLLOWING)
  })
  expect(newsBeforeChart).toBe(true)
  await expectNoSeriousA11yViolations(page)

  await page.getByRole('button', { name: 'Table' }).click()
  await expect(page.getByRole('table', { name: 'Quarterly macroeconomic history' })).toBeVisible()
  await expectNoSeriousA11yViolations(page)
  await page.getByRole('button', { name: 'Chart' }).click()

  await playHoldQuarters(page, 16)

  await expect(page.getByText(/Term \d+ complete|Career: \d+ quarters/)).toBeVisible()
  await expect(page.getByRole('heading', { name: /Reappointed|Not reappointed/ })).toBeVisible()
  await expectNoSeriousA11yViolations(page)
  const csv = await downloadText(page, 'CSV')
  const json = await downloadText(page, 'JSON')
  const markdown = await downloadText(page, 'Markdown')
  expect(csv.trim().split('\n')).toHaveLength(18)
  expect(json).toMatch(/"status": "(term_debrief|not_reappointed)"/)
  expect(markdown).toContain('Classic Monetary Policy Debrief')
  await expect(page.getByRole('button', { name: /Advance quarter/ })).toBeHidden()
})

test('custom basis-point decision commits once and keeps cockpit stable', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('button', { name: 'Start term' }).click()
  await page.getByLabel('Custom bps').fill('+37')
  await page.getByRole('button', { name: /Custom \+37 bps to 4\.37%; commit and advance one quarter/ }).click()

  await expect(page.getByText('Quarter 1 of 16')).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Quarter Review' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Policy Lever' })).toBeInViewport()
  await expectNoHorizontalOverflow(page)
})

test('dark cockpit theme is persistent, legible, and stable', async ({ page }) => {
  await page.goto('/')
  const themeSwitch = page.getByRole('switch', { name: 'Use dark cockpit theme' })
  await expect(themeSwitch).toBeVisible()
  await themeSwitch.check()
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark')
  await expectNoSeriousA11yViolations(page)
  await expectNoHorizontalOverflow(page)

  await page.getByRole('button', { name: 'Start term' }).click()
  await expect(page.getByRole('heading', { name: 'Policy Lever' })).toBeVisible()
  await expect(page.getByRole('switch', { name: 'Use dark cockpit theme' })).toBeChecked()
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark')
  await expectNoHorizontalOverflow(page)

  const surfaceColors = await page.evaluate(() => {
    const chart = document.querySelector('.chart-frame')
    const policy = document.querySelector('.policy-button')
    if (!(chart instanceof HTMLElement) || !(policy instanceof HTMLElement)) {
      return null
    }
    return {
      chart: getComputedStyle(chart).backgroundColor,
      policyText: getComputedStyle(policy).color,
    }
  })
  expect(surfaceColors).not.toBeNull()
  expect(surfaceColors?.chart).not.toBe('rgb(255, 254, 251)')
  expect(surfaceColors?.policyText).not.toBe('rgb(18, 26, 24)')

  await page.reload()
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark')
})

test('reappointed player can continue a new term and retire at a later debrief', async ({ page }) => {
  test.setTimeout(45_000)
  const firstTermPath: Array<keyof typeof policyButtons> = [
    'raise25',
    'raise25',
    'hold',
    'hold',
    'hold',
    'cut25',
    'cut25',
    'hold',
    'hold',
    'hold',
    'hold',
    'hold',
    'cut25',
    'hold',
    'raise25',
    'hold',
  ]
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.goto('/')
  await page.getByLabel('Shared seed').fill('raiseEarly')
  await page.getByRole('button', { name: 'Start term' }).click()
  await playPolicyPath(page, firstTermPath)

  await expect(page.getByText('Term 1 complete')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Continue next term' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Retire with final score' })).toBeHidden()

  await page.getByRole('button', { name: 'Continue next term' }).click()
  await expect(page.getByText('Term 2', { exact: true })).toBeVisible()
  await expect(page.getByText('Quarter 0 of 16')).toBeVisible()
  await page.getByRole('button', { name: 'Table' }).click()
  await expect(page.getByRole('cell', { name: 'T1 Q16' })).toBeVisible()
  await expect(page.getByRole('cell', { name: 'T2 start' })).toBeVisible()
  await page.getByRole('button', { name: 'Chart' }).click()
  await page.evaluate(() => {
    const raw = window.localStorage.getItem('fed-chairman-classic-v1')
    if (!raw) {
      throw new Error('Missing saved session')
    }
    const save = JSON.parse(raw) as { session: { [key: string]: unknown; completedTerms: unknown[] } }
    const firstTerm = save.session.completedTerms[0] as {
      [key: string]: unknown
      endingState: unknown
      history: unknown
      decisions: unknown
      traces: unknown
      score: unknown
    }
    save.session.status = 'term_debrief'
    save.session.termNumber = 2
    save.session.currentTermQuarter = 16
    save.session.totalCareerQuarters = 32
    save.session.completedTerms = [
      firstTerm,
      {
        ...firstTerm,
        termNumber: 2,
      },
    ]
    save.session.current = firstTerm.endingState
    save.session.history = firstTerm.history
    save.session.decisions = firstTerm.decisions
    save.session.traces = firstTerm.traces
    save.session.score = firstTerm.score
    save.session.careerScore = firstTerm.score
    window.localStorage.setItem('fed-chairman-classic-v1', JSON.stringify(save))
  })
  await page.reload()
  await page.getByRole('button', { name: 'Resume saved term' }).click()
  await expect(page.getByText('Term 2 complete')).toBeVisible()
  await page.getByRole('button', { name: 'Retire with final score' }).click()
  await expect(page.getByRole('heading', { name: 'Career complete' })).toBeVisible()
  await expect(page.getByText('Career: 32 quarters')).toBeVisible()
  await expectNoHorizontalOverflow(page)

  const markdown = await downloadText(page, 'Markdown')
  expect(markdown).toContain('Terms completed: 2')
  expect(markdown).toContain('Career score:')
})

test('portable save files download, load, and reject tampering', async ({ page }, testInfo) => {
  await page.goto('/')
  await page.getByRole('button', { name: 'Start term' }).click()
  await page.getByRole('button', { name: /Hold; .*commit and advance one quarter/ }).click()

  const savePath = await downloadFile(page, 'Save')
  const saveText = await readFile(savePath, 'utf8')
  expect(saveText).toContain('"digest"')

  await page.evaluate(() => window.localStorage.clear())
  await page.reload()
  await expect(page.getByRole('heading', { name: 'Classic Monetary Policy Mode' })).toBeVisible()
  await page.getByLabel('Load Fed Chairman save file').setInputFiles(savePath)
  await expect(page.getByText('Quarter 1 of 16')).toBeVisible()

  const tampered = JSON.parse(saveText) as { payload: { current: { inflation: number } } }
  tampered.payload.current.inflation += 1
  const tamperedPath = testInfo.outputPath('tampered.fedchair-save.json')
  await writeFile(tamperedPath, JSON.stringify(tampered), 'utf8')
  await page.getByLabel('Load Fed Chairman save file').setInputFiles(tamperedPath)
  await expect(page.getByText('Save file failed integrity check.')).toBeVisible()
})

test('keyboard shortcuts commit and advance a decision', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('button', { name: 'Start term' }).click()
  await page.keyboard.press('KeyR')
  await expect(page.getByText('Quarter 1 of 16')).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Three-month transmission' })).toBeVisible()
})

test('hold policy button clearly commits one quarter', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('button', { name: 'Start term' }).click()

  await page.getByRole('button', { name: /Hold; .*commit and advance one quarter/ }).click()

  await expect(page.getByText('Quarter 1 of 16')).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Three-month transmission' })).toBeVisible()
})

test('saved sessions resume after reload', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('button', { name: 'Start term' }).click()
  await page.getByRole('button', { name: /Hold; .*commit and advance one quarter/ }).click()
  await page.reload()

  await page.getByRole('button', { name: 'Resume saved term' }).click()

  await expect(page.getByText('Quarter 1 of 16')).toBeVisible()
})

test('sound fails closed when Web Audio is unavailable', async ({ page }) => {
  await page.goto('/')
  await page.evaluate(() => {
    Object.defineProperty(window, 'AudioContext', { configurable: true, value: undefined })
    Object.defineProperty(window, 'webkitAudioContext', { configurable: true, value: undefined })
  })
  await page.getByRole('button', { name: 'Start term' }).click()

  const soundButton = page.getByRole('button', { name: 'Sound' })
  await soundButton.click()

  await expect(soundButton).toHaveAttribute('aria-pressed', 'false')
})

test('reduced motion keeps quarter advancement out of animated phase', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.goto('/')
  await page.getByRole('button', { name: 'Start term' }).click()
  await page.getByRole('button', { name: /Hold; .*commit and advance one quarter/ }).click()

  await expect(page.locator('main')).not.toHaveClass(/phase-advancing/)
  await expect(page.getByRole('heading', { name: 'Three-month transmission' })).toBeVisible()
  await expectNoHorizontalOverflow(page)
})
