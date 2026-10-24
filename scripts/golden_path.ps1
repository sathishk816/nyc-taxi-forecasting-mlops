$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$python = ".\.venv\Scripts\python.exe"
if (-not (Test-Path $python)) {
    throw "Python virtual environment not found."
}

function Run-Step {
    param([string]$Name, [string[]]$Arguments)

    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    & $python @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }

    Write-Host "PASS: $Name" -ForegroundColor Green
}

Write-Host "NYC TAXI FORECASTING - GOLDEN PATH VERIFICATION" -ForegroundColor Yellow

foreach ($file in @(
    "data\processed\pipeline_summary.json",
    "data\raw\taxi_zone_lookup.csv",
    "docs\model_cards\demand.md",
    "docs\model_cards\fare.md",
    "artifacts\responsible\demand_fairness.json",
    "artifacts\responsible\fare_fairness.json"
)) {
    if (-not (Test-Path $file)) {
        throw "Required artifact missing: $file"
    }
    Write-Host "PASS: $file"
}

Run-Step "MLflow model registry" @(
    "-c",
    "import mlflow; from mlflow.tracking import MlflowClient; mlflow.set_tracking_uri('sqlite:///mlflow.db'); c=MlflowClient(); names=['taxi-demand-forecaster','taxi-fare-predictor']; [(print(n, 'versions:', len(c.search_model_versions('name=' + chr(34) + n + chr(34)))), None) for n in names]; assert all(c.search_model_versions('name=' + chr(34) + n + chr(34)) for n in names)"
)

Run-Step "Batch demand forecasting" @(
    "-m", "scripts.batch_forecast", "--horizon", "2"
)

Run-Step "Feature drift monitoring" @(
    "-m", "scripts.monitoring.demo_drift_report",
    "--problem", "all", "--mode", "drift"
)

Write-Host "`n=== FastAPI health ===" -ForegroundColor Cyan
$health = Invoke-RestMethod -Uri "http://127.0.0.1:8000/health" -TimeoutSec 15
if ($health.status -ne "ok" -or
    -not $health.demand_model_loaded -or
    -not $health.fare_model_loaded) {
    throw "FastAPI health verification failed."
}
Write-Host "PASS: FastAPI healthy; both models loaded." -ForegroundColor Green

Write-Host "`nGOLDEN PATH VERIFICATION PASSED" -ForegroundColor Green
