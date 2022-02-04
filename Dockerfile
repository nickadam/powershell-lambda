FROM mcr.microsoft.com/powershell:latest AS pip

RUN apt-get update && apt-get install -y python3-pip

RUN mkdir /function && \
  pip install --target /function awslambdaric

FROM mcr.microsoft.com/powershell:latest

RUN apt-get update && \
  apt-get install -y python3 && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install powershell modules
RUN pwsh -command 'Install-Module -Name AWS.Tools.Installer -Scope AllUsers -Force \
  && Install-AWSToolsModule AWS.Tools.SecretsManager,AWS.Tools.S3 -Scope AllUsers -Force'

COPY --from=pip /function /function

COPY execpwsh.py /function/

WORKDIR /function

###
# make you changes below here
###

# install linux utilities
# RUN apt-get update && apt-get install -y myutility

# install powershell modules
# RUN pwsh -command 'Install-Module -Name MyModule -Scope AllUsers -Force'

# Install addtional AWSToolsModule
# RUN pwsh -command 'Install-AWSToolsModule AWS.Tools.SimpleNotificationService -Scope AllUsers -Force'

# copy your script into the image and set environment variables
COPY init.ps1 example_script.ps1 /scripts/
ENV PWSH_SCRIPT=/scripts/example_script.ps1 \
  FAIL_IF_STDERR=0 \
  OUTPUT=Default

###
# do not change below this line
###

ENTRYPOINT [ "/usr/bin/python3", "-m", "awslambdaric" ]

CMD [ "execpwsh.handler" ]
