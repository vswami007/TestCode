<#
.SYNOPSIS
  Parse an ASPX markup file, extract ASP.NET validators + validation groups, map them to controls,
  write JSON output + a Markdown tree.

.USAGE
  .\Parse-WebFormsValidation.ps1 -AspxPath "C:\app\Pages\Login.aspx" -OutDir "C:\out"
#>

param(
  [Parameter(Mandatory = $true)]
  [string]$AspxPath = "C:\Users\Admin\Downloads\PS-Scripts\Manage.aspx",

  [Parameter(Mandatory = $false)]
  [string]$OutDir = "C:\Users\Admin\Downloads\PS-Scripts\Manage.aspx_validation_out",

  [Parameter(Mandatory = $false)]
  [string]$JsonFileName = "validation-map.json",

  [Parameter(Mandatory = $false)]
  [string]$MdFileName = "validation-tree.md"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $AspxPath)) {
  throw "ASPX file not found: $AspxPath"
}

if (!(Test-Path -LiteralPath $OutDir)) {
  New-Item -ItemType Directory -Path $OutDir | Out-Null
}

# ----------------------------
# Helpers
# ----------------------------

function Parse-Attributes {
  param([string]$TagText)

  $attrs = [ordered]@{}
  $attrRegex = [regex]'(?is)(?<k>[\w:\-]+)\s*=\s*(?:"(?<v>[^"]*)"|''(?<v>[^'']*)'')'
  foreach ($m in $attrRegex.Matches($TagText)) {
    $k = $m.Groups['k'].Value
    $v = $m.Groups['v'].Value
    if (-not $attrs.Contains($k)) { $attrs[$k] = $v }
  }
  return $attrs
}

function Get-BoolOrNull {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  switch ($Value.Trim().ToLowerInvariant()) {
    "true" { return $true }
    "false" { return $false }
    default { return $null }
  }
}

function Find-ControlTagById {
  param(
    [string]$AllText,
    [string]$ControlId
  )

  if ([string]::IsNullOrWhiteSpace($ControlId)) { return $null }

  $escaped = [regex]::Escape($ControlId)

  # ASP.NET server controls: <asp:TextBox ... ID="txtEmail" ...>
  $rxAsp = [regex]::new("(?is)<asp:(?<type>\w+)\b[^>]*\bID\s*=\s*(?:`"$escaped`"|'$escaped')[^>]*>", "IgnoreCase")
  $mAsp = $rxAsp.Match($AllText)
  if ($mAsp.Success) {
    return @{
      controlType = $mAsp.Groups['type'].Value
      rawTag      = $mAsp.Value
      attrs       = (Parse-Attributes $mAsp.Value)
      source      = "asp"
    }
  }

  # HTML tags: <input id="x" runat="server" ...> etc.
  $rxHtml = [regex]::new("(?is)<(?<type>[\w\-]+)\b[^>]*\bid\s*=\s*(?:`"$escaped`"|'$escaped')[^>]*>", "IgnoreCase")
  $mHtml = $rxHtml.Match($AllText)
  if ($mHtml.Success) {
    return @{
      controlType = $mHtml.Groups['type'].Value
      rawTag      = $mHtml.Value
      attrs       = (Parse-Attributes $mHtml.Value)
      source      = "html"
    }
  }

  return $null
}

function Normalize-ValidatorType {
  param([string]$AspTagName)
  if ([string]::IsNullOrWhiteSpace($AspTagName)) { return $AspTagName }
  return $AspTagName.Trim()
}

function Pick-ValidationGroup {
  param($attrs)
  if ($null -eq $attrs) { return $null }
  if ($attrs.Contains("ValidationGroup")) { return $attrs["ValidationGroup"] }
  return $null
}

function Get-IdAttr {
  param($attrs)
  if ($null -eq $attrs) { return $null }
  if ($attrs.Contains("ID")) { return $attrs["ID"] }
  if ($attrs.Contains("id")) { return $attrs["id"] }
  return $null
}

function Md-Escape {
  param([string]$s)
  if ($null -eq $s) { return "" }
  return ($s -replace '\|','\|' -replace '\r?\n',' ')
}

# ----------------------------
# Read file as raw text
# ----------------------------
$allText = Get-Content -LiteralPath $AspxPath -Raw

# ----------------------------
# 1) Extract validator tags + validation summary
# ----------------------------
$validatorTagRegex = [regex]::new(
  '(?is)<asp:(?<tag>(?:RequiredFieldValidator|RegularExpressionValidator|RangeValidator|CompareValidator|CustomValidator|ValidationSummary))\b(?<body>[^>]*)>',
  "IgnoreCase"
)

$rawValidators = @()
$rawSummaries  = @()

foreach ($m in $validatorTagRegex.Matches($allText)) {
  $tagName = $m.Groups['tag'].Value
  $fullTag = $m.Value
  $attrs   = Parse-Attributes $fullTag

  $id = Get-IdAttr $attrs
  $vg = Pick-ValidationGroup $attrs

  if ($tagName -ieq "ValidationSummary") {
    $rawSummaries += [ordered]@{
      validatorId     = $id
      validatorType   = "ValidationSummary"
      validationGroup = $vg
      properties      = $attrs
    }
    continue
  }

  $rawValidators += [ordered]@{
    validatorId       = $id
    validatorType     = (Normalize-ValidatorType $tagName)
    controlToValidate = ($attrs["ControlToValidate"])
    validationGroup   = $vg
    errorMessage      = ($attrs["ErrorMessage"])
    text              = ($attrs["Text"])
    display           = ($attrs["Display"])
    enabled           = (Get-BoolOrNull $attrs["Enabled"])
    properties        = $attrs
  }
}

# ----------------------------
# 2) Build control map by following ControlToValidate
# ----------------------------
$controlsById = @{}
$unboundValidators = @()

foreach ($v in $rawValidators) {
  $ctv = $v.controlToValidate

  if ([string]::IsNullOrWhiteSpace($ctv)) {
    $unboundValidators += $v
    continue
  }

  if (-not $controlsById.ContainsKey($ctv)) {
    $controlInfo = Find-ControlTagById -AllText $allText -ControlId $ctv
    $controlType = $null
    $controlName = $null
    $controlVG   = $null

    if ($null -ne $controlInfo) {
      $controlType = $controlInfo.controlType
      $controlName = $controlInfo.attrs["Name"]
      if ($controlInfo.attrs.Contains("ValidationGroup")) { $controlVG = $controlInfo.attrs["ValidationGroup"] }
    }

    $controlsById[$ctv] = [ordered]@{
      controlId        = $ctv
      controlType      = $controlType
      name             = $controlName
      validationGroup  = $controlVG
      validators       = @()
    }
  }

  $controlsById[$ctv].validators += [ordered]@{
    validatorId     = $v.validatorId
    validatorType   = $v.validatorType
    errorMessage    = $v.errorMessage
    text            = $v.text
    display         = $v.display
    enabled         = $v.enabled
    validationGroup = $v.validationGroup
    properties      = $v.properties
  }

  if ([string]::IsNullOrWhiteSpace($controlsById[$ctv].validationGroup) -and -not [string]::IsNullOrWhiteSpace($v.validationGroup)) {
    $controlsById[$ctv].validationGroup = $v.validationGroup
  }
}

# ----------------------------
# 3) Extract buttons that trigger validation groups
# ----------------------------
$buttonRegex = [regex]::new(
  '(?is)<asp:(?<tag>(?:Button|LinkButton|ImageButton))\b(?<body>[^>]*)>',
  "IgnoreCase"
)

$buttons = @()
foreach ($m in $buttonRegex.Matches($allText)) {
  $fullTag = $m.Value
  $attrs   = Parse-Attributes $fullTag
  $id      = Get-IdAttr $attrs
  if ([string]::IsNullOrWhiteSpace($id)) { continue }

  $causesValidation = $true
  if ($attrs.Contains("CausesValidation")) {
    $cv = Get-BoolOrNull $attrs["CausesValidation"]
    if ($null -ne $cv) { $causesValidation = $cv }
  }

  $vg = $null
  if ($attrs.Contains("ValidationGroup")) { $vg = $attrs["ValidationGroup"] }

  $buttons += [ordered]@{
    controlId        = $id
    controlType      = $m.Groups['tag'].Value
    causesValidation = $causesValidation
    validationGroup  = $vg
    properties       = $attrs
  }
}

# ----------------------------
# 4) Build validationGroups structure
# ----------------------------
$groups = @{}

foreach ($b in $buttons) {
  if (-not $b.causesValidation) { continue }
  $g = $b.validationGroup
  if ([string]::IsNullOrWhiteSpace($g)) { continue }

  if (-not $groups.ContainsKey($g)) {
    $groups[$g] = [ordered]@{
      groupName         = $g
      triggeredBy       = @()
      controlsValidated = @()
    }
  }

  if (-not $groups[$g].triggeredBy.Contains($b.controlId)) {
    $groups[$g].triggeredBy += $b.controlId
  }
}

foreach ($cid in $controlsById.Keys) {
  $c = $controlsById[$cid]
  $g = $c.validationGroup
  if ([string]::IsNullOrWhiteSpace($g)) { continue }

  if (-not $groups.ContainsKey($g)) {
    $groups[$g] = [ordered]@{
      groupName         = $g
      triggeredBy       = @()
      controlsValidated = @()
    }
  }

  if (-not $groups[$g].controlsValidated.Contains($cid)) {
    $groups[$g].controlsValidated += $cid
  }
}

# ----------------------------
# 5) Prepare final JSON object + write it
# ----------------------------
$controls = @()
foreach ($cid in ($controlsById.Keys | Sort-Object)) {
  $controls += $controlsById[$cid]
}

$validationGroups = @()
foreach ($gk in ($groups.Keys | Sort-Object)) {
  $validationGroups += $groups[$gk]
}

$unbound = @()
$unbound += $rawSummaries
foreach ($uv in $unboundValidators) {
  $unbound += [ordered]@{
    validatorId     = $uv.validatorId
    validatorType   = $uv.validatorType
    validationGroup = $uv.validationGroup
    properties      = $uv.properties
  }
}

$result = [ordered]@{
  sourceFile        = $AspxPath
  generatedAt       = (Get-Date).ToString("o")
  controls          = $controls
  validationGroups  = $validationGroups
  unboundValidators = $unbound
  buttonsScanned    = $buttons
}

$jsonPath = Join-Path $OutDir $JsonFileName
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

# ----------------------------
# 6) Build Markdown tree (NO backticks in double-quoted strings)
# ----------------------------
$bt = [char]96  # literal backtick for Markdown inline code

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Validation Tree')
$md.Add('')
$md.Add(('- **Source:** {0}' -f (Md-Escape $AspxPath)))
$md.Add(('- **Generated:** {0}' -f (Md-Escape $result.generatedAt)))
$md.Add('')

if (@($validationGroups).Count -gt 0) {
  $md.Add('## Validation Groups')
  $md.Add('')

  foreach ($g in $validationGroups) {
    $md.Add(('### Group: {0}{1}{0}' -f $bt, (Md-Escape $g.groupName)))
    $md.Add('')

    $triggers = if (@($g.triggeredBy).Count -gt 0) { ($g.triggeredBy -join ', ') } else { '(not found in markup)' }
    $md.Add(('- **Triggered by:** {0}' -f (Md-Escape $triggers)))

    if (@($g.controlsValidated).Count -gt 0) {
      $md.Add('- **Controls validated:**')
      foreach ($cid in ($g.controlsValidated | Sort-Object)) {
        $c = $controlsById[$cid]
        $ctype = if ($c.controlType) { $c.controlType } else { 'UNKNOWN' }
        $md.Add(('  - {0}{1}{0} ({2})' -f $bt, (Md-Escape $cid), (Md-Escape $ctype)))

        foreach ($v in $c.validators) {
          if ($v.validationGroup -ne $g.groupName) { continue }
          $em = if ($v.errorMessage) { $v.errorMessage } else { $v.text }
          $md.Add(('    - Validator: {0}{1}{0} **{2}** — {3}' -f $bt, (Md-Escape $v.validatorId), (Md-Escape $v.validatorType), (Md-Escape $em)))
        }
      }
    } else {
      $md.Add('- **Controls validated:** (none discovered)')
    }

    $summ = $rawSummaries | Where-Object { $_.validationGroup -eq $g.groupName }
    if (@($summ).Count -gt 0) {
      $md.Add('- **ValidationSummary:**')
      foreach ($s in $summ) {
        $props = (($s.properties.Keys | Sort-Object) -join ', ')
        $md.Add(('  - {0}{1}{0} (properties: {2})' -f $bt, (Md-Escape $s.validatorId), (Md-Escape $props)))
      }
    }

    $md.Add('')
  }
}

$ungroupedControls = $controls | Where-Object { [string]::IsNullOrWhiteSpace($_.validationGroup) }
if (@($ungroupedControls).Count -gt 0) {
  $md.Add('## Ungrouped Validations (default)')
  $md.Add('')

  foreach ($c in ($ungroupedControls | Sort-Object controlId)) {
    $ctype = if ($c.controlType) { $c.controlType } else { 'UNKNOWN' }
    $md.Add(('- {0}{1}{0} ({2})' -f $bt, (Md-Escape $c.controlId), (Md-Escape $ctype)))

    foreach ($v in $c.validators) {
      if (-not [string]::IsNullOrWhiteSpace($v.validationGroup)) { continue }
      $em = if ($v.errorMessage) { $v.errorMessage } else { $v.text }
      $md.Add(('  - {0}{1}{0} **{2}** — {3}' -f $bt, (Md-Escape $v.validatorId), (Md-Escape $v.validatorType), (Md-Escape $em)))
    }
  }

  $md.Add('')
}

if (@($unbound).Count -gt 0) {
  $md.Add('## Unbound Validators / Summaries')
  $md.Add('')

  foreach ($u in ($unbound | Sort-Object validatorType, validatorId)) {
    $gname = if ($u.validationGroup) { $u.validationGroup } else { '(none)' }
    $md.Add(('- {0}{1}{0} **{2}** — group: {0}{3}{0}' -f $bt, (Md-Escape $u.validatorId), (Md-Escape $u.validatorType), (Md-Escape $gname)))
  }

  $md.Add('')
}

$mdPath = Join-Path $OutDir $MdFileName
$mdText = $md -join "`r`n"
Set-Content -LiteralPath $mdPath -Value $mdText -Encoding UTF8

Write-Host "Done."
Write-Host "JSON: $jsonPath"
Write-Host "MD:   $mdPath"
