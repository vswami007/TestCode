param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath = "C:\Users\Admin\Downloads\PS-Scripts\Manage.aspx",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "C:\Users\Admin\Downloads\PS-Scripts\Manage_New_test.md"
)

# Self-closing HTML tags that don't need closing tags
$voidElements = @('area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 
                  'link', 'meta', 'param', 'source', 'track', 'wbr')

function Parse-Element {
    param([string]$line)
    
    $element = @{
        IsOpening = $false
        IsClosing = $false
        IsSelfClosing = $false
        ControlName = $null
        ID = $null
        Name = $null
        Text = $null
        RawTag = $null
    }
    
    $trimmed = $line.Trim()
    
    # Skip comments and empty lines
    if ([string]::IsNullOrWhiteSpace($trimmed) -or 
        $trimmed -match '^\s*<!--' -or 
        $trimmed -match '^\s*<%--') {
        return $null
    }
    
    # Check if it's a closing tag
    if ($trimmed -match '^</') {
        $element.IsClosing = $true
        if ($trimmed -match '</([^>]+)>') {
            $element.RawTag = $matches[1].Trim()
        }
        return $element
    }
    
    # Check if it's an opening tag
    if ($trimmed -match '^<([^\s/>]+)') {
        $element.IsOpening = $true
        $tagName = $matches[1]
        $element.RawTag = $tagName
        
        # Determine control name
        if ($tagName -match '^asp:(.+)') {
            $element.ControlName = "asp:$($matches[1])"
        }
        elseif ($tagName -match '^(\w+):(\w+)') {
            $element.ControlName = "$($matches[1]):$($matches[2])"
        }
        elseif ($tagName -match '^(%@\s*)?(\w+)') {
            $element.ControlName = $matches[2]
        }
        else {
            $element.ControlName = $tagName
        }
        
        # Extract ID attribute
        if ($trimmed -match '\bID\s*=\s*"([^"]+)"') {
            $element.ID = $matches[1]
        }
        elseif ($trimmed -match '\bID\s*=\s*''([^'']+)''') {
            $element.ID = $matches[1]
        }
        elseif ($trimmed -match '\bid\s*=\s*"([^"]+)"') {
            $element.ID = $matches[1]
        }
        elseif ($trimmed -match '\bid\s*=\s*''([^'']+)''') {
            $element.ID = $matches[1]
        }
        
        # Extract Name attribute
        if ($trimmed -match '\bName\s*=\s*"([^"]+)"') {
            $element.Name = $matches[1]
        }
        elseif ($trimmed -match '\bName\s*=\s*''([^'']+)''') {
            $element.Name = $matches[1]
        }
        elseif ($trimmed -match '\bname\s*=\s*"([^"]+)"') {
            $element.Name = $matches[1]
        }
        elseif ($trimmed -match '\bname\s*=\s*''([^'']+)''') {
            $element.Name = $matches[1]
        }
        
        # Extract Text attribute
        if ($trimmed -match '\bText\s*=\s*"([^"]+)"') {
            $element.Text = $matches[1]
        }
        elseif ($trimmed -match '\bText\s*=\s*''([^'']+)''') {
            $element.Text = $matches[1]
        }
        elseif ($trimmed -match '\btext\s*=\s*"([^"]+)"') {
            $element.Text = $matches[1]
        }
        elseif ($trimmed -match '\btext\s*=\s*''([^'']+)''') {
            $element.Text = $matches[1]
        }
        
        # Check if self-closing
        if ($trimmed -match '/>[\s]*$') {
            $element.IsSelfClosing = $true
        }
        # Check if it's a void element (self-closing by nature)
        elseif ($voidElements -contains $tagName.ToLower()) {
            $element.IsSelfClosing = $true
        }
        
        return $element
    }
    
    return $null
}

function Build-DisplayName {
    param($element)
    
    $identifier = $null
    
    # Priority: Text > Name > ID
    if ($element.Text) {
        $identifier = $element.Text
    }
    elseif ($element.Name) {
        $identifier = $element.Name
    }
    elseif ($element.ID) {
        $identifier = $element.ID
    }
    
    if ($identifier) {
        return "$identifier - $($element.ControlName)"
    }
    else {
        return $element.ControlName
    }
}

function Build-Hierarchy {
    param([string[]]$lines)
    
    $stack = @()
    $output = @()
    $level = 0
    
    foreach ($line in $lines) {
        $element = Parse-Element -line $line
        
        if ($null -eq $element) {
            continue
        }
        
        # Handle closing tag
        if ($element.IsClosing) {
            # Pop from stack
            if ($stack.Count -gt 0) {
                $stack = $stack[0..($stack.Count - 2)]
                $level = $stack.Count
            }
            continue
        }
        
        # Handle opening tag
        if ($element.IsOpening) {
            $displayName = Build-DisplayName -element $element
            
            $node = @{
                Name = $displayName
                Level = $level
                Element = $element
            }
            
            $output += $node
            
            # If not self-closing, push to stack and increase level
            if (-not $element.IsSelfClosing) {
                $stack += $element
                $level = $stack.Count
            }
        }
    }
    
    return $output
}

function Print-Tree {
    param(
        [array]$nodes,
        [switch]$ToMarkdown
    )
    
    $output = @()
    $lastLevel = -1
    $levelStates = @{}  # Track if each level has more siblings
    
    for ($i = 0; $i -lt $nodes.Count; $i++) {
        $node = $nodes[$i]
        $currentLevel = $node.Level
        
        # Determine if there are more siblings at this level
        $hasNextSibling = $false
        for ($j = $i + 1; $j -lt $nodes.Count; $j++) {
            if ($nodes[$j].Level -eq $currentLevel) {
                $hasNextSibling = $true
                break
            }
            elseif ($nodes[$j].Level -lt $currentLevel) {
                break
            }
        }
        
        $levelStates[$currentLevel] = $hasNextSibling
        
        # Build the prefix
        $prefix = ""
        for ($l = 0; $l -lt $currentLevel; $l++) {
            if ($levelStates.ContainsKey($l) -and $levelStates[$l]) {
                $prefix += "│   "
            }
            else {
                $prefix += "    "
            }
        }
        
        # Add connector
        if ($currentLevel -gt 0) {
            if ($hasNextSibling) {
                $prefix += "├── "
            }
            else {
                $prefix += "└── "
            }
        }
        
        $line = "$prefix$($node.Name)"
        
        if ($ToMarkdown) {
            $output += $line
        }
        else {
            Write-Host $line
        }
        
        $lastLevel = $currentLevel
    }
    
    if ($ToMarkdown) {
        return $output
    }
}

# Main execution
if (-not (Test-Path $FilePath)) {
    Write-Error "File not found: $FilePath"
    exit 1
}

Write-Host "Parsing ASP.NET markup from: $FilePath`n" -ForegroundColor Cyan

$content = Get-Content -Path $FilePath
$hierarchy = Build-Hierarchy -lines $content

if ($hierarchy.Count -eq 0) {
    Write-Host "No controls found in the file." -ForegroundColor Yellow
}
else {
    # Display to console
    Print-Tree -nodes $hierarchy
    
    # Write to markdown if output path specified
    if ($OutputPath) {
        $mdContent = @()
        $mdContent += "# ASP.NET Control Hierarchy"
        $mdContent += ""
        $mdContent += "**Source File:** ``$FilePath``"
        $mdContent += ""
        $mdContent += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $mdContent += ""
        $mdContent += "## Control Tree"
        $mdContent += ""
        $mdContent += "``````"
        $mdContent += Print-Tree -nodes $hierarchy -ToMarkdown
        $mdContent += "``````"
        
        $mdContent | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "`nMarkdown file saved to: $OutputPath" -ForegroundColor Green
    }
}