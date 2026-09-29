"""Windows Office conversion in a private, bounded worker process."""

import json
import subprocess
from pathlib import Path


SCRIPT = r'''
param([string]$InputPath,[string]$PdfPath,[string]$OwnerPath)
$ErrorActionPreference='Stop'
$app=$null; $doc=$null; $owned=$false
$kind=[IO.Path]::GetExtension($InputPath).ToLowerInvariant()
$name=@{'.docx'='WINWORD';'.xlsx'='EXCEL';'.pptx'='POWERPNT'}[$kind]
if (!$name) { throw 'Unsupported Office format' }
if (Get-Process -Name $name -ErrorAction SilentlyContinue) { throw 'office_busy: close the existing Office application or use LibreOffice' }
$started=[DateTime]::UtcNow
try {
  $prog=@{'.docx'='Word.Application';'.xlsx'='Excel.Application';'.pptx'='PowerPoint.Application'}[$kind]
  $app=New-Object -ComObject $prog
  $owners=@(Get-Process -Name $name | Where-Object {$_.StartTime.ToUniversalTime() -ge $started})
  if ($owners.Count -ne 1) { throw 'Office ownership could not be verified' }
  $owner=$owners[0]; $ownerId=$owner.Id
  $owned=$true
  @{id=$ownerId; name=$name; ticks=$owner.StartTime.ToUniversalTime().Ticks} | ConvertTo-Json -Compress | Set-Content -LiteralPath $OwnerPath -Encoding UTF8
  $app.AutomationSecurity=3
  if ($kind -eq '.docx') {
    $app.Visible=$false; $app.DisplayAlerts=0
    $doc=$app.Documents.Open($InputPath,$false,$true,$false)
    $doc.ExportAsFixedFormat($PdfPath,17)
  } elseif ($kind -eq '.xlsx') {
    $app.Visible=$false; $app.DisplayAlerts=$false; $app.AskToUpdateLinks=$false
    $doc=$app.Workbooks.Open($InputPath,0,$true)
    $doc.ExportAsFixedFormat(0,$PdfPath)
  } else {
    $app.DisplayAlerts=1
    $doc=$app.Presentations.Open($InputPath,$true,$false,$false)
    $doc.SaveAs($PdfPath,32)
  }
} finally {
  if ($doc) {
    try { if ($kind -eq '.pptx') {$doc.Close()} else {$doc.Close($false)} } catch {}
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($doc)
  }
  if ($app -and $owned) { try {$app.Quit()} catch {} }
  if ($app) {[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($app)}
  [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
'''

_CLEANUP = r'''
param([string]$OwnerPath)
if (!(Test-Path -LiteralPath $OwnerPath)) {exit 0}
$v=Get-Content -LiteralPath $OwnerPath -Raw | ConvertFrom-Json
$p=Get-Process -Id ([int]$v.id) -ErrorAction SilentlyContinue
if ($p -and $p.ProcessName -eq $v.name -and $p.StartTime.ToUniversalTime().Ticks -eq [long]$v.ticks) {
 Stop-Process -Id $p.Id -Force
}
'''


def convert(source: Path, pdf: Path, scratch: Path, powershell: str, timeout: float = 75) -> None:
    script = scratch / "office-convert.ps1"
    script.write_text(SCRIPT, encoding="utf-8-sig")
    owner = scratch / "office-owner.json"
    cleanup = scratch / "office-cleanup.ps1"
    cleanup.write_text(_CLEANUP, encoding="utf-8-sig")
    base = [powershell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File"]
    try:
        result = subprocess.run(base + [str(script), "-InputPath", str(source), "-PdfPath", str(pdf),
                                       "-OwnerPath", str(owner)], capture_output=True, text=True,
                                errors="replace", timeout=timeout,
                                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if result.returncode:
            detail = (result.stderr or result.stdout or "Office conversion failed")[-1200:]
            raise RuntimeError(detail)
    finally:
        # Never kill an existing user's Office process: match the worker-owned PID and creation time.
        if owner.exists():
            record = json.loads(owner.read_text(encoding="utf-8-sig"))
            if record.get("name") in {"WINWORD", "EXCEL", "POWERPNT"} and isinstance(record.get("id"), int):
                subprocess.run(base + [str(cleanup), "-OwnerPath", str(owner)], capture_output=True,
                               timeout=10, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
