#!/usr/bin/env pwsh
# Author: Jim JMcDonald
# GitHub source: https://github.com/Jim-JMCD/Genfrn/tree/main
# PowerShell conversion

# Display usage
function Show-Usage {
    @"
Genfrn - Generic File Renamer
genFRN renames generic meaningless names of files by prefixing the names of parent directories to existing names. 

Once the files have been renamed they can be moved, backed up etc without relying upon the directory structure to give them meaning. 

Useful for directories that only contain many files with generic names like
   image-00204.jpg
   log.202505261809
   scan_056.pdf
and given context by their parent directories.

USAGE
   genFRN.ps1 <parent level> [input directory]

   <parent level>    Number of parent directories to include. (1 - 4, mandatory)
   [input directory] Directory to process (Default: current directory).

NOTES
All files in the directory are renamed.
Directories and hidden files are ignored. 

Example of setting the parent level for ../image-067.jpg 

Parent Level           Resulting File Name
  1                      Tue_image-067.jpg
  2                Week4_Tue_image-067.jpg
  3            May_Week4_Tue_image-067.jpg
  4       2025_May_Week4_Tue_image-067.jpg

* The script is not recursive, it only renames all the files in the given directory.
* If the script parent level exceeds the number of parent levels, the script will use all that it can.
* Files in root directories cannot be renamed because there is no parent directory.

HOW TO UNDO the renaming.
In the input directory a log file is created. The log file is an executable undo script. 
To recover run the log/undo file: ./genFRN_log_<YYYYMMDD-hhmm-ss>.ps1

Where <YYYYMMDD-hhmm-ss> is the date-time of log file creation. When the undo is complete remove the log file.

Any changes made to the directory contents after the renaming has completed could interfere with the recovery process.
If you abort while renaming, the log file can be used to undo any renaming up to time of the bail out.

NOTE: If you abort during renaming, clean up is manual.

SAFETY
Always review the preview before confirming.
Avoid running in system directories (e.g. C:\Windows, C:\Program Files).

"@
}

function Ask-YesNo {
    param([string]$Question)
    
    do {
        $answer = Read-Host "$Question [y/n]"
        switch ($answer.ToLower()) {
            'y' { return $true }
            'n' { return $false }
            default { Write-Host "Please answer y or n." }
        }
    } while ($true)
}

# Organise the log/undo file
function New-UndoLog {
    param([string]$LogTmp, [string]$InputDir)
    
    if ($LogTmp -and (Test-Path $LogTmp)) {
        $logFile = Join-Path $InputDir "genFRN_log_$(Get-Date -Format 'yyyyMMdd-HHmmss').ps1"
        @"
# Undo script for genFRN
# PowerShell undo script

"@ | Set-Content $logFile
        
        Get-Content $LogTmp | Add-Content $logFile
        Remove-Item $LogTmp
        Write-Host "`nTo UNDO run: $logFile"
    }
}

# Main script
if ($args[0] -eq "--help") {
    Show-Usage
    exit 0
}

if ($args.Count -lt 1 -or $args.Count -gt 2) {
    Show-Usage
    Write-Host "Error: Invalid number of arguments." -ForegroundColor Red
    exit 1
}

if ($args[0] -notmatch '^[1-4]$') {
    Write-Host "Error: Parent level must be 1, 2, 3, or 4." -ForegroundColor Red
    exit 1
}

$parentLevel = [int]$args[0]
$inputDir = if ($args[1]) { $args[1] } else { $PWD.Path }

if (-not (Test-Path $inputDir -PathType Container)) {
    Write-Host "Error: Directory '$inputDir' does not exist." -ForegroundColor Red
    exit 1
}

# Resolve full path and check for root directories
try {
    $inputDir = Convert-Path $inputDir
} catch {
    Write-Host "Error: Cannot resolve path '$inputDir'." -ForegroundColor Red
    exit 1
}

if ($inputDir -eq [System.IO.Path]::GetPathRoot($inputDir)) {
    Write-Host "Error: Cannot rename files in the root directory." -ForegroundColor Red
    exit 1
}

# Build prefix list
$dir = $inputDir
$parents = @()

for ($i = 0; $i -lt $parentLevel; $i++) {
    $dirName = Split-Path $dir -Leaf
    if ($dirName -eq "" -or $dir -eq [System.IO.Path]::GetPathRoot($dir)) {
        break
    }
    $parents += $dirName
    $dir = Split-Path $dir -Parent
}

[array]::Reverse($parents)
$prefix = $parents -join "_"

# Preview changes
Write-Host "`nPreview of changes:" -ForegroundColor Yellow
Write-Host "=" * 60

$files = Get-ChildItem -Path $inputDir -File | Where-Object { -not $_.Name.StartsWith(".") }

foreach ($file in $files) {
    $newName = "${prefix}_$($file.Name)"
    Write-Host ("{0,-30} -> {1,-30}" -f $file.Name, $newName)
}

if (-not (Ask-YesNo "Proceed with renaming?")) {
    Write-Host "Aborted - nothing changed" -ForegroundColor Yellow
    exit 0
}

if (-not (Ask-YesNo "ARE YOU SURE (If you ABORT once started clean up is manual) ?")) {
    Write-Host "Aborted - nothing changed" -ForegroundColor Yellow
    exit 0
}

# Create temporary log file
$logTmp = "genFRN_tmp_log_$(Get-Date -Format 'yyyyMMdd-HHmmss').ps1"

Write-Host "`nRenaming files..." -ForegroundColor Green

foreach ($file in $files) {
    $newName = "${prefix}_$($file.Name)"
    $newPath = Join-Path $file.Directory $newName
    
    try {
        Rename-Item -Path $file.FullName -NewName $newName
        Write-Host ("{0,-30} -> {1,-30}" -f $file.Name, $newName)
        "Rename-Item '$newName' '$($file.Name)'" | Add-Content $logTmp
    } catch {
        Write-Host "Error renaming $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nRenaming complete." -ForegroundColor Green

# Create final undo log
New-UndoLog -LogTmp $logTmp -InputDir $inputDir