<#
.SYNOPSIS 
	Creates Inf with desired configuration for a user right assignment that is passed to secedit.exe
.PARAMETER InfPolicy
	Name of user rights assignment policy
.PARAMETER UserList
	List of user9s0 to be added to policy
.PARAMETER FilePath
	Path Inf will be created
.EXAMPLE
	Out-UserRightsInf -InfPolicy SeTrustedCredManAccessPrivilege -UserList Contoso\User1 -FilePath C:\Scratch\Secedit.Inf
#>
Function Out-UserRightsInf
{
	Param
	(
		[string]$InfPolicy,

		[string]$UserList,

		[string]$FilePath
	)

$infTemplate =@"
[Unicode]
Unicode=yes
[Privilege Rights]
$InfPolicy = $UserList
[Version]
signature="`$CHICAGO`$"
Revision=1
"@

    Out-File -InputObject $infTemplate -FilePath $FilePath -Encoding unicode
}

<#
.SYNOPSIS
    Converts SID to friendly name
.PARAMETER SID
    SID of identity being converted
.EXAMPLE
    ConvertTo-LocalFriendlyName -SID 'S-1-5-21-3623811015-3361044348-30300820-1013'
#>
Function ConvertTo-LocalFriendlyName
{
	Param
	(
		[string[]]$SID		
	)
	 
    Foreach($id in $SID)
    {        
        If($id -ne $null -and $id -match "S-")
        {   
            $sIDobj = [System.Security.Principal.SecurityIdentifier]($id.trim())
            $user = $sIDobj.Translate([System.Security.Principal.NTAccount])
            $user.value            
        }
    }
}

<#
.SYNOPSIS
	Parses Inf produced by secedit.exe /export and returns an object of identites assigned to a user rights assignment policy
.PARAMETER FilePath
	Path to Inf
.EXAMPLE
	Get-UserRightsAssignment -FilePath C:\seceditOutput.inf
#>
function Get-UserRightsAssignment
{
	[cmdletbinding()]
	Param
	(
		[string]$FilePath
	)

    $ini = @{}
    switch -regex -file $FilePath
    {
        "^\[(.+)\]" # Section
        {
            $section = $matches[1]
            $ini[$section] = @{}
            $CommentCount = 0
        }
        "^(;.*)$" # Comment
        {
            $value = $matches[1]
            $commentCount = $commentCount + 1
            $name = "Comment" + $commentCount
            $ini[$section][$name] = $value
        } 
        "(.+?)\s*=(.*)" # Key
        {
            
            $name,$value =  $matches[1..2] -replace "\*"
            $ini[$section][$name] = @(ConvertTo-LocalFriendlyName $($value -split ','))
        }
    }
    return $ini
}

<#
.SYNOPSIS
	Converts policy names that match the GUI the abbreviated names used by secedit.exe 
#>
Function Get-AssignmentFriendlyNames
{
    Get-Content -Path $PSScriptRoot\UserRightsFriendlyNameConversions.psd1 -Raw | ConvertFrom-StringData
}

<#
.SYNOPSIS
	Returns an object of the identities assigned to a user rights assignment
.PARAMETER Policy
	Name of the policy to inspect
.PARAMETER Areas
	Specifies the security areas to be inspect. Possible values: "SECURITYPOLICY","GROUP_MGMT","USER_RIGHTS","REGKEYS","FILESTORE","SERVICES"
.EXAMPLE
	Get-USRPolicy -Policy Create_a_token_object -Areas USER_RIGHTS
#>
Function Get-USRPolicy
{
    [cmdletbinding()]
    Param
    (
        [parameter(Mandatory = $true)]
		[ValidateSet("Create_a_token_object","Access_this_computer_from_the_network","Change_the_system_time","Deny_log_on_as_a_batch_job","Deny_log_on_through_Remote_Desktop_Services","Create_global_object","Remove_computer_from_docking_station","Deny_access_to_this_computer_form_the_network","Act_as_part_of_the_operating_system","Modify_firmware_environment_values","Deny_log_on_locally","Access_Credential_Manager_as_a_trusted_caller","Restore_files_and_directories","Change_the_time_zone","Replace_a_process_level_token","Manage_auditing_and_security_log","Create_symbolic_links","Modify_an_object_label","Enable_computer_and_user_accounts_to_be_trusted_for_delegation","Generate_security_audits","Increase_a_process_working_set","Take_ownership_of_files_or_other_objects","Bypass_traverse_checking","Log_on_as_a_service","Shut_down_the_system","Lock_pages_in_memory","Impersonate_a_client_after_authentication","Profile_system_performance","Debug_programs","Profile_single_process","Allow_log_on_through_Remote_Desktop_Services","Allow_log_on_locally","Increase_scheduling_priority","Synchronize_directory_service_data","Add_workstations_to_domain","Adjust_memory_quotas_for_a_process","Perform_volume_maintenance_tasks","Load_and_unload_device_drivers","Force_shutdown_from_a_remote_system","Back_up_files_and_directories","Create_a_pagefile","Deny_log_on_as_a_service","Log_on_as_a_batch_job","Create_permanent_shared_objects")]
		[System.String]
		$Policy,
        
        [parameter(Mandatory = $true)]
        [ValidateSet("SECURITYPOLICY","GROUP_MGMT","USER_RIGHTS","REGKEYS","FILESTORE","SERVICES")]
        [string]$Areas = "USER_Rights"
    )

    $policyList = Get-AssignmentFriendlyNames
    $policyName = $policyList[$Policy]

    $currentUserRights = ([system.IO.Path]::GetTempFileName()).Replace('tmp','inf')    

    $secedit = secedit.exe /export /cfg $currentUserRights /areas $areas

    $userRights = (Get-UserRightsAssignment $currentUserRights).'Privilege Rights'    

    [psobject]@{
        Policy = $policyName
        PolicyFriendlyName = $Policy
        Identity = $userRights[$policyName]
    }    
}

<#
.SYNOPSIS
	Wrapper around secedit.exe
.PARAMETER UserRightsToAddInf
	Inf with desired user rights assignment policy configuration
.PARAMETER SeceditOutput
	Path to secedit log file output
.EXAMPLE
	Invoke-Secedit -UserRightsToAddInf C:\secedit.inf -SeceditOutput C:\seceditLog.txt
#>
Function Invoke-Secedit
{
    [cmdletbinding()]
    Param
    (
        [string]$UserRightsToAddInf,
        [string]$SeceditOutput
    )

    $tempDB = "$env:TEMP\DscSecedit.sdb"   
    
    Start-Process secedit.exe -ArgumentList "/configure /db $tempDB /cfg $userRightsToAddInf" -RedirectStandardOutput $seceditOutput -NoNewWindow -Wait
}

<#
.SYNOPSIS
	Returns all the possible user rights assignments.
	Only used for dev purposes
	Not used by code
#>
Function Get-PrivilegeRightsList
{
    $currentUserRights = ([system.IO.Path]::GetTempFileName()).Replace('tmp','inf')

    $secedit = secedit.exe /export /cfg $currentUserRights /areas USER_RIGHTS

    $UserRights = (Get-UserRightsAssignment $currentUserRights).'Privilege Rights'

    $userRights.Keys
}