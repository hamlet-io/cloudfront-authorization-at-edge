[#ftl]

[@addExtension
    id="cfcog_edge_config"
    aliases=[
        "_cfcog_edge_config_signout",
        "_cfcog_edge_config_refresh",
        "_cfcog_edge_config_check",
        "_cfcog_edge_config_parse"
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

[#macro shared_extension_cfcog_edge_config_deployment_setup occurrence ]

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

    [#-- preexisitng links --]
    [#local links = _context.Links ]

    [#local userPoolClient = links["userpoolClient"]!{} ]
    [#if userPoolClient?has_content && ! ( userPoolClient.Core.Type == USERPOOL_CLIENT_COMPONENT_TYPE ) ]
        [@fatal
            message="User pool client link is not to userpool client"
            context={
                "Type" : userPoolClient.Core.Type,
                "LinkComponentName" : userPoolClient.Core.FullName
            }
        /]
    [/#if]

    [#local userPoolArn = (userPoolClient.State.Attributes["USER_POOL_ARN"])!"" ]
    [#local userPoolClientId = (userPoolClient.State.Attributes["CLIENT"])!"" ]
    [#local userPoolDomain = (userPoolClient.State.Attributes["UI_FQDN"])!"" ]
    [#local userPoolClientSecretRef = (userPoolClient.State.Attributes["SECRET_REF"])!"" ]
    [#local oAuthScopes = ((userPoolClient.State.Attributes["LB_OAUTH_SCOPE"])!"")?split(" ")]

    [#-- Configuration --]
    [#local httpHeaders = _context.DefaultEnvironment["HTTPHEADERS"]!""]
    [#local logLevel = _context.DefaultEnvironment["LOGLEVEL"]!"" ]
    [#local cookieCompatibility = _context.DefaultEnvironment["COOKIECOMPATIBILITY"]!"" ]
    [#local additionalCookies = _context.DefaultEnvironment["ADDITONALCOOKIES"]!"" ]
    [#local userPoolGroupName = _context.DefaultEnvironment["USERPOOLGROUPNAME"]!"" ]
    [#local mode = _context.DefaultEnvironment["MODE"]!"" ]

    [#local nonceSigningSecret = (segmentSeed + runId)?truncate_c(16, "")]

    [#local redirectPathSignIn = _context.DefaultEnvironment["REDIRECTPATHSIGNIN"]!"" ]
    [#local redirectPathSignOut  = _context.DefaultEnvironment["REDIRECTPATHSIGNOUT"]!""]
    [#local redirectPathAuthRefresh = _context.DefaultEnvironment["REDIRECTPATHAUTHREFRESH"]!"" ]

    [@lambdaAttributes
        createVersionInExtension=true
    /]

    [#if deploymentSubsetRequired(occurrence.Core.Type, true) ]

        [#local configuration = getJSON(
            {
                "userPoolArn": userPoolArn,
                "clientId": userPoolClientId,
                "clientSecret": userPoolClientSecretRef,
                "cognitoAuthDomain": userPoolDomain,
                "oauthScopes": oAuthScopes,
                "redirectPathSignIn": redirectPathSignIn,
                "redirectPathSignOut": redirectPathSignOut,
                "redirectPathAuthRefresh": redirectPathAuthRefresh,
                "cookieSettings":       {
                    "idToken": r'Path=/; Secure; HttpOnly; SameSite=Lax',
                    "accessToken": r'Path=/; Secure; HttpOnly; SameSite=Lax',
                    "refreshToken": r'Path=/; Secure; HttpOnly; SameSite=Lax',
                    "nonce": r'Path=/; Secure; HttpOnly; SameSite=Lax'
                },
                "mode": mode,
                "httpHeaders": httpHeaders,
                "logLevel": logLevel,
                "nonceSigningSecret": nonceSigningSecret,
                "cookieCompatibility": cookieCompatibility,
                "additionalCookies": additionalCookies,
                "requiredGroup": userPoolGroupName
            }
        )]

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
