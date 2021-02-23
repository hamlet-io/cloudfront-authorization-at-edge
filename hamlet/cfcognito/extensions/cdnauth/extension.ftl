[#ftl]

[@addExtension
    id="cfcog_cdnauth"
    aliases=[
        "_cfcog_cdnauth"
    ]
    description=[
        "Returns the authorisation URL required for cognito user pool configuration"
    ]
    supportedTypes=[
        EXTERNALSERVICE_COMPONENT_TYPE
    ]
/]

[#macro shared_extension_cfcog_cdnauth_deployment_setup occurrence ]

    [@DefaultLinkVariables enabled=false /]
    [@DefaultCoreVariables enabled=false /]
    [@DefaultEnvironmentVariables enabled=false /]
    [@DefaultBaselineVariables enabled=false /]

    [#local callBackUrls = []]
    [#local logoutUrls = []]

    [#local redirectPathSignIn = "parseauth" ]
    [#local redirectPathSignOut = "signout" ]

    [#if _context.Links["cdn"]?has_content ]
        [#local linkUrl = _context.Links["cdn"].State.Attributes["URL"] ]
        [#local callBackUrls += [ formatRelativePath(linkUrl, redirectPathSignIn) ]]
        [#local logoutUrls += [ formatRelativePath(linkUrl, redirectPathSignOut) ]]
    [#else]
        [#local callBackUrls += [ "https://placeholder_${occurrence.Core.Id}" ] ]
        [#local logoutUrls += [ "https://placeholder_${occurrence.Core.Id}" ] ]
    [/#if]

    [@Settings
        {
            "AUTH_CALLBACK_URL" : callBackUrls?join(","),
            "AUTH_SIGNOUT_URL" : logoutUrls?join(",")
        }
    /]

[/#macro]
