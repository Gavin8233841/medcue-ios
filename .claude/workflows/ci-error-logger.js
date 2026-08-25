export const meta = {
  name: 'ci-error-logger',
  description: 'Automatically analyze and log CI failures to memory for future prevention',
  phases: [
    { title: 'Fetch', detail: 'Get CI failure logs from GitHub' },
    { title: 'Analyze', detail: 'Extract root cause and pattern' },
    { title: 'Record', detail: 'Save to memory with prevention guidance' },
  ],
}

phase('Fetch')
const prNumber = args.prNumber
const repoOwner = args.repoOwner || 'Gavin8233841'
const repoName = args.repoName || 'medcue-ios'

log(`Fetching CI failure details for PR #${prNumber}`)

const checksResult = await agent(
  `Run: gh pr checks ${prNumber} --repo ${repoOwner}/${repoName}

  Extract the failed check names and their URLs. Return as JSON array with:
  - checkName
  - runId (extract from URL)
  - jobId (extract from URL)`,
  {
    label: 'Get failed checks',
    phase: 'Fetch',
    schema: {
      type: 'object',
      properties: {
        failedChecks: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              checkName: { type: 'string' },
              runId: { type: 'string' },
              jobId: { type: 'string' },
            },
            required: ['checkName', 'runId'],
          },
        },
      },
      required: ['failedChecks'],
    },
  }
)

if (!checksResult || checksResult.failedChecks.length === 0) {
  log('No failed checks found')
  return { status: 'no_failures' }
}

phase('Analyze')

const analyses = await parallel(
  checksResult.failedChecks.map(check => async () => {
    return await agent(
      `Analyze this CI failure for ${check.checkName}:

      Run: gh run view ${check.runId} --repo ${repoOwner}/${repoName} --log-failed

      Extract:
      1. Root cause (the actual error, not symptoms)
      2. Error category (trailing-whitespace, build-error, test-failure, permission-issue, etc)
      3. Specific trigger (what file/code/action caused it)
      4. Prevention rule (how to avoid this in the future)

      Be specific and actionable. If it's a build error, include the exact file and line.`,
      {
        label: `Analyze ${check.checkName}`,
        phase: 'Analyze',
        schema: {
          type: 'object',
          properties: {
            rootCause: { type: 'string' },
            category: { type: 'string' },
            trigger: { type: 'string' },
            preventionRule: { type: 'string' },
          },
          required: ['rootCause', 'category', 'trigger', 'preventionRule'],
        },
      }
    )
  })
)

const validAnalyses = analyses.filter(Boolean)

if (validAnalyses.length === 0) {
  log('Could not analyze any failures')
  return { status: 'analysis_failed' }
}

phase('Record')

const memoryPath = 'C:\\Users\\Lenovo\\.claude\\projects\\D-----medcue\\memory'

for (const analysis of validAnalyses) {
  const slug = analysis.category.toLowerCase().replace(/[^a-z0-9]+/g, '-')
  const filename = `feedback_ci_${slug}.md`

  await agent(
    `Create or update memory file at: ${memoryPath}/${filename}

    Content:
    ---
    name: ci-${slug}
    description: CI failure: ${analysis.category}
    metadata:
      type: feedback
    ---

    ${analysis.rootCause}

    **Why:** ${analysis.trigger}

    **How to apply:** ${analysis.preventionRule}

    Use the Write tool to create this file. If it already exists, read it first and append the new information if it's a different case.`,
    {
      label: `Record ${analysis.category}`,
      phase: 'Record',
    }
  )
}

log(`Recorded ${validAnalyses.length} CI failure patterns to memory`)

return {
  status: 'success',
  recordedCount: validAnalyses.length,
  categories: validAnalyses.map(a => a.category),
}
