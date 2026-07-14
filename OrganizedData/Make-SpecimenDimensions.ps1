<#
.SYNOPSIS
    Traverses an organized data tree (the output of Organize-DataDir.ps1):

        <OrganizedRoot>\
            monday\monday_10446\{compression, fracture, tension}
            tuesday\...
            ...

    detects every CRN, orders them oldest -> newest (by the earliest test
    timestamp found in the CSV filenames, e.g. TENSION_20260420_155824_1.csv),
    and generates a blank SpecimenDimensions.xlsx matching the template:

        Section | (variant) | Test | Sample | Width_mm | Thickness_mm |
        NotchLength_mm | PreCrackLength_mm | Length_mm | Diameter_mm | GaugeLength_mm

    Each CRN gets one block of rows (dimension columns left blank to fill in):
        COMPRESSION  cnt 1, neat 1
        FRACTURE     cnt 1-4, neat 1-4
        TENSION      cnt 1, neat 1

.PARAMETER OrganizedRoot
    The organized data folder (e.g. ".\2026_organized").

.PARAMETER Output
    Path of the xlsx to create (default: <OrganizedRoot>\SpecimenDimensions.xlsx)

.PARAMETER Variants
    Material variants per CRN. Default: cnt, neat

.PARAMETER FracturePerVariant / CompressionPerVariant / TensionPerVariant
    Number of specimens per variant for each test. Defaults: 4 / 1 / 1

.EXAMPLE
    .\Make-SpecimenDimensions.ps1 -OrganizedRoot ".\2026_organized"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OrganizedRoot,

    [string]$Output,

    [string[]]$Variants = @('cnt', 'neat'),

    [int]$CompressionPerVariant = 1,
    [int]$FracturePerVariant    = 4,
    [int]$TensionPerVariant     = 1
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $OrganizedRoot -PathType Container)) {
    throw "Organized data folder not found: $OrganizedRoot"
}
if (-not $Output) {
    $Output = Join-Path $OrganizedRoot 'SpecimenDimensions.xlsx'
}

# --- Detect CRNs and their earliest test timestamp -----------------------------
# Sample folders look like <day>_<crn> and contain compression/fracture/tension
# folders of CSVs named like TENSION_20260420_155824_1.csv
$samples = New-Object System.Collections.Generic.List[object]

$rootFull = (Get-Item -LiteralPath $OrganizedRoot).FullName

$sampleDirs = Get-ChildItem -LiteralPath $OrganizedRoot -Recurse -Directory |
    Where-Object { $_.Name -match '^[A-Za-z]+_(\d+)$' -and $_.Name -notmatch '^_' }

foreach ($dir in $sampleDirs) {
    $null = $dir.Name -match '^[A-Za-z]+_(\d+)$'
    $crn  = $Matches[1]

    # Detect a batchN ancestor folder (e.g. 2024 layout: batch1\monday\monday_10418)
    $batch = ''
    $p = $dir.Parent
    while ($p -and $p.FullName.Length -ge $rootFull.Length) {
        if ($p.Name -match '^batch\d+$') { $batch = $p.Name; break }
        if ($p.FullName -eq $rootFull) { break }
        $p = $p.Parent
    }

    # earliest timestamp from CSV names: *_YYYYMMDD_HHMMSS_*.csv
    $earliest = $null
    $csvs = Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Filter '*.csv' -ErrorAction SilentlyContinue
    foreach ($csv in $csvs) {
        if ($csv.Name -match '_(\d{8})_(\d{1,6})_') {
            $date = $Matches[1]
            $time = $Matches[2].PadLeft(6, '0')
            $stamp = "$date$time"
            if ($null -eq $earliest -or $stamp -lt $earliest) { $earliest = $stamp }
        }
    }
    if ($null -eq $earliest) { $earliest = '99999999999999' }  # no CSVs -> sort last

    $samples.Add([pscustomobject]@{
        Crn      = $crn
        Batch    = $batch
        Earliest = $earliest
        Folder   = $dir.Name
    })
}

if ($samples.Count -eq 0) {
    throw "No sample folders (like monday_10446) found under $OrganizedRoot"
}

# oldest first -> newest last; tie-break by CRN
$ordered = $samples | Sort-Object Earliest, Batch, Crn

Write-Host "Detected $($ordered.Count) CRNs (oldest -> newest):" -ForegroundColor Cyan
$i = 0
foreach ($s in $ordered) {
    $i++
    $when = ''
    if ($s.Earliest -ne '99999999999999') {
        $when = "$($s.Earliest.Substring(0,4))-$($s.Earliest.Substring(4,2))-$($s.Earliest.Substring(6,2))"
    } else {
        $when = 'no data found'
    }
    $where = $s.Folder
    if ($s.Batch) { $where = "$($s.Batch)\$($s.Folder))".TrimEnd(')') }
    Write-Host ("  {0,3}. CRN {1}  ({2}, first test {3})" -f $i, $s.Crn, $where, $when)
}

# --- Build rows in template order, one sheet per batch --------------------------
$headers = @('Section', 'Variant', 'Test', 'Sample', 'Width_mm', 'Thickness_mm',
             'NotchLength_mm', 'PreCrackLength_mm', 'Length_mm', 'Diameter_mm', 'GaugeLength_mm')

$testPlan = @(
    @{ Test = 'COMPRESSION'; Count = $CompressionPerVariant },
    @{ Test = 'FRACTURE';    Count = $FracturePerVariant },
    @{ Test = 'TENSION';     Count = $TensionPerVariant }
)

# Group samples by batch. No batches -> a single sheet named "Blank".
# 2024-style layouts (batch1, batch2, ...) -> one worksheet per batch.
$sheetOrder  = New-Object System.Collections.Generic.List[string]
$sheetGroups = @{}
foreach ($s in $ordered) {
    $sheetName = $s.Batch
    if (-not $sheetName) { $sheetName = 'Blank' }
    if (-not $sheetGroups.ContainsKey($sheetName)) {
        $sheetGroups[$sheetName] = New-Object System.Collections.Generic.List[object]
        $sheetOrder.Add($sheetName)
    }
    $sheetGroups[$sheetName].Add($s)
}

function New-SheetRows($samplesInSheet) {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($s in $samplesInSheet) {
        foreach ($plan in $testPlan) {
            foreach ($variant in $Variants) {
                for ($n = 1; $n -le $plan.Count; $n++) {
                    # keep leading zeros (2023 ids like 040308) by emitting text
                    $section = $s.Crn
                    if ($section -notmatch '^0') { $section = [long]$section }
                    $rows.Add([pscustomobject]@{
                        Section = $section
                        Variant = $variant
                        Test    = $plan.Test
                        Sample  = $n
                        Width_mm = $null; Thickness_mm = $null; NotchLength_mm = $null
                        PreCrackLength_mm = $null; Length_mm = $null; Diameter_mm = $null
                        GaugeLength_mm = $null
                    })
                }
            }
        }
    }
    return $rows
}

# --- Minimal dependency-free .xlsx writer (multi-sheet) --------------------------
function Escape-Xml([string]$s) {
    return $s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'
}

function New-SheetXml($rows) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    [void]$sb.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols>')
    for ($c = 1; $c -le $headers.Count; $c++) {
        [void]$sb.Append("<col min=""$c"" max=""$c"" width=""18"" customWidth=""1""/>")
    }
    [void]$sb.Append('</cols><sheetData>')

    # Header row - column B (Variant) has a blank header cell like the template
    [void]$sb.Append('<row r="1">')
    foreach ($h in $headers) {
        $label = $h
        if ($h -eq 'Variant') { $label = '' }   # template leaves this header blank
        [void]$sb.Append('<c t="inlineStr" s="1"><is><t>' + (Escape-Xml $label) + '</t></is></c>')
    }
    [void]$sb.Append('</row>')

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
    return $sb.ToString()
}

Add-Type -AssemblyName System.IO.Compression | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

# Build workbook parts for N sheets
$sheetXmls    = @()
$sheetEntries = New-Object System.Text.StringBuilder
$ctOverrides  = New-Object System.Text.StringBuilder
$wbRels       = New-Object System.Text.StringBuilder
$totalRows    = 0

$i = 0
foreach ($sheetName in $sheetOrder) {
    $i++
    $rows = New-SheetRows $sheetGroups[$sheetName]
    $totalRows += $rows.Count
    $sheetXmls += ,@("xl/worksheets/sheet$i.xml", (New-SheetXml $rows))
    [void]$sheetEntries.Append("<sheet name=""$(Escape-Xml $sheetName)"" sheetId=""$i"" r:id=""rId$i""/>")
    [void]$ctOverrides.Append("<Override PartName=""/xl/worksheets/sheet$i.xml"" ContentType=""application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml""/>")
    [void]$wbRels.Append("<Relationship Id=""rId$i"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"" Target=""worksheets/sheet$i.xml""/>")
}
$stylesRid = "rId$($i + 1)"

$contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' + $ctOverrides.ToString() + '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'
$rels         = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
$workbook     = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>' + $sheetEntries.ToString() + '</sheets></workbook>'
$workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + $wbRels.ToString() + '<Relationship Id="' + $stylesRid + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
$styles       = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="11"/><name val="Arial"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf xfId="0"/><xf xfId="0" fontId="1" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'

$full = $Output
if (-not [System.IO.Path]::IsPathRooted($full)) { $full = Join-Path (Get-Location).Path $full }
$full = [System.IO.Path]::GetFullPath($full)
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
        @('xl/styles.xml',              $styles)
    )
    $entries += $sheetXmls
    foreach ($e in $entries) {
        $entry  = $zip.CreateEntry($e[0])
        $writer = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false)))
        $writer.Write($e[1])
        $writer.Dispose()
    }
} finally {
    $zip.Dispose()
}

Write-Host ""
Write-Host "Wrote $totalRows specimen rows for $($ordered.Count) CRNs across $($sheetOrder.Count) sheet(s) to: $Output" -ForegroundColor Green
