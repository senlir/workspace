param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('start', 'continue', 'status')]
    [string]$Action,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$Value
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$python = Join-Path $root '.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $python)) {
    throw "Workflow environment not found. Run: py -3 -m venv .venv"
}

Push-Location $root
try {
    switch ($Action) {
        'start' {
            & $python -m tools.dev_workflow.cli start $Value --provider minimax --auto-review --apply
        }
        'continue' {
            & $python -m tools.dev_workflow.cli continue $Value
        }
        'status' {
            & $python -m tools.dev_workflow.cli status $Value
        }
    }
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
