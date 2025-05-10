<#
.SYNOPSIS
    Получает историю входов пользователя в Active Directory.
.DESCRIPTION
    Скрипт ищет события входа (Event ID 4624) в журналах безопасности контроллеров домена
    и выводит время входа, имя компьютера и IP-адрес.
.PARAMETER Username
    Имя пользователя в домене (например, "ivanov" или "DOMAIN\ivanov").
.EXAMPLE
    .\Get-UserLogonHistory.ps1 -Username "ivanov"
    Ищет все входы пользователя "ivanov" в домене.
.NOTES
    Требуются права администратора на контроллерах домена.
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$Username
)

# Проверяем, запущен ли скрипт от имени администратора
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Скрипт требует запуска от имени администратора!"
    exit 1
}

# Получаем контроллеры домена
$DomainControllers = Get-ADDomainController -Filter *

# Создаем массив для хранения результатов
$LogonEvents = @()

foreach ($DC in $DomainControllers.HostName) {
    try {
        Write-Host "Поиск событий входа на контроллере домена: $DC" -ForegroundColor Cyan

        # Альтернативный способ фильтрации событий (без XPath, если он вызывает ошибки)
        $Filter = @{
            LogName = 'Security'
            ID = 4624
            StartTime = (Get-Date).AddDays(-30)  # Ищем за последние 30 дней (можно изменить)
        }

        $Events = Get-WinEvent -ComputerName $DC -FilterHashtable $Filter -ErrorAction SilentlyContinue | 
                  Where-Object { $_.Properties[5].Value -eq $Username }

        if ($Events) {
            foreach ($Event in $Events) {
                $EventData = @{
                    TimeCreated = $Event.TimeCreated
                    UserName    = $Username
                    Computer    = $Event.Properties[6].Value  # Workstation Name
                    IPAddress   = $Event.Properties[18].Value # IP Address (может быть пустым)
                }
                $LogonEvents += New-Object PSObject -Property $EventData
            }
        } else {
            Write-Host "На $DC не найдено событий входа для пользователя $Username." -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "Ошибка при подключении к $DC : $($_)"
    }
}

# Выводим результаты
if ($LogonEvents.Count -gt 0) {
    Write-Host "`nНайдено событий входа для пользователя '$Username':" -ForegroundColor Green
    $LogonEvents | Sort-Object TimeCreated -Descending | Format-Table -AutoSize -Property TimeCreated, UserName, Computer, IPAddress
} else {
    Write-Host "`nСобытий входа для пользователя '$Username' не найдено." -ForegroundColor Red
}