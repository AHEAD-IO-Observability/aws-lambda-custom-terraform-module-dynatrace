"""Minimal demo handler.

The application code is intentionally unaware of Dynatrace — instrumentation is
applied entirely at deploy time by the module (OneAgent layer + handler wrapper).
The module repoints the function handler at the Dynatrace wrapper and preserves
this entry point in the ORIGINAL_HANDLER environment variable.
"""


def handler(event, context):
    return {
        "statusCode": 200,
        "body": "hello from a Dynatrace-instrumented lambda",
    }
