Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "Home Directory Mapped To Drive Editor"
$form.Size = New-Object System.Drawing.Size(1600, 500)
$form.StartPosition = "CenterScreen"

# TreeView для OU
$treeView = New-Object System.Windows.Forms.TreeView
$treeView.Location = New-Object System.Drawing.Point(10, 10)
$treeView.Size = New-Object System.Drawing.Size(350, 400)
$treeView.Anchor = "Top,Left,Bottom"
$treeView.Add_AfterSelect({TreeView_AfterSelect})
$form.Controls.Add($treeView)

# Группа для редактирования
$groupBox = New-Object System.Windows.Forms.GroupBox
$groupBox.Location = New-Object System.Drawing.Point(370, 10)
$groupBox.Size = New-Object System.Drawing.Size(1000, 400)
$groupBox.Anchor = "Top,Right,Bottom"
$groupBox.Text = "OU Attributes"
$form.Controls.Add($groupBox)

# Метка и поле ввода
$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(10, 30)
$label.Size = New-Object System.Drawing.Size(580, 20)
$label.Text = "Home directory to be mapped to drive:"
$groupBox.Controls.Add($label)

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Location = New-Object System.Drawing.Point(10, 55)
$textBox.Size = New-Object System.Drawing.Size(980, 20)
$textBox.Name = "attrValue"
$groupBox.Controls.Add($textBox)

# Кнопка Apply
$buttonApply = New-Object System.Windows.Forms.Button
$buttonApply.Location = New-Object System.Drawing.Point(10, 90)
$buttonApply.Size = New-Object System.Drawing.Size(100, 30)
$buttonApply.Text = "Apply"
$buttonApply.Add_Click({ButtonApply_Click})
$buttonApply.Enabled = $false
$groupBox.Controls.Add($buttonApply)

# Статус бар
$statusBar = New-Object System.Windows.Forms.StatusBar
$statusBar.Text = "Loading domain structure..."
$form.Controls.Add($statusBar)

# Глобальные переменные
$global:selectedOU = $null
$global:initialValue = $null

# Загрузка структуры OU
function Load-OUStructure {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        
        $domain = Get-ADDomain
        $rootDSE = Get-ADRootDSE
        $domainDN = $domain.DistinguishedName
        
        $rootNode = New-Object System.Windows.Forms.TreeNode
        $rootNode.Text = $domain.Name
        $rootNode.Tag = $domainDN
        $rootNode.Name = "DOMAIN"
        $treeView.Nodes.Add($rootNode) | Out-Null
        
        Get-ADOrganizationalUnit -Filter * -SearchBase $domainDN -SearchScope OneLevel | Sort-Object Name | ForEach-Object {
            $ouNode = New-Object System.Windows.Forms.TreeNode
            $ouNode.Text = $_.Name
            $ouNode.Tag = $_.DistinguishedName
            $ouNode.Name = $_.Name
            $rootNode.Nodes.Add($ouNode) | Out-Null
            Add-SubOUs -parentNode $ouNode -parentDN $_.DistinguishedName
        }
        
        $rootNode.Expand()
        $statusBar.Text = "Ready. Domain: $($domain.Name)"
    }
    catch {
        $statusBar.Text = "Error: $_"
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to load AD structure: $_",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

# Рекурсивное добавление подразделений
function Add-SubOUs {
    param(
        [System.Windows.Forms.TreeNode]$parentNode,
        [string]$parentDN
    )
    
    $childOUs = Get-ADOrganizationalUnit -Filter * -SearchBase $parentDN -SearchScope OneLevel | Sort-Object Name
    foreach ($ou in $childOUs) {
        $childNode = New-Object System.Windows.Forms.TreeNode
        $childNode.Text = $ou.Name
        $childNode.Tag = $ou.DistinguishedName
        $childNode.Name = $ou.Name
        $parentNode.Nodes.Add($childNode) | Out-Null
        Add-SubOUs -parentNode $childNode -parentDN $ou.DistinguishedName
    }
}

# Обработчик выбора OU
function TreeView_AfterSelect {
    $selectedNode = $treeView.SelectedNode
    if ($selectedNode -and $selectedNode.Tag -like "OU=*") {
        $global:selectedOU = $selectedNode.Tag
        try {
            $ouObject = Get-ADObject -Identity $global:selectedOU -Properties homeDirectoryMappedToDrive
            $attrValue = $ouObject.homeDirectoryMappedToDrive
            $textBox.Text = $attrValue
            $global:initialValue = $attrValue
            $buttonApply.Enabled = $true
            $statusBar.Text = "Selected OU: $($selectedNode.Text)"
        }
        catch {
            $statusBar.Text = "Error reading attributes: $_"
            $textBox.Text = ""
            $buttonApply.Enabled = $false
        }
    }
    else {
        $textBox.Text = ""
        $buttonApply.Enabled = $false
        $global:selectedOU = $null
    }
}

# Обработчик кнопки Apply
function ButtonApply_Click {
    if (-not $global:selectedOU) {
        [System.Windows.Forms.MessageBox]::Show(
            "No OU selected!",
            "Warning",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }
    
    $newValue = $textBox.Text.Trim()
    
    if ($newValue -eq $global:initialValue) {
        $statusBar.Text = "No changes detected."
        return
    }
    
    try {
        Set-ADObject -Identity $global:selectedOU -Replace @{
            homeDirectoryMappedToDrive = $newValue
        }
        $global:initialValue = $newValue
        $statusBar.Text = "Attribute updated successfully for: $($treeView.SelectedNode.Text)"
    }
    catch {
        $statusBar.Text = "Update error: $_"
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to update attribute: $_",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

# Инициализация формы
Load-OUStructure
$form.Add_Shown({$form.Activate()})
[void]$form.ShowDialog()
