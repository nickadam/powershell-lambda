$AWS = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($args)) | ConvertFrom-Json

$LambdaInput = $AWS.event
$LambdaContext = [PSCustomObject]@{
  "FunctionName" = $Env:AWS_LAMBDA_FUNCTION_NAME
  "FunctionVersion" = $Env:AWS_LAMBDA_FUNCTION_VERSION
  "InvokedFunctionArn" = $AWS.context.InvokedFunctionArn
  "MemoryLimitInMB" = $Env:AWS_LAMBDA_FUNCTION_MEMORY_SIZE
  "AwsRequestId" = $AWS.context.AwsRequestId
  "LogGroupName" = $Env:AWS_LAMBDA_LOG_GROUP_NAME
  "LogStreamName" = $Env:AWS_LAMBDA_LOG_STREAM_NAME
}

function Get-SECSecretBinary {
  param($AWSSecretName, $FileFullPath)
  $fso = New-Object -TypeName "System.IO.FileStream" -ArgumentList $FileFullPath, Create
  (Get-SECSecretValue -SecretId $AWSSecretName).SecretBinary.WriteTo($fso)
  $fso.Flush()
  $fso.Dispose()
  return Get-Item $FileFullPath
}

# execute script
. $Env:PWSH_SCRIPT
