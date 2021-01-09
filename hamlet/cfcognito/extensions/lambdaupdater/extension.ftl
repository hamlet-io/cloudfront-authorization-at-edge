[#ftl]

[@addExtension
    id="cfcog_lambdaupdater"
    aliases=[
        "_cfcog_lambdaupdater"
    ]
    description=[
        "Applies extra permissions on the lambda updater function to allow access to edge functions"
    ]
    supportedTypes=[
        LAMBDA_COMPONENT_TYPE,
        LAMBDA_FUNCTION_COMPONENT_TYPE
    ]
/]

[#macro shared_extension_cfcog_lambdaupdater_deployment_setup occurrence ]

    [#local solution = occurrence.Configuration.Solution ]

    [#list solution.Links as id, link ]
        [#local linkTarget = getLinkTarget(occurrence, link, false)]
        [#if linkTarget?has_content]
            [#if linkTarget.Core.Type == LAMBDA_FUNCTION_COMPONENT_TYPE ]
                [@Policy
                    [
                        getPolicyStatement(
                            [
                                "lambda:GetFunction",
                                "lambda:UpdateFunctionCode"
                            ],
                            getReference(linkTarget.State.Resources["function"].Id, ARN_ATTRIBUTE_TYPE)
                        )
                    ]
                /]
            [/#if]
        [/#if]
    [/#list]
[/#macro]
