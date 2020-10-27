<#
.SYNOPSIS 
    Sample runbook to search for a specific event id in an Azure VM

.DESCRIPTION
    This runbook looks for a specific event ID in an Azure VM so that an action
    could be taken when this event happens.
    It is designed to be used with the Manage-MonitorRunbook utility runbook so that
    it will get resumed on specific intervals defined by the schedules on the Manage-MonitorRunbook
    runbook. This runbook should have a tag to indicate that it should get resumed by
    that runbook.

	This runbook depends on the Connect-AzureVM utility runbook that is available from the gallery.

.PARAMETER ServiceName
    Name of the Azure Cloud Service where the VM is located

.PARAMETER VMName
    Name of the Azure VM
        
.PARAMETER AzureCredentialSetting
    A credential asset name containing an Org Id username / password with access to this Azure subscription.

.PARAMETER SubscriptionName
    The name of the Azure subscription
    
.PARAMETER EventID
    The specific event ID to search for. This sample looks for this event ID
    
.PARAMETER LogName
    The event log name. Example System
    
.PARAMETER Source
    The event log source. Example EventLog
 
.PARAMETER VMCredentialSetting
    A credential asset name that has access to the Azure VM 

.EXAMPLE
    Watch-EventID -ServiceName "Finance" -VMName 'FinanceWeb1' -AzureCredentialSetting 'FinanceOrgID' -SubscriptionName "Visual Studio Ultimate with MSDN" -EventID "63" -LogName "System" -Source "EventLog" -VMCredentialSetting "FinanceVMCredential"
#>
workflow Watch-EventID
{
  Param ( 
        [String] $ServiceName,
        [String] $VMName,
        [String] $AzureCredentialSetting,
        [String] $SubscriptionName,
        [String] $EventID,
        [String] $LogName,
        [String] $Source,
        [String] $VMCredentialSetting
    )

	# The start time is used to ensure we only look for events after this specific time.
	# This would be a common pattern in any monitor runbooks that are developed.
    $StartTime = Get-Date
    Try
    {
        While (1)
        {         
            $OrgIDCredential = Get-AutomationPSCredential -Name $AzureCredentialSetting
            if ($OrgIDCredential -eq $null)
            {
                throw "Could not retrieve '$AzureCredentialSetting' credential asset. Check that you created this first in the Automation service."
            }
    
            $Credential = Get-AutomationPSCredential -Name $VMCredentialSetting
            if ($Credential -eq $null)
            {
                throw "Could not retrieve '$VMCredential' credential asset. Check that you created this first in the Automation service."
            }     
             
            # Get the uri of the Azure VM to connect to by calling the Connect-AzureVM utility runbook                 
            $Uri =  Connect-AzureVM `
                -AzureOrgIdCredential $OrgIDCredential `
                -AzureSubscriptionName $SubscriptionName `
                -ServiceName $ServiceName `
                -VMName $VMName
            
			# Script to run on the remote VM looking for an event ID
            $ScriptBlock = {Param($EventID, $StartTime,$LogName,$Source) Get-EventLog -LogName $LogName -Source $Source -InstanceID $EventID -After $StartTime -Newest 1} 
        
			# Run this ScirptBlock on the remote VM
            $EventResult = InlineScript {
                 Invoke-command -ConnectionUri $Using:Uri -Credential $Using:Credential -ScriptBlock $Using:ScriptBlock -ArgumentList $Using:EventID, $Using:StartTime, $Using:LogName, $Using:Source
            }
             
            if ($EventResult)
            {
                # Set new start time to be after this event. This is to ensure that only new events are looked for.
                $StartTime = $EventResult.TimeGenerated

                # Take whatever action is required when this event happens...
                # You should use the Start-AzureAutomationRunbook cmdlet to trigger a new runbook asynchrously
                # so that this runbook returns immediately and this runbook can suspend itself looking for new work
                # at the next call from the Manage-MonitorRunbook runbook
                # Start-AzureAutomationRunbook -AutomationAccountName <System.String> -Name <System.String> [-Parameters <System.Collections.IDictionary>] 
                 
                Write-Output "Event ID found... Taking action"
            }
            
            # Suspending workflow so Automation minutes are not used up continously
            # This workflow will be resumed by a separate monitor runbook (Manage-MonitorRunbook) on a specific schedule
            Write-Verbose "Suspending workflow..."
            
            # Clearing credentials since these can't be persisted with suspend currently
            $Credential = $Null
            $OrgIDCredential = $Null
            Suspend-Workflow
        }
    }
    Catch
    {  
        # This runbook should never suspend due to an error as it will
        # get resumed by the monitor runbook when it shouldn't. You should not set Erroractionpreference  =  stop for this runbook
		# as it will cause the runbook to suspend when it shouldn't for monitor runbooks.
        # Writing out an error in this case 
        Write-Error ($_)
    }
      
}