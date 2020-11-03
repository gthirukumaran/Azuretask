param(
    $sourceSubscriptionID,
    $targetSubscriptionID,
    $sourceresourceGroup,
    $targetresourceGroup
)
 
function Get-AzCachedAccessToken()
{
    $azureContext = Get-AzContext
    $currentAzureProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile;
    $currentAzureProfileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($currentAzureProfile);
    $azureAccessToken = $currentAzureProfileClient.AcquireAccessToken($azureContext.Tenant.Id).AccessToken;
    $azureAccessToken
 
}
 
function Get-AzBearerToken()
{
    $ErrorActionPreference = 'Stop'
    ('Bearer {0}' -f (Get-AzCachedAccessToken))
}
 
$currentContext = (Get-AzContext | select Subscription).Subscription.Id
 
if(!$currentContext){
    Login-AzAccount -SubscriptionId $sourceSubscriptionID
}
if($currentContext -ne $sourceSubscriptionID){
    Select-AzSubscription -SubscriptionId $sourceSubscriptionID
}
 
$resources = (Get-AzResource -ResourceGroupName $sourceresourceGroup)
foreach($resource in $resources){
 
    Write-Host "Checking resource type: $($resource.ResourceType) with resource name: $($resource.Name)"
 
    $resourceID = @()
    $resourceID += $resource.resourceId
    $body = @{
     resources=$resourceID ;
     targetResourceGroup= "/subscriptions/$targetSubscriptionID/resourceGroups/$targetresourceGroup"
    }
 
    #add try catch
    Try{
    $return = Invoke-WebRequest -Uri "https://management.azure.com/subscriptions/$sourceSubscriptionID/resourceGroups/$sourceresourceGroup/validateMoveResources?api-version=2018-02-01" -method Post -Body (ConvertTo-Json $body) -ContentType "application/json" -Headers @{Authorization = (Get-AzBearerToken)}
    }
    Catch{
        $statusCode = $null
        $statusCode = $_.Exception.Message
    }
 
    if($statusCode){
        [int]$retryTime = ($return.RawContent -split "Retry-After: ")[1].Substring(0,2)
        $retryTime = $retryTime+5
 
        do{
            Write-Host Waiting for status...
            Start-Sleep -Seconds $retryTime
 
            $validationUrl = ($return.RawContent -split "Location: ")[-1]
            $validationUrl = $validationUrl.Replace('`r`n','')
            Try{
            $status = Invoke-WebRequest -Uri $validationUrl -method Get -ContentType "application/json" -Headers @{Authorization = (Get-AzBearerToken)}
            $statusCode = $status.StatusCode
            }
            Catch{
                $statusCode = 205
                $Exc = $_.Exception
            }
        }
        while($statusCode -eq 202)
 
        if($statusCode -eq 205){
            Write-host "Resource type $($resource.ResourceType) with resource name $($resource.Name)can not be moved. Error: $Exc" -ForegroundColor Red
        }
        elseif($statusCode -eq 204){
            Write-Host "Resource type $($resource.ResourceType) with resource name $($resource.Name) can be moved to new subscrtipion" -ForegroundColor Green
        }
        else{
            Write-Host "Another problem occured for resource type $($resource.ResourceType) with resource name $($resource.Name). Error: $Exc"
        }
    }
    else{
        Write-Host "Another error occured. Error: $statusCode"
    }
}
