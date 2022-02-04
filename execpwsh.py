import subprocess
import json
import os
import base64

def convertto_base64(input_object):
    return str(base64.b64encode(json.dumps(input_object).encode('utf-8')), 'utf-8')

def handler(event, context):
    check_stderr = os.getenv('FAIL_IF_STDERR') == '1'
    out_none = os.getenv('OUTPUT') == 'NONE'
    out_stdout = os.getenv('OUTPUT') == 'STDOUT'
    out_stderr = os.getenv('OUTPUT') == 'STDERR'
    out_json = os.getenv('OUTPUT') == 'LAST_LINE_JSON'

    context_props = {
        'FunctionName': context.function_name,
        'FunctionVersion': context.function_version,
        'InvokedFunctionArn': context.invoked_function_arn,
        'MemoryLimitInMB': context.memory_limit_in_mb,
        'AwsRequestId': context.aws_request_id,
        'LogGroupName': context.log_group_name,
        'LogStreamName': context.log_stream_name,
    }

    encoded_event_and_context = convertto_base64({
        'event': event,
        'context': context_props,
    })

    cmd = ['pwsh', '-Command', f'& \u007b/scripts/init.ps1 {encoded_event_and_context}\u007d']
    o = subprocess.run(cmd, encoding='utf-8', stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout = o.stdout.strip()
    stderr = o.stderr.strip()

    if check_stderr and stderr:
        raise Exception(stderr)

    if out_none:
        return ''

    if out_stdout:
        return stdout

    if out_stderr:
        return stderr

    if out_json:
        return json.loads(stdout.split('\n')[-1])

    return {
        'stdout': stdout,
        'stderr': stderr
    }
