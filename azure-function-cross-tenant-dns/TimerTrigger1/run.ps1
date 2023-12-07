# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' porperty is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

## Variables 

$dnsZoneName = $env:DNSZONENAME ## Name of the private DNS zone that you want to replicate to the main tenant.

$tenant = $env:REMOTE_TENANT ## Tenant ID for the remote tenant
$clientid = $env:REMOTE_CLIENTID ## Client ID of  the application registration in the remote tenant
$secretvalue = $env:REMOTE_SECRETVALUE ## Client Secret Value of the application registration in the remote tenant
$remotesub = $env:REMOTE_SUBSCRIPTIONID ## SubscriptionID in the remote tenant that hosts the private DNS zone. 
$remoterg = $env:REMOTE_RGNAME ## Resource group in the remote tenant to hosts the private DNS zone. 

$subscriptionId = $env:MAIN_SUBSCRIPTIONID ## Subscription ID in the main tenant that hosts the private DNS zone
$resourceGroupName = $env:MAIN_RGNAME ## Resource group in the main tenant that hosts the private DNS zone
 

# Check each variable to make sure that the AppSettings are properly configured. 
$variables = @{
    "REMOTE_TENANT" = $env:REMOTE_TENANT
    "REMOTE_CLIENTID" = $env:REMOTE_CLIENTID
    "REMOTE_SECRETVALUE" = $env:REMOTE_SECRETVALUE
    "REMOTE_SUBSCRIPTIONID" = $env:REMOTE_SUBSCRIPTIONID
    "REMOTE_RGNAME" = $env:REMOTE_RGNAME
    "MAIN_SUBSCRIPTIONID" = $env:MAIN_SUBSCRIPTIONID
    "MAIN_RGNAME" = $env:MAIN_RGNAME
    "DNSZONENAME" = $env:DNSZONENAME
}


foreach ($var in $variables.GetEnumerator()) {
    if ([string]::IsNullOrEmpty($var.Value)) {
        Write-Host "Variable $($var.Key) does not have a value. Exiting function."
        exit
    }
}

# Authenticate with the remote tenant
try {
    # Convert to SecureString
    $securepass = ConvertTo-SecureString -String $secretvalue -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $clientid, $securepass

    # Connect to Azure Account
    Connect-AzAccount -ServicePrincipal -TenantId $Tenant -Credential $Credential -ErrorAction Stop

    # Set Azure Subscription Context
    Set-AzContext -SubscriptionID $remotesub -ErrorAction Stop
    Write-Host "Connected to Azure and set context to subscription ID: $remotesub"
    
} catch {
    # Handle the exception
    Write-Error "Cannot connect to $($tenant): $_"
    exit
}


# Get DNS zone records
try {
    # Get DNS zone records
    $RemoteDnsRecords = Get-AzPrivateDnsRecordSet -ResourceGroupName $remoterg -ZoneName $dnsZoneName -RecordType A -ErrorAction Stop
    Write-Host "Successfully retrieved DNS records from remote tenant: $($tenant)."
} catch {
    # Handle the exception
    Write-Error "An error occurred while retrieving DNS records: $_"
    exit
}


# Disconnect from the remote tenant
Disconnect-AzAccount -TenantId $tenant -ApplicationId $clientid


# Connect to the main tenant using a managed identity of the Azure Function
try { 
    if ($env:MSI_SECRET) {
        Disable-AzContextAutosave -Scope Process | Out-Null
        Connect-AzAccount -Identity
        $AzureIdentityContext = (Connect-AzAccount -Identity).context
        $AzureIdentityContext = Set-AzContext -SubscriptionName $AzureIdentityContext.Subscription -DefaultProfile $AzureIdentityContext
        
        # Set the context to the subscription where the Private DNS Zones are created
        Set-AzContext -SubscriptionId $subscriptionId
    }
    Write-Host "Successfully connected using the Managed Identity"
} catch {
    Write-Error "Couldn't connect using the Managed Identity: $_"
    exit
}

# Get all the existing records in the Private DNS Zone
try { 
    $MainDnsRecords = Get-AzPrivateDnsRecordSet -ResourceGroupName $resourceGroupName -ZoneName $dnsZoneName -RecordType A
} catch { 
    Write-Error "Couldn't get the existing records in the private DNS zone: $_"
}

# Add DNS records
$addCount = 0 
foreach ($record in $RemoteDnsRecords) { 

    if (!($MainDnsRecords | Where-Object {$_.Name -eq $record.name})) {
        
        #DNS Record doesn't exist yet, create record. 
        try {
            New-AzPrivateDNSRecordSet -ResourceGroupName $resourceGroupName `
                -name $record.name `
                -RecordType A `
                -ZoneName $dnsZoneName `
                -ttl $record.ttl `
                -privateDNSRecords (New-AzPrivateDNSRecordConfig -ipv4Address $($record.Records.ipv4Address)) `
                -metadata @{creationTime="$(Get-Date -format o)"; tenantID="$($tenant)"; targetResourceId="$($record.id)";}

            Write-Host "DNS record $($record.name) created successfully."

            $addCount++

        } catch {
            Write-Error "DNS record $($record.name) failed to create: $_"
        }

    }   
    
}

# Filter the records from the main DNS that belong to the specified tenant and no longer exist in the remote DNS records
$recordsToRemove = $MainDnsRecords | Where-Object {$_.Metadata.tenantID -eq $tenant -and -not ($RemoteDnsRecords.Name -contains $_.Name)}

# Iterate through the filtered records to remove
$removeCount = 0 
foreach ($record in $recordsToRemove) {
    try {
        Remove-AzPrivateDNSRecordSet -ResourceGroupName $resourceGroupName -ZoneName $dnsZoneName -Name $record.Name -RecordType A
        Write-Host "DNS Record $($record.Name) deleted"

        $removeCount++
    } catch {
        Write-Error "DNS Record $($record.Name) could not get deleted: $_"
    }
}

Write-host "Total DNS records added:" $addCount
Write-host "Total DNS records removed:" $removeCount


