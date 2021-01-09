[#ftl]

[@addExtension
    id="cfcog_httpheader_config"
    aliases=[
        "_cfcog_edge_config_headers"
    ]
    description=[
        "Updates the lambda@edge functions to include the deployment specific configuration",
        "The Lambda update will publish a verison of lambda which we then save as outputs"
    ]
    supportedTypes=[
        LAMBDA_COMPONENT_TYPE,
        LAMBDA_FUNCTION_COMPONENT_TYPE
    ]
/]

[#macro shared_extension_cfcog_httpheader_config_deployment_setup occurrence ]

    [@DefaultLinkVariables enabled=false /]
    [@DefaultCoreVariables enabled=false /]
    [@DefaultEnvironmentVariables enabled=false /]
    [@DefaultBaselineVariables enabled=false /]

    [#local lambdaResourceId = occurrence.State.Resources["function"].Id ]
    [#local lambdaVersionId = occurrence.State.Resources["version"].Id ]

    [#-- deployment specific links --]
    [#local solution = occurrence.Configuration.Solution]
    [#local linkTargets = getLinkTargets(occurrence, solution.Links, false )]

    [#local updaterFunctionId = linkTargets["updater"].State.Resources["function"].Id ]

    [#-- Configuration --]
    [#local httpHeaders = _context.DefaultEnvironment["HTTPHEADERS"]!{}]
    [#local logLevel = _context.DefaultEnvironment["LOGLEVEL"]!"" ]

    [#-- Make the version creation depdedent on the updater --]
    [@lambdaAttributes
        createVersionInExtension=true
    /]

    [#local configuration = getJSON(
        {
            "httpHeaders": httpHeaders,
            "logLevel" : logLevel
        }
    )]

    [#if deploymentSubsetRequired(occurrence.Core.Type, true) ]

        [@cfResource
            id=lambdaVersionId
            type="Custom::LambdaCodeUpdate"
            properties={
                "ServiceToken" : getReference(updaterFunctionId, ARN_ATTRIBUTE_TYPE),
                "LambdaFunction" : getReference(lambdaResourceId, ARN_ATTRIBUTE_TYPE),
                "Version" : "",
                "Configuration" : configuration
            }
            outputs={
                REFERENCE_ATTRIBUTE_TYPE : {
                    "Attribute" : "FunctionArn"
                },
                ARN_ATTRIBUTE_TYPE : {
                    "Attribute" : "FunctionArn"
                }
            }
        /]

        [@cfResource
            id=formatLambdaPermissionId(occurrence, "replication")
            type="AWS::Lambda::Permission"
            properties=
            {
                "FunctionName" : {
                    "Fn::GetAtt": [
                        lambdaVersionId,
                        "FunctionArn"
                    ]
                },
                "Action" : "lambda:GetFunction",
                "Principal" : "replicator.lambda.amazonaws.com"
            }
            outputs={
                REFERENCE_ATTRIBUTE_TYPE : {
                    "UseRef" : true
                }
            }
        /]

    [/#if]

[/#macro]
