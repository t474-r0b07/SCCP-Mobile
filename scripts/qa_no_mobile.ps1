param(
  [switch]$SkipApkBuild,
  [switch]$IncludeWebBuild
)

$ErrorActionPreference = 'Stop'

Write-Host "[SCCP] pub get"
flutter pub get

Write-Host "[SCCP] analyze"
flutter analyze

Write-Host "[SCCP] test"
flutter test

if (-not $SkipApkBuild) {
  Write-Host "[SCCP] build apk debug"
  flutter build apk --debug
}

if ($IncludeWebBuild) {
  Write-Host "[SCCP] build web"
  flutter build web
}

Write-Host "[SCCP] QA sin movil completado"
