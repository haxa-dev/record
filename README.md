# Haxa

Ask [Haxa](https://haxa.dev) to film what a pull request changes, and to test it, when your
workflow says so: after CI passes, on a label, for the paths you choose.

Haxa's checks, **Haxa Demo** and **Haxa QA**, appear on the pull request as its runs go, whatever
the workflow does next.

## Before you start

- **The Haxa app** is installed on the repository, and the repository is in a Haxa workspace.
- **Runs start from your workflow alone** once "Runs by itself" is switched off for the repository
  in Haxa. Otherwise Haxa also runs on every pull request, and the action warns you so.

The action needs no secret: it proves which repository and pull request it's for with the
token GitHub gives the workflow, which needs `id-token: write`.

## On every pull request

```yaml
on: pull_request

permissions:
  id-token: write

jobs:
  haxa:
    runs-on: ubuntu-latest
    steps:
      - uses: haxa-dev/record@v1
```

## After CI passes

A workflow that runs after another names the pull request itself:

```yaml
on:
  workflow_run:
    workflows: [CI]
    types: [completed]

permissions:
  id-token: write

jobs:
  haxa:
    if: github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: haxa-dev/record@v1
        with:
          pull-request: ${{ github.event.workflow_run.pull_requests[0].number }}
```

## Inputs

| Input | Default | What it does |
| --- | --- | --- |
| `pipeline` | `both` | What to run: `demo`, `qa` or `both`. What isn't switched on for the repository is skipped, with a warning. |
| `wait` | `false` | Wait for the runs to end. The job succeeds once they have, whatever they found. |
| `dry-run` | `false` | Say what would start, and start nothing. A free way to check the setup. |
| `pull-request` | | The pull request's number, for a workflow on an event that names none. |
| `server` | `https://haxa.dev` | The Haxa to ask. |

## Outputs

| Output | What it is |
| --- | --- |
| `run-urls` | The runs' pages, as a JSON array, for `fromJSON`. |

## Blocking a merge on the demo

Haxa never fails a pull request. To require a demo before merging, make **Haxa Demo** a required
check in the branch's protection rules.

## Forks

GitHub gives a workflow on a fork's pull request no token, so the action can't ask for it. A
workspace's people can still start a fork's run in Haxa, where its code waits until they trust it.
