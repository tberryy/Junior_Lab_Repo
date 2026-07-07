<#
.SYNOPSIS
    Takes a flat "data" folder full of raw Instron sample folders like:

        data\
            FRIDAY_10444\   (raw .is_* files, PDFs, *_Exports folders...)
            Monday_10453\
            tHURSDAY_10452\
            TENSION_20260422_195931.is_tens_Exports\   (loose export folder)
            ...

    and builds an organized output tree matching the OrganizedData\2026 format:

        <Destination>\
            monday\monday_10446\{compression, fracture, tension}
            tuesday\...
            wensday\...
            thursday\...
            friday\...

    Only the time-series data CSVs (Time / Displacement / Force header) are
    copied. Summary "Results Table" CSVs, .is_*/.id_* files, and PDFs are
    left behind. The source data folder is NOT modified.

    An Excel error report (error_report.xlsx) is written to the destination
    listing every sample whose file counts don't match the expected numbers:
        fracture    = 8 data CSVs
        tension     = 2 or 3 data CSVs
        compression = 2 data CSVs
    plus samples with no exports at all, loose/unassigned export folders,
    and unrecognized folders. Adjust with -ExpectedTensionMin/-ExpectedTensionMax etc.

.EXAMPLE
    .\Organize-DataDir.ps1 -Source ".\data" -Destination ".\2026" -DryRun
    .\Organize-DataDir.ps1 -Source ".\data" -Destination ".\2026"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Destination,

    # Expected number of data CSVs per test (min/max lets you allow a range)
    [int]$ExpectedFractureMin    = 8,
    [int]$ExpectedFractureMax    = 8,
    [int]$ExpectedTensionMin     = 2,
    [int]$ExpectedTensionMax     = 2,
    [int]$ExpectedCompressionMin = 2,
    [int]$ExpectedCompressionMax = 2,

    # Where to write the Excel report (default: <Destination>\error_report.xlsx)
    [string]$ReportPath,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    throw "Source folder not found: $Source"
}
if (-not $ReportPath) {
    $ReportPath = Join-Path $Destination 'error_report.xlsx'
}

# --- Day-name normalization -------------------------------------------------
# Output day-folder names. Misspelled input folder names (thrusday, wensday)
# are still recognized, but output uses the spelling on the right-hand side.
# (Note: "wensday" is still spelled this way to match your existing organized
#  folder. Edit here if you fix the spelling there.)
$DayMap = @{
    'monday'    = 'monday'
    'mon'       = 'monday'
    'tuesday'   = 'tuesday'
    'tue'       = 'tuesday'
    'tues'      = 'tuesday'
    'tuesdsay'  = 'tuesday'   # common typo
    'wednesday' = 'wensday'
    'wensday'   = 'wensday'
    'wed'       = 'wensday'
    'weds'      = 'wensday'
    'thursday'  = 'thursday'
    'thrusday'  = 'thursday'
    'thu'       = 'thursday'
    'thur'      = 'thursday'
    'thurs'     = 'thursday'
    'friday'    = 'friday'
    'fri'       = 'friday'
    'saturday'  = 'saturday'
    'sat'       = 'saturday'
    'sunday'    = 'sunday'
    'sun'       = 'sunday'
}

# Top-level folder names to silently ignore (not organized, not reported)
$IgnorePatterns = @('^batch\s*\d*$')

$Expected = @{
    'fracture'    = @{ Min = $ExpectedFractureMin;    Max = $ExpectedFractureMax }
    'tension'     = @{ Min = $ExpectedTensionMin;     Max = $ExpectedTensionMax }
    'compression' = @{ Min = $ExpectedCompressionMin; Max = $ExpectedCompressionMax }
}

# "8" or "2-3" style label for the report
function Get-ExpectedLabel($range) {
    if ($range.Min -eq $range.Max) { return "$($range.Min)" }
    return "$($range.Min)-$($range.Max)"
}

# Map a test-file/export-folder prefix to its category folder name
function Get-Category([string]$name) {
    if ($name -match '^COMPRESSION') { return 'compression' }
    if ($name -match '^Fracture')    { return 'fracture' }
    if ($name -match '^TENSION')     { return 'tension' }
    return $null
}

# A "data" CSV has a Time,Displacement,Force header near the top;
# the "Results Table" summary CSVs do not.
function Test-IsDataCsv([string]$path) {
    $head = Get-Content -LiteralPath $path -TotalCount 4 -ErrorAction SilentlyContinue
    foreach ($line in $head) {
        if ($line -match '^\s*Time\s*,') { return $true }
    }
    return $false
}

# Copy the data CSVs from one *_Exports folder into <sampleDest>\<category>.
# Returns a hashtable of category -> number of data CSVs copied.
function Copy-ExportFolder([System.IO.DirectoryInfo]$exp, [string]$sampleDest) {
    $counts   = @{}
    $category = Get-Category $exp.Name
    if (-not $category) {
        Write-Warning "  Unrecognized export folder skipped: $($exp.Name)"
        return $counts
    }

    $destDir = Join-Path $sampleDest $category
    if (-not (Test-Path -LiteralPath $destDir)) {
        if (-not $script:DryRun) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    }

    $csvs = Get-ChildItem -LiteralPath $exp.FullName -File -Filter '*.csv'
    foreach ($csv in $csvs) {
        if (Test-IsDataCsv $csv.FullName) {
            if ($script:DryRun) {
                Write-Host "  [DryRun] copy  $($csv.Name)  ->  $category\"
            } else {
                Copy-Item -LiteralPath $csv.FullName -Destination (Join-Path $destDir $csv.Name) -Force
                Write-Host "  copied  $($csv.Name)  ->  $category\"
            }
            if ($counts.ContainsKey($category)) { $counts[$category]++ } else { $counts[$category] = 1 }
        } else {
            Write-Host "  skip summary CSV: $($csv.Name)" -ForegroundColor DarkGray
        }
    }
    return $counts
}

# --- Minimal dependency-free .xlsx writer ------------------------------------
function Escape-Xml([string]$s) {
    return $s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'
}

function New-XlsxReport([object[]]$rows, [string[]]$headers, [string]$path) {
    Add-Type -AssemblyName System.IO.Compression | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

    # Build sheet XML (header row bold via style 1, inline strings, numbers typed)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    [void]$sb.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols>')
    for ($i = 1; $i -le $headers.Count; $i++) {
        [void]$sb.Append("<col min=""$i"" max=""$i"" width=""22"" customWidth=""1""/>")
    }
    [void]$sb.Append('</cols><sheetData>')

    # header row
    [void]$sb.Append('<row r="1">')
    foreach ($h in $headers) {
        [void]$sb.Append('<c t="inlineStr" s="1"><is><t>' + (Escape-Xml $h) + '</t></is></c>')
    }
    [void]$sb.Append('</row>')

    # data rows
    $r = 1
    foreach ($row in $rows) {
        $r++
        [void]$sb.Append("<row r=""$r"">")
        foreach ($h in $headers) {
            $v = $row.$h
            if ($null -eq $v -or "$v" -eq '') {
                [void]$sb.Append('<c/>')
            } elseif ($v -is [int] -or $v -is [long] -or $v -is [double]) {
                [void]$sb.Append('<c t="n"><v>' + $v + '</v></c>')
            } else {
                [void]$sb.Append('<c t="inlineStr"><is><t>' + (Escape-Xml "$v") + '</t></is></c>')
            }
        }
        [void]$sb.Append('</row>')
    }
    [void]$sb.Append('</sheetData></worksheet>')
    $sheetXml = $sb.ToString()

    $contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'
    $rels         = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
    $workbook     = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Errors" sheetId="1" r:id="rId1"/></sheets></workbook>'
    $workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
    $styles       = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="11"/><name val="Arial"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf xfId="0"/><xf xfId="0" fontId="1" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'

    $full = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $path))
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Force }
    $dir = Split-Path $full -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $zip = [System.IO.Compression.ZipFile]::Open($full, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $entries = @(
            @('[Content_Types].xml',        $contentTypes),
            @('_rels/.rels',                $rels),
            @('xl/workbook.xml',            $workbook),
            @('xl/_rels/workbook.xml.rels', $workbookRels),
            @('xl/styles.xml',              $styles),
            @('xl/worksheets/sheet1.xml',   $sheetXml)
        )
        foreach ($e in $entries) {
            $entry  = $zip.CreateEntry($e[0])
            $writer = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false)))
            $writer.Write($e[1])
            $writer.Dispose()
        }
    } finally {
        $zip.Dispose()
    }
}

# ==============================================================================

$script:DryRun = [bool]$DryRun
$reportRows    = New-Object System.Collections.Generic.List[object]

$topDirs      = Get-ChildItem -LiteralPath $Source -Directory | Sort-Object Name
$sampleDirs   = @()
$looseExports = @()
$unknownDirs  = @()

foreach ($dir in $topDirs) {
    $ignored = $false
    foreach ($pat in $IgnorePatterns) {
        if ($dir.Name -match $pat) { $ignored = $true; break }
    }
    if ($ignored) {
        Write-Host "Ignoring folder: $($dir.Name)" -ForegroundColor DarkGray
        continue
    }

    if ($dir.Name -like '*_Exports') {
        $looseExports += $dir
    } elseif ($dir.Name -match '^([A-Za-z]+)[ _-]?(\d+)$' -and $DayMap.ContainsKey($Matches[1].ToLower())) {
        $sampleDirs += $dir
    } else {
        $unknownDirs += $dir
    }
}

if (-not $sampleDirs -and -not $looseExports) {
    Write-Host "Nothing to do - no sample folders or export folders found in $Source"
    return
}

# --- Organize each sample folder ----------------------------------------------
$crnsByDay = @{}   # day -> list of CRN ids processed
$yearVotes = @{}   # year -> count (detected from export folder dates)

foreach ($sample in $sampleDirs) {
    $null    = $sample.Name -match '^([A-Za-z]+)[ _-]?(\d+)$'
    $day     = $DayMap[$Matches[1].ToLower()]
    $id      = $Matches[2]
    $newName = "${day}_${id}"
    $destDir = Join-Path (Join-Path $Destination $day) $newName

    if (-not $crnsByDay.ContainsKey($day)) { $crnsByDay[$day] = New-Object System.Collections.Generic.List[string] }
    $crnsByDay[$day].Add($id)

    # Detect the year from export/test folder names like TENSION_20260420_...
    foreach ($item in (Get-ChildItem -LiteralPath $sample.FullName)) {
        if ($item.Name -match '_((19|20)\d{2})\d{4}_') {
            $y = $Matches[1]
            if ($yearVotes.ContainsKey($y)) { $yearVotes[$y]++ } else { $yearVotes[$y] = 1 }
        }
    }

    Write-Host ""
    Write-Host "Organizing: $($sample.Name)  ->  $day\$newName" -ForegroundColor Cyan

    if (-not $DryRun) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    # Track how many data CSVs we found per category for this sample
    $found = @{ 'compression' = 0; 'fracture' = 0; 'tension' = 0 }

    $exportDirs = Get-ChildItem -LiteralPath $sample.FullName -Directory -Filter '*_Exports'
    if (-not $exportDirs) {
        Write-Warning "  No *_Exports folders found inside $($sample.Name)"
    } else {
        foreach ($exp in $exportDirs) {
            $c = Copy-ExportFolder $exp $destDir
            foreach ($k in $c.Keys) { $found[$k] += $c[$k] }
        }
    }

    # QC check against expected counts (Min-Max range per category)
    foreach ($cat in @('compression', 'fracture', 'tension')) {
        $range    = $Expected[$cat]
        $expLabel = Get-ExpectedLabel $range
        $got      = $found[$cat]
        if ($got -lt $range.Min -or $got -gt $range.Max) {
            if ($got -eq 0 -and -not $exportDirs) { $issue = 'NO EXPORTS FOUND - test was never exported from the machine' }
            elseif ($got -eq 0)                   { $issue = 'MISSING - no data files for this test' }
            elseif ($got -lt $range.Min)          { $issue = "MISSING $($range.Min - $got) file(s)" }
            else                                  { $issue = "EXTRA $($got - $range.Max) file(s) - check for duplicate runs" }

            Write-Warning "  ${cat}: found $got, expected $expLabel"
            $reportRows.Add([pscustomobject]@{
                Day      = $day
                Sample   = $newName
                SourceFolder = $sample.Name
                Category = $cat
                Expected = $expLabel
                Found    = $got
                Issue    = $issue
            })
        }
    }
}

# --- Handle loose *_Exports folders at the top level ----------------------------
foreach ($loose in $looseExports) {
    Write-Host ""
    Write-Host "Loose export folder: $($loose.Name)" -ForegroundColor Magenta

    $owner = $sampleDirs | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName $loose.Name)
    }

    if ($owner) {
        Write-Host "  Duplicate of the copy inside $($owner[0].Name) - skipping." -ForegroundColor DarkGray
        continue
    }

    Write-Warning "  No matching sample folder found. Copying to _unassigned\ - please file it manually."
    $c = Copy-ExportFolder $loose (Join-Path $Destination '_unassigned')
    $n = 0; foreach ($k in $c.Keys) { $n += $c[$k] }
    $reportRows.Add([pscustomobject]@{
        Day      = ''
        Sample   = '_unassigned'
        SourceFolder = $loose.Name
        Category = (Get-Category $loose.Name)
        Expected = ''
        Found    = $n
        Issue    = 'UNASSIGNED - loose export folder does not belong to any sample folder'
    })
}

foreach ($u in $unknownDirs) {
    Write-Warning "Skipped unrecognized folder: $($u.Name)"
    $reportRows.Add([pscustomobject]@{
        Day      = ''
        Sample   = ''
        SourceFolder = $u.Name
        Category = ''
        Expected = ''
        Found    = ''
        Issue    = 'UNRECOGNIZED folder name - could not parse day/sample id'
    })
}

# --- Build the text data report -------------------------------------------------
# Detected year (most common in the data), fallback to blank
$year = ''
if ($yearVotes.Count -gt 0) {
    $year = ($yearVotes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
}

$dayOrder = @('monday', 'tuesday', 'wensday', 'thursday', 'friday', 'saturday', 'sunday')
$lines    = New-Object System.Collections.Generic.List[string]

$lines.Add("$year Data Report".Trim())
$lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$lines.Add("Source:    $Source")
$lines.Add("Output:    $Destination")
$lines.Add(('=' * 40))
$lines.Add('')
$lines.Add('CRNs processed by day:')
$lines.Add('')

$totalCrns = 0
foreach ($day in $dayOrder) {
    if (-not $crnsByDay.ContainsKey($day)) { continue }
    $ids = $crnsByDay[$day] | Sort-Object
    $totalCrns += $ids.Count
    $lines.Add("${day}: $($ids.Count) crns")
    foreach ($id in $ids) { $lines.Add("  $id") }
    $lines.Add('')
}

$lines.Add("Total samples: $totalCrns")
$lines.Add('')
$lines.Add('Sample errors:')

$errorRows = @($reportRows | Where-Object { $_.Issue -and $_.Issue -notlike 'No errors*' })
if ($errorRows.Count -eq 0) {
    $lines.Add('  None - all samples had the expected number of files.')
} else {
    foreach ($row in $errorRows) {
        $who = $row.Sample
        if (-not $who) { $who = $row.SourceFolder }
        $detail = ''
        if ("$($row.Expected)" -ne '') { $detail = " (found $($row.Found), expected $($row.Expected))" }
        $lines.Add("  ${who} - $($row.Category): $($row.Issue)$detail")
    }
}

$reportText = $lines -join [Environment]::NewLine

# Always show the report in the console (including dry runs)
Write-Host ""
Write-Host $reportText

$TextReportPath = [System.IO.Path]::ChangeExtension($ReportPath, '.txt')
if (-not $DryRun) {
    Set-Content -LiteralPath $TextReportPath -Value $reportText -Encoding UTF8
    Write-Host ""
    Write-Host "Text report written: $TextReportPath" -ForegroundColor Yellow
}

# --- Write the Excel error report ------------------------------------------------
$headers = @('Day', 'Sample', 'SourceFolder', 'Category', 'Expected', 'Found', 'Issue')

if ($reportRows.Count -eq 0) {
    $reportRows.Add([pscustomobject]@{
        Day = ''; Sample = ''; SourceFolder = ''; Category = ''
        Expected = ''; Found = ''; Issue = 'No errors - all samples had the expected number of files'
    })
}

if ($DryRun) {
    Write-Host ""
    Write-Host "[DryRun] Would write error report with $($reportRows.Count) row(s) to $ReportPath" -ForegroundColor Yellow
    $reportRows | Format-Table -AutoSize
} else {
    New-XlsxReport -rows $reportRows.ToArray() -headers $headers -path $ReportPath
    Write-Host ""
    Write-Host "Error report written: $ReportPath  ($($reportRows.Count) row(s))" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done. Output: $Destination" -ForegroundColor Green
