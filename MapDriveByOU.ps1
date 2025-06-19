# Импорт модуля ActiveDirectory
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

# Получение DN текущего пользователя
$user = Get-ADUser $env:USERNAME -Properties DistinguishedName
$userDN = $user.DistinguishedName

# Извлечение DN родительского OU
$ouDN = $userDN -replace '^CN=[^,]+,', ''

# Получение атрибута OU
try {
    $ou = Get-ADOrganizationalUnit $ouDN -Properties extensionAttribute1
    $path = $ou.extensionAttribute1
    
    if ($path) {
        $driveLetter = "Z:"
        # Проверка и подключение диска
        if (Test-Path $driveLetter) { net use $driveLetter /delete /y }
        net use $driveLetter $path /persistent:yes
    } else {
        Write-Warning "Атрибут папки отдела не задан в OU: $ouDN"
    }
} catch {
    Write-Warning "Ошибка при доступе к OU: $($_.Exception.Message)"
}