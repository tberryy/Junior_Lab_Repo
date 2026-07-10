<#
.SYNOPSIS
    Walks an organized data tree (output of Organize-DataDir.ps1) and pulls the
    test date (yyyymmdd) out of the CSV filenames, e.g.:

        TENSION_20260423_111551_2.csv  ->  2026-04-23

    Prints one line per CRN with its date(s). Optionally writes a CSV.

.EXAMPLE
    .\Get-CrnDates.ps1 -OrganizedRoot ".\2026_organized"
    .\Get-CrnDates.ps1 -OrganizedRoot ".\2026_organized" -OutCsv ".\crn_dates.csv"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OrganizedRoot,

    # Optional: also write the results to a CSV file
    [string]$OutCsv
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $OrganizedRoot -PathType Container)) {
    throw "Organized data folder not found: $OrganizedRoot"
}

# Sample folders look like <day>_<crn>, e.g. monday_10446
$sampleDirs = Get-ChildItem -LiteralPath $OrganizedRoot -Recurse -Directory |
    Where-Object { $_.Name -match '^[A-Za-z]+_\d+$' } |
    Sort-Object Name

$results = New-Object System.Collections.Generic.List[object]

foreach ($dir in $sampleDirs) {
    $null = $dir.Name -match '^([A-Za-z]+)_(\d+)$'
    $day  = $Matches[1]
    $crn  = $Matches[2]

    # Collect every yyyymmdd found in CSV filenames under this sample
    $dates = @{}
    $csvs = Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Filter '*.csv' -ErrorAction SilentlyContinue
    foreach ($csv in $csvs) {
        if ($csv.Name -match '_((19|20)\d{6})_') {
            $raw = $Matches[1]
            $pretty = "$($raw.Substring(0,4))-$($raw.Substring(4,2))-$($raw.Substring(6,2))"
            $dates[$pretty] = $true
        }
    }

    $dateList = @($dates.Keys | Sort-Object)
    if ($dateList.Count -eq 0) { $dateStr = 'NO DATA FILES' }
    else                       { $dateStr = $dateList -join ', ' }

    $results.Add([pscustomobject]@{
        CRN   = $crn
        Day   = $day
        Dates = $dateStr
        Files = $csvs.Count
    })
}

if ($results.Count -eq 0) {
    Write-Host "No sample folders (like monday_10446) found under $OrganizedRoot"
    return
}

# Sort by (first) date, oldest first; undated last
$sorted = $results | Sort-Object @{ Expression = {
    if ($_.Dates -eq 'NO DATA FILES') { 'zzzz' } else { $_.Dates }
} }

$sorted | Format-Table CRN, Day, Dates, Files -AutoSize

if ($OutCsv) {
    $sorted | Export-Csv -LiteralPath $OutCsv -NoTypeInformation
    Write-Host "Written: $OutCsv" -ForegroundColor Green
}
