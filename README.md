# powershell-lambda
A different way to run PowerShell scripts in AWS lambda

AWS does not provide a container image for PowerShell lambdas, [823](https://github.com/aws/aws-lambda-dotnet/issues/823).
This project provides a starting point to run PowerShell scripts from a container image.

## Why

- Lambda's deployed via zip have a limitation of 50MB compressed and 250MB expanded. Container images can be as large as 10GB!
- Some powershell modules have an install process that relies on having write access to powershell shared objects, [PSWSMan](https://www.powershellgallery.com/packages/PSWSMan/2.2.0) for example. Once you deploy your script to AWS, you only have write access /tmp. Such a module could be installed in a container image prior to execution.
- Generic linux utilities and other arbitrary files are simpler to include into a container image as part of a build process compared to using lambda layers or bundling into a required module.

## How it works

- The image is based on mcr.microsoft.com/powershell, python3 is installed and a small python program implements the runtime interface.
- The python program encodes the input event and context properties and executes a powershell init script.
- The init.ps1 script decodes the input and context and sets variables that would normally be available in a zip deployment, i.e. `$LambdaInput` and `$LambdaContext`. This init script is also a nice place to include some generic functions or [dot source](https://devblogs.microsoft.com/scripting/how-to-reuse-windows-powershell-functions-in-scripts/) other scripts not packages as modules. As an example, one function is included in init.ps1 that can write an AWS Secrets Manager binary secret value to a file, `Get-SECSecretBinary`.
- init.ps1 calls your script and does whatever you want.
- Finally the python program then collects stdout and stderr and returns an object.

## Some differences to consider

### The object returned
A zipped powershell lambda will return the last object output. If you wrote a script with `@(1,2,3)`, you would get `3`. This program will return all the stdout and stderr by default. Lambda responses are limited to 6MB. If you have a script with a lot of output, this could be a problem.

There are 5 different modes of output to choose from by setting the environment variable `OUTPUT`.
- `Default`, object with stdout and stderr `{"stdout": "", "stderr": ""}`
- `NONE`, empty string
- `STDOUT`, just standard out as a string
- `STDERR`, just standard error as a string
- `LAST_LINE_JSON`, your object built from the last line of stdout

`LAST_LINE_JSON` is very useful in getting data back from powershell as an arbitrary object. All you have to do is ensure the last line contains a string that can be parsed as JSON, i.e. `@(1,2,3) | ConvertTo-Json -Compress` results in `[1,2,3]`.

### Return codes
Script return codes are not evaluated to determine if your script succeeded or failed.

### Throwing errors
By default no errors will be thrown if your script fails, you will simply see the stdout and stderr. You can change this behavior by setting the environment variable `FAIL_IF_STDERR` to 1. Any output in stderr will result in an exception being raised with the content of stderr. You can get output into stderr by calling `throw` or `Write-Error` in your PowerShell script.

### Missing resources
The list of resources below are not available in `$LambdaContext` as would be when using a zipped PowerShell lambda:
- RemainingTime
- Identity
- ClientContext
- Logger

### Speed
_or lack thereof_

Running scripts this way is slow. You can speed things up increasing memory but don't expect sub-second response times. Even a basic script with 4GB of memory allocated will take a couple seconds to return and consume ~150MB. The motivation behind this project is largely to handle cron triggered tasks that start and complete within 15 minutes. AWS limits lambda's maximum execution time to 15 minutes.

## Environment variables
Name | Required | Acceptable values | Value if not specified | Description
---|---|---|---|---
PWSH_SCRIPT | No | any string | /script/example_script.ps1 | Path to script that will be executed, see `example_script.ps1`
FAIL_IF_STDERR | No | 1, 0 | 0 | Cause the lambda function to fail if there is any output in STDERR
OUTPUT | No | Default, NONE, STDOUT, STDERR, LAST_LINE_JSON | Default (both stdout and stderr) | Specify if you want no output, just stdout, just stderr, or to parse the last line of your script output as a JSON object

## How-to

Prerequisites
- Ability to build linux container images: docker, podman, rancher desktop, etc.
- [AWS CLI](https://aws.amazon.com/cli/)
- Access to lambda and ECR
- A lambda execution role (or the ability to create one), [AWS docs](https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html)

Download, clone, or fork this repo.
```
git clone https://github.com/nickadam/powershell-lambda.git
cd powershell-lambda
```
Add your script and whatever.

Modify the Dockerfile or init.ps1 to suite your needs, [Dockerfile reference](https://docs.docker.com/engine/reference/builder/):
- Install linux utilities using `apt-get`
- Install powershell modules using `Install-Module -Name MyModule -Scope AllUsers -Force`
  - `-Scope AllUsers` is very important since you lambda will execute as any user
- Install additional AWS modules using `Install-AWSToolsModule`, S3 and SecretsManager are installed by default
- Set desired default environment variables
- COPY your script, or just replace example_script.ps1 in the Dockerfile
- Add functions or whatever to init.ps1

Build, tag, and push your image, [AWS docs](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html).
```
docker build -t myimage:latest .
docker tag myimage:latest <accountid>.dkr.ecr.<region>.amazonaws.com/myimage:latest
docker push <accountid>.dkr.ecr.<region>.amazonaws.com/myimage:latest
```

Create lambda function
```
aws lambda create-function --region <region> --function-name MyFunction --package-type Image --code ImageUri=<accountid>.dkr.ecr.<region>.amazonaws.com/myimage:latest --role <execution role arn>
```

Run the function
```
aws lambda invoke --function-name MyFunction --payload '{ "key": "value" }' response.json
```

If you make changes - build, tag, push AND **update the function**. Updating the container image latest tag does not update the function.
```
aws lambda update-function-code --region <region> --function-name MyFunction <accountid>.dkr.ecr.<region>.amazonaws.com/myimage:latest
```

## Test locally
[AWS Docs](https://docs.aws.amazon.com/lambda/latest/dg/images-test.html)

Download RIE
```
mkdir -p ~/.aws-lambda-rie && curl -Lo ~/.aws-lambda-rie/aws-lambda-rie \
https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie \
&& chmod +x ~/.aws-lambda-rie/aws-lambda-rie
```
Run the container
```
docker run --rm \
  -e AWS_LAMBDA_RUNTIME_API=/aws-lambda/aws-lambda-rie \
  -v ~/.aws-lambda-rie:/aws-lambda \
  -p 9000:8080 \
  --entrypoint /aws-lambda/aws-lambda-rie \
  python3 -m awslambdaric execpwsh.handler
```
Make a request
```
curl -s -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" -d '{ "key": "value" }'
```
