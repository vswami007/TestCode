param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath = "C:\Users\Admin\Downloads\PS-Scripts\Manage.aspx",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "C:\Users\Admin\Downloads\PS-Scripts\Manage_claude.md"
)

# STEP 1: Read line by line, find all *Validators and ValidationSummary
function Find-AllValidators {
    param([string[]]$content)
    
    $validators = @()
    $currentValidator = ""
    $inValidator = $false
    
    foreach ($line in $content) {
        $trimmed = $line.Trim()
        
        # Check if line starts a validator
        if ($trimmed -match '<asp:.*[Vv]alidator|<asp:ValidationSummary') {
            $inValidator = $true
            $currentValidator = $trimmed
            
            # Check if it closes on same line
            if ($trimmed -match '/>\s*$') {
                $validators += $currentValidator
                $currentValidator = ""
                $inValidator = $false
            }
        }
        elseif ($inValidator) {
            # Continue building multi-line validator
            $currentValidator += " " + $trimmed
            
            # Check if it closes
            if ($trimmed -match '/>\s*$') {
                $validators += $currentValidator
                $currentValidator = ""
                $inValidator = $false
            }
        }
    }
    
    return $validators
}

# STEP 2: Extract key attributes from validator markup
function Extract-ValidatorAttributes {
    param([string]$validatorMarkup)
    
    $validator = @{
        validatorId = $null
        validatorType = $null
        controlToValidate = $null
        errorMessage = $null
        text = $null
        display = $null
        enabled = $null
        validationGroup = $null
        properties = @{}
    }
    
    # Extract validator type
    if ($validatorMarkup -match '<asp:(\w+)') {
        $validator.validatorType = $matches[1]
    }
    
    # Extract ID
    if ($validatorMarkup -match 'ID\s*=\s*"([^"]+)"') {
        $validator.validatorId = $matches[1]
    }
    
    # Extract ControlToValidate
    if ($validatorMarkup -match 'ControlToValidate\s*=\s*"([^"]+)"') {
        $validator.controlToValidate = $matches[1]
    }
    
    # Extract ErrorMessage
    if ($validatorMarkup -match 'ErrorMessage\s*=\s*"([^"]+)"') {
        $validator.errorMessage = $matches[1]
    }
    
    # Extract Text
    if ($validatorMarkup -match 'Text\s*=\s*"([^"]+)"') {
        $validator.text = $matches[1]
    }
    
    # Extract Display
    if ($validatorMarkup -match 'Display\s*=\s*"([^"]+)"') {
        $validator.display = $matches[1]
    }
    
    # Extract Enabled
    if ($validatorMarkup -match 'Enabled\s*=\s*"([^"]+)"') {
        $validator.enabled = $matches[1]
    }
    
    # Extract ValidationGroup
    if ($validatorMarkup -match 'ValidationGroup\s*=\s*"([^"]+)"') {
        $validator.validationGroup = $matches[1]
    }
    
    # Extract type-specific properties
    switch ($validator.validatorType) {
        "RequiredFieldValidator" {
            if ($validatorMarkup -match 'InitialValue\s*=\s*"([^"]*)"') {
                $validator.properties.InitialValue = $matches[1]
            }
        }
        "RangeValidator" {
            if ($validatorMarkup -match 'MinimumValue\s*=\s*"([^"]*)"') {
                $validator.properties.MinimumValue = $matches[1]
            }
            if ($validatorMarkup -match 'MaximumValue\s*=\s*"([^"]*)"') {
                $validator.properties.MaximumValue = $matches[1]
            }
            if ($validatorMarkup -match 'Type\s*=\s*"([^"]*)"') {
                $validator.properties.Type = $matches[1]
            }
        }
        "CompareValidator" {
            if ($validatorMarkup -match 'ControlToCompare\s*=\s*"([^"]*)"') {
                $validator.properties.ControlToCompare = $matches[1]
            }
            if ($validatorMarkup -match 'ValueToCompare\s*=\s*"([^"]*)"') {
                $validator.properties.ValueToCompare = $matches[1]
            }
            if ($validatorMarkup -match 'Operator\s*=\s*"([^"]*)"') {
                $validator.properties.Operator = $matches[1]
            }
        }
        "RegularExpressionValidator" {
            if ($validatorMarkup -match 'ValidationExpression\s*=\s*"([^"]*)"') {
                $validator.properties.ValidationExpression = $matches[1]
            }
        }
        "CustomValidator" {
            if ($validatorMarkup -match 'ClientValidationFunction\s*=\s*"([^"]*)"') {
                $validator.properties.ClientValidationFunction = $matches[1]
            }
            if ($validatorMarkup -match 'OnServerValidate\s*=\s*"([^"]*)"') {
                $validator.properties.ServerValidationFunction = $matches[1]
            }
        }
        "ValidationSummary" {
            if ($validatorMarkup -match 'DisplayMode\s*=\s*"([^"]*)"') {
                $validator.properties.DisplayMode = $matches[1]
            }
            if ($validatorMarkup -match 'ShowSummary\s*=\s*"([^"]*)"') {
                $validator.properties.ShowSummary = $matches[1]
            }
            if ($validatorMarkup -match 'ShowMessageBox\s*=\s*"([^"]*)"') {
                $validator.properties.ShowMessageBox = $matches[1]
            }
        }
    }
    
    return $validator
}

# STEP 3: Search ASPX for control details
function Find-ControlDetails {
    param(
        [string]$controlId,
        [string[]]$content
    )
    
    $controlInfo = @{
        controlId = $controlId
        controlType = $null
        controlName = $null
    }
    
    # Search for the control in the ASPX
    foreach ($line in $content) {
        if ($line -match "ID\s*=\s*`"$controlId`"") {
            # Extract control type
            if ($line -match '<asp:(\w+)') {
                $controlInfo.controlType = $matches[1]
            }
            elseif ($line -match '<(\w+):(\w+)') {
                $controlInfo.controlType = "$($matches[1]):$($matches[2])"
            }
            elseif ($line -match '<(\w+)') {
                $controlInfo.controlType = $matches[1]
            }
            
            # Extract Name attribute if exists
            if ($line -match 'Name\s*=\s*"([^"]+)"') {
                $controlInfo.controlName = $matches[1]
            }
            
            break
        }
    }
    
    return $controlInfo
}

# STEP 4: Build complete JSON structure
function Build-ValidationData {
    param([string[]]$content)
    
    Write-Host "Step 1: Finding all validators..." -ForegroundColor Gray
    $validatorMarkups = Find-AllValidators -content $content
    Write-Host "  Found $(@($validatorMarkups).Count) validators" -ForegroundColor Gray
    
    Write-Host "Step 2: Extracting validator attributes..." -ForegroundColor Gray
    $validators = @()
    foreach ($markup in $validatorMarkups) {
        $validator = Extract-ValidatorAttributes -validatorMarkup $markup
        $validators += $validator
    }
    
    Write-Host "Step 3: Looking up control details for each validator..." -ForegroundColor Gray
    $controlsWithValidators = @{}
    
    foreach ($validator in $validators) {
        if ($validator.controlToValidate) {
            # Find control details
            $controlDetails = Find-ControlDetails -controlId $validator.controlToValidate -content $content
            
            # Group validators by control
            if (-not $controlsWithValidators.ContainsKey($validator.controlToValidate)) {
                $controlsWithValidators[$validator.controlToValidate] = @{
                    controlId = $controlDetails.controlId
                    controlType = $controlDetails.controlType
                    controlName = $controlDetails.controlName
                    validationGroup = $validator.validationGroup
                    validators = @()
                }
            }
            
            $controlsWithValidators[$validator.controlToValidate].validators += $validator
        }
    }
    
    Write-Host "Step 4: Building final JSON structure..." -ForegroundColor Gray
    
    # Build final structure
    $validationData = @{
        controls = @()
        unboundValidators = @()
    }
    
    # Add controls
    foreach ($controlId in $controlsWithValidators.Keys) {
        $validationData.controls += $controlsWithValidators[$controlId]
    }
    
    # Add unbound validators (ValidationSummary, etc.)
    foreach ($validator in $validators) {
        if (-not $validator.controlToValidate) {
            $validationData.unboundValidators += $validator
        }
    }
    
    return $validationData
}

# STEP 5: Build tree hierarchy from JSON
function Build-TreeFromJson {
    param([object]$data)
    
    $output = @()
    
    if (@($data.controls).Count -eq 0 -and @($data.unboundValidators).Count -eq 0) {
        $output += "No validators found in the file."
        return $output
    }
    
    # Print controls with validators
    foreach ($control in $data.controls) {
        $output += "$($control.controlId) ($($control.controlType))"
        
        # Validation Group
        $vGroup = if ($control.validationGroup) { $control.validationGroup } else { "None" }
        $output += "├── Validation Group: $vGroup"
        
        # Validators
        $output += "└── Validators:"
        
        for ($i = 0; $i -lt @($control.validators).Count; $i++) {
            $validator = $control.validators[$i]
            $isLastValidator = ($i -eq @($control.validators).Count - 1)
            $validatorConnector = if ($isLastValidator) { "└──" } else { "├──" }
            
            $output += "    $validatorConnector $($validator.validatorType) ($($validator.validatorId))"
            
            $prefix = if ($isLastValidator) { "        " } else { "    │   " }
            
            # Error Message
            $errMsg = if ($validator.errorMessage) { $validator.errorMessage } else { "(none)" }
            $output += "$prefix├── Error Message: `"$errMsg`""
            
            # Text (if different from ErrorMessage)
            if ($validator.text -and $validator.text -ne $validator.errorMessage) {
                $output += "$prefix├── Text: `"$($validator.text)`""
            }
            
            # Display
            if ($validator.display) {
                $output += "$prefix├── Display: $($validator.display)"
            }
            
            # Enabled
            if ($validator.enabled) {
                $output += "$prefix├── Enabled: $($validator.enabled)"
            }
            
            # Validation Group (if different from control level)
            if ($validator.validationGroup -and $validator.validationGroup -ne $control.validationGroup) {
                $output += "$prefix├── Validation Group: $($validator.validationGroup)"
            }
            
            # Type-specific properties
            if (@($validator.properties.PSObject.Properties).Count -gt 0) {
                $propArray = @($validator.properties.PSObject.Properties)
                
                for ($p = 0; $p -lt @($propArray).Count; $p++) {
                    $prop = $propArray[$p]
                    $isLastProp = ($p -eq @($propArray).Count - 1)
                    $propConnector = if ($isLastProp) { "└──" } else { "├──" }
                    
                    $output += "$prefix$propConnector $($prop.Name): $($prop.Value)"
                }
            }
        }
        
        $output += ""
    }
    
    # Print unbound validators
    if (@($data.unboundValidators).Count -gt 0) {
        $output += "=== Unbound Validators ==="
        $output += ""
        
        foreach ($validator in $data.unboundValidators) {
            $output += "$($validator.validatorType) ($($validator.validatorId))"
            
            if ($validator.validationGroup) {
                $output += "├── Validation Group: $($validator.validationGroup)"
            }
            
            # Properties
            if (@($validator.properties.PSObject.Properties).Count -gt 0) {
                $output += "└── Properties:"
                
                $propArray = @($validator.properties.PSObject.Properties)
                for ($p = 0; $p -lt @($propArray).Count; $p++) {
                    $prop = $propArray[$p]
                    $isLastProp = ($p -eq @($propArray).Count - 1)
                    $propConnector = if ($isLastProp) { "└──" } else { "├──" }
                    
                    $output += "    $propConnector $($prop.Name): $($prop.Value)"
                }
            }
            
            $output += ""
        }
    }
    
    return $output
}

# MAIN EXECUTION
if (-not (Test-Path $FilePath)) {
    Write-Error "File not found: $FilePath"
    exit 1
}

Write-Host "`nAnalyzing ASP.NET Validators from: $FilePath`n" -ForegroundColor Cyan

$content = Get-Content -Path $FilePath

# Build validation data
$validationData = Build-ValidationData -content $content

# Convert to JSON and save
$jsonOutput = $validationData | ConvertTo-Json -Depth 10
$jsonPath = [System.IO.Path]::ChangeExtension($FilePath, ".validation.json")
$jsonOutput | Out-File -FilePath $jsonPath -Encoding UTF8
Write-Host "`nJSON saved to: $jsonPath" -ForegroundColor Green

# Parse JSON back for tree building
$data = $jsonOutput | ConvertFrom-Json

# Build tree hierarchy
$treeLines = Build-TreeFromJson -data $data

# Display to console
Write-Host "`n=== Validation Tree ===`n" -ForegroundColor Cyan
$treeLines | ForEach-Object { Write-Host $_ }

# Save to markdown if output path specified
if ($OutputPath) {
    $mdContent = @()
    $mdContent += "# ASP.NET Validation Analysis"
    $mdContent += ""
    $mdContent += "**Source File:** ``$FilePath``"
    $mdContent += ""
    $mdContent += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $mdContent += ""
    $mdContent += "**Total Controls with Validators:** $($data.controls.Count)"
    $mdContent += "**Unbound Validators:** $($data.unboundValidators.Count)"
    $mdContent += ""
    $mdContent += "## Validation Tree"
    $mdContent += ""
    $mdContent += "``````"
    $mdContent += $treeLines
    $mdContent += "``````"
    
    $mdContent | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "`nMarkdown file saved to: $OutputPath" -ForegroundColor Green
}
else {
    # Auto-generate markdown filename
    $autoMdPath = [System.IO.Path]::ChangeExtension($FilePath, ".validation.md")
    $mdContent = @()
    $mdContent += "# ASP.NET Validation Analysis"
    $mdContent += ""
    $mdContent += "**Source File:** ``$FilePath``"
    $mdContent += ""
    $mdContent += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $mdContent += ""
    $mdContent += "**Total Controls with Validators:** $($data.controls.Count)"
    $mdContent += "**Unbound Validators:** $($data.unboundValidators.Count)"
    $mdContent += ""
    $mdContent += "## Validation Tree"
    $mdContent += ""
    $mdContent += "``````"
    $mdContent += $treeLines
    $mdContent += "``````"
    
    $mdContent | Out-File -FilePath $autoMdPath -Encoding UTF8
    Write-Host "`nMarkdown file saved to: $autoMdPath" -ForegroundColor Green
}