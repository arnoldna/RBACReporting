<#
    NAME 
        AzureSubscriptionRBACAudit.ps1    

    SYNOPSIS
        Gathers Azure Role Based Access Control Data for Audit Purposes.

    DESCRIPTION
        Gathers Azure Role Based Access Control Data for Audit Purposes. The script will prompt the user to 
        select a subscription to run the audit against. The user is only presented the scriptions currently 
        available to the users credentials.

    OUTPUTS
        Outputs a CSV file in the same directory that the script is located in. The CSV file will have the 
        name of the subscription in its title followed by "Azure RBAC Audit.csv"

#>

## Functions
Function Login {
    <#
    .SYNOPSIS
        Runs the Azure Login Command
    #>
    $needLogin = $true
    Try {
        $content = Get-AzContext
        if ($content) {
            $needLogin = ([string]::IsNullOrEmpty($content.Account))
        } 
    } 
    Catch {
        if ($_ -like "*Login-AzAccount to login*") {
            $needLogin = $true
        } 
        else {
            throw
        }
    }

    if ($needLogin) {
        #Login-AzAccount
        Select-Azure
    }
}
Function Select-Azure{
    <#
    .SYNOPSIS
        Provides a list of Azure Environments for the user to select from.
        AzureGov, AzureCloud, etc.
    #>
    Clear-Host
    $ErrorActionPreference = 'SilentlyContinue'
    $Menu = 0
    $AzEnvironment = @(Get-AzEnvironment |select-object Name)
    Write-Host "Please select the Azure Environment you want to use:" -ForegroundColor Green;
    ForEach-Object {Write-Host ""}
    $AzEnvironment | ForEach-Object {Write-Host "[$($Menu)]" -ForegroundColor Cyan -NoNewline ; Write-host ". $($_.Name)"; $Menu++; }
    ForEach-Object {Write-Host ""}
    ForEach-Object {Write-Host "[Q]" -ForegroundColor Red -NoNewline ; Write-host ". To quit."}
    ForEach-Object {Write-Host ""}
    $selection = Read-Host "Please select the Azure Environment Number - Valid numbers are 0 - $($AzEnvironment.count -1) or Q to quit"
    If ($selection -eq 'Q') { 
        Clear-Host
        Exit
    }
    If ($AzEnvironment.item($selection) -ne $null)
    { Connect-AzAccount -EnvironmentName  $AzEnvironment.item($selection).Name -ErrorAction Stop}
}

Function Select-Subs {
    <#
    .SYNOPSIS
        Provides a list of subscriptions for the user to select from.
    #>
    Clear-Host
    $ErrorActionPreference = 'SilentlyContinue'
    $Menu = 0
    $Subs = @(Get-AzSubscription | Select-Object Name, ID, TenantId)

    Write-Host "Please select the subscription you want to use:" -ForegroundColor Green;
    ForEach-Object {Write-Host ""}
    $Subs | ForEach-Object {Write-Host "[$($Menu)]" -ForegroundColor Cyan -NoNewline ; Write-host ". $($_.Name)"; $Menu++; }
    ForEach-Object {Write-Host ""}
    ForEach-Object {Write-Host "[S]" -ForegroundColor Yellow -NoNewline ; Write-host ". To switch Azure Account."}
    ForEach-Object {Write-Host ""}
    ForEach-Object {Write-Host "[Q]" -ForegroundColor Red -NoNewline ; Write-host ". To quit."}
    ForEach-Object {Write-Host ""}
    $selection = Read-Host "Please select the Subscription Number - Valid numbers are 0 - $($Subs.count -1), S to switch Azure Account or Q to quit"
    If ($selection -eq 'S') { 
        Get-AzContext | ForEach-Object {Clear-AzContext -Scope CurrentUser -Force}
        Select-Azure
        Select-Subs
    }
    If ($selection -eq 'Q') { 
        Clear-Host
        Exit
    }
    If ($Subs.item($selection) -ne $null)
    { Return @{name = $subs[$selection].Name; ID = $subs[$selection].ID} 
    }
}

Function Resolve-AzAdGroupMembers {
    <#
    .SYNOPSIS
        Gets list of Azure Active Directory groups and its members
    #>
    param(
        [guid]
        $GroupObjectId,
        $GroupList = (Get-AzADGroup)
    )
    $VerbosePreference = 'continue'
    Write-Verbose -Message ('Resolving {0}' -f $GroupObjectId)
    $group = $GroupList | Where-Object -Property Id -EQ -Value $GroupObjectId
    $groupMembers = Get-AzADGroupMember -GroupObjectId $GroupObjectId
    Write-Verbose -Message ('Found members {0}' -f ($groupMembers.DisplayName -join ', '))
    $parentGroup = @{
        Id          = $group.Id
        DisplayName = $group.DisplayName
    }
    $groupMembers |
    Where-Object -Property Type -NE -Value Group |
    Select-Object -Property Id, DisplayName, @{
        Name       = 'ParentGroup'
        Expression = { $parentGroup }
    }
    $groupMembers |
    Where-Object -Property type -EQ -Value Group |
    ForEach-Object -Process {
        Resolve-AzAdGroupMembers -GroupObjectId $_.Id -GroupList $GroupList 
    }
}

## Main Part of Script

Write-Output "Running login script"
Login       # Login to Azure

$SubscriptionSelection = Select-Subs        # Runs function to get Azure subscriptions available to user and sets the subscription to the users choice.
Select-AzSubscription -SubscriptionName $SubscriptionSelection.Name -ErrorAction Stop

## Get current Azure Subscription Name to be used in reporting output
$Azuresub = $SubscriptionSelection.Name -replace , '/'

ForEach-Object {Write-Host "Getting Role Assignments" -ForegroundColor Yellow -NoNewline}
ForEach-Object {Write-Host "`r`n========================================" -ForegroundColor Yellow -NoNewline}
ForEach-Object {Write-Host "`nThis process can take at least 20 minutes to run since it is checking every Azure Role and its corresponding assignments." -ForegroundColor Yellow -NoNewline }
$roleAssignments = Get-AzRoleAssignment -IncludeClassicAdministrators

## Loop through each role assignment to determine the user assigned to that role. 
$members = $roleAssignments | ForEach-Object -Process {
    Write-Verbose -Message ('Processing Assignment {0}' -f $_.RoleDefinitionName)
    $roleAssignment = $_
    
    if($roleAssignment.ObjectType -eq 'Group') 
    {
        Resolve-AzAdGroupMembers -GroupObjectId $roleAssignment.ObjectId `
        | Select-Object -Property Id,
            DisplayName,
            ParentGroup, @{
                Name       = 'RoleDefinitionName'
                Expression = { $roleAssignment.RoleDefinitionName }
            }, @{
                Name       = 'Scope'
                Expression = { $roleAssignment.Scope }
            }, @{
                Name       = 'CanDelegate'
                Expression = { $roleAssignment.CanDelegate }
            }
    }
    else 
    {
        $roleAssignment | Select-Object -Property @{
                Name       = 'Id'
                Expression = { $_.ObjectId }
            },
            DisplayName, 
            @{
                Name       = 'RoleDefinitionName'
                Expression = { $roleAssignment.RoleDefinitionName }
            },
            Scope, 
            CanDelegate
    }
}

# Generating CSV Output for reporting
$outtbl = @()
$members | ForEach-Object {
    $x = New-Object PSObject -Property @{ 
        Subscription = $Azuresub -join ','
        ActiveDirID = $_.Id -join ','
        DisplayName = $_.DisplayName  -join ','
        ParentGroupID = $_.ParentGroup.Id  -join ','
        ParentGroupDisplayName = $_.ParentGroup.DisplayName  -join ','
        RoleDefinitionName = $_.RoleDefinitionName  -join ','
        Scope = $_.Scope
        }
        $outtbl += $x
    }
$outtbl | Select-Object Subscription,ActiveDirID,DisplayName,ParentGroupID,ParentGroupDisplayName,RoleDefinitionName, Scope |Export-CSV -path $($PSScriptRoot + "\" + "$Azuresub" + " Azure RBAC Audit.csv") -NoTypeInformation
ForEach-Object {Write-Host " `r`nRBAC Audit has completed. Your CSV file is located: $($PSScriptRoot + "\" + "$Azuresub" + " Azure RBAC Audit.csv")" -ForegroundColor Green -NoNewline }