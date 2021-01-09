[#ftl]

[@addModule
    name="cdnlambda"
    description="Creates a CDN with the appropriate lambda extensions for cognito auth"
    provider=CFCOGNITO_PROVIDER
    properties=[
        {
            "Names" : "id",
            "Description" : "The Id of this CDN instance",
            "Type" : STRING_TYPE,
            "Mandatory" : true
        },
        {
            "Names" : "tier",
            "Description" : "The Id of this CDN instance",
            "Type" : STRING_TYPE,
            "Mandatory" : true
        },
        {
            "Names" : "instance",
            "Description" : "The id of the instance to create",
            "Type" : STRING_TYPE,
            "Default" : "default"
        },
        {
            "Names" : "originLink",
            "Description" : "The link to the origin for the CDN",
            "Children" : linkChildrenConfiguration
        },
        {
            "Names" : "userpoolClientLink",
            "Description" : "A link to a cognito Client for the CDN to use",
            "Children" : linkChildrenConfiguration
        },
        {
            "Names" : "artefactBaseUrl",
            "Description" : "The base Url to the release artefacts",
            "Type" : STRING_TYPE,
            "Default" : "https://github.com/hamlet-io/cloudfront-authorization-at-edge/releases/download"
        },
        {
            "Names" : "artefactVersion",
            "Description" : "The version of the artefacts to use",
            "Type" : STRING_TYPE,
            "Default" : "v0.0.3"
        }
    ]
/]

[#macro cfcognito_module_cdnlambda
        id
        tier
        instance
        originLink
        userpoolClientLink
        artefactBaseUrl
        artefactVersion
 ]

    [#local product = getActiveLayer(PRODUCT_LAYER_TYPE) ]
    [#local environment = getActiveLayer(ENVIRONMENT_LAYER_TYPE)]
    [#local segment = getActiveLayer(SEGMENT_LAYER_TYPE)]

    [#local namespace = formatName(product["Name"], environment["Name"], segment["Name"])]

    [#local edgeSettingsNamespace = formatName(id, "edgelambda" )]

    [#local cdnName = id ]
    [#local cdnDeploymentUnit = formatName(id, "cdn") ]

    [#local fakeOriginName = concatenate( [ id, "fake", "origin" ], "")]
    [#local cdnAuthName = concatenate( [id, "auth" ], "")]

    [#local lambdaCDNUnit = formatName( id, "lmb" ) ]
    [#local lambdaCDNDetails = [
        {
            "Name" : "check",
            "ZipFile" : "CheckAuthHandler.zip"
        },
        {
            "Name" : "headers",
            "ZipFile" : "HttpHeadersHandler.zip"
        },
        {
            "Name" : "parse",
            "ZipFile" : "ParseAuthHandler.zip"
        },
        {
            "Name" : "refresh",
            "ZipFile" : "RefreshAuthHandler.zip"
        },
        {
            "Name" : "signout",
            "ZipFile" : "SignOutHandler.zip"
        }
    ]]

    [#local lambdaUpdaterName = concatenate([ id, "config" ], "" )]
    [#local lambdaUpdateUrl = formatRelativePath( artefactBaseUrl, artefactVersion, "LambdaCodeUpdateHandler.zip" )]

    [#local lambdaCDNLinks = {}]
    [#list lambdaCDNDetails as lambdaDetail ]
        [#local lambdaCDNLinks += {
            lambdaDetail.Name : {
                "Tier" : tier,
                "Component" : concatenate([id, lambdaDetail.Name], "" ),
                "Function" : "event"
            }
        }]
    [/#list]

    [#local lambdaComponents = {
        lambdaUpdaterName : {
            "lambda" : {
                "deployment:Unit" : lambdaCDNUnit,
                "Instances" : {
                    instance : { }
                },
                "Functions" : {
                    "update" : {
                        "Extensions" : [ "_noenv", "cfcog_lambdaupdater" ],
                        "Handler" : "index.handler",
                        "RunTime" : "nodejs12.x",
                        "MemorySize": 256,
                        "Timeout": 300,
                        "VPCAccess" : false,
                        "PredefineLogGroup" : false,
                        "Permissions": {
                            "Decrypt": false,
                            "AsFile": false,
                            "AppData": false,
                            "AppPublic": false
                        },
                        "Links" :
                            lambdaCDNLinks

                    }
                },
                "Profiles" : {
                    "Placement" : "global"
                },
                "Image" : {
                    "Source" : "url",
                    "UrlSource" : {
                        "Url" : lambdaUpdateUrl
                    }
                }
            }
        }
    }]

    [#list lambdaCDNDetails as lambdaDetail ]

        [#local lambdaSourceUrl = formatRelativePath( artefactBaseUrl, artefactVersion, lambdaDetail.ZipFile )]

        [#local lambdaComponents += {
            lambdaCDNLinks[lambdaDetail.Name]["Component"] : {
                "lambda" : {
                    "deployment:Unit" : lambdaCDNUnit,
                    "Instances" : {
                        instance : { }
                    },
                    "Functions" : {
                        "event" : {
                            "DeploymentType": "EDGE",
                            "Handler" : "bundle.handler",
                            "Extensions" : [ "_noenv", "_cfcog_edge_config_" + lambdaDetail.Name ],
                            "RunTime" : "nodejs12.x",
                            "MemorySize": 128,
                            "Timeout": 5,
                            "VPCAccess" : false,
                            "PredefineLogGroup" : false,
                            "FixedCodeVersion" : {
                                "Enabled" : true,
                                "NewVersionOnDeploy" : true
                            },
                            "Permissions": {
                                "Decrypt": false,
                                "AsFile": false,
                                "AppData": false,
                                "AppPublic": false
                            },
                            "Links" : {
                                "updater" : {
                                    "Tier" : tier,
                                    "Component" : lambdaUpdaterName,
                                    "Function" : "update",
                                    "Role" : "none"
                                },
                                "userpoolClient" : userpoolClientLink
                            },
                            "Profiles" : {
                                "Placement" : "global"
                            },
                            "SettingNamespaces" : {
                                "base" : {
                                    "Name" : edgeSettingsNamespace,
                                    "Match" : "partial",
                                    "IncludeInNamespace" : {
                                        "Tier" : false,
                                        "Component" : false,
                                        "Type" : false,
                                        "SubComponent" : false,
                                        "Instance" : true,
                                        "Version" : false,
                                        "Name" : true
                                    }
                                }
                            }
                        }
                    },
                    "Image" : {
                        "Source" : "url",
                        "UrlSource" : {
                            "Url" : lambdaSourceUrl
                        }
                    }
                }
            }
        }]
    [/#list]

    [@loadModule

        settingSets=[
            {
                "Type" : "Settings",
                "Scope" : "Products",
                "Namespace" : formatName( namespace, (instance == "default")?then("", instance), edgeSettingsNamespace),
                "Settings" : {
                    "httpHeaders" : {
                        "Value" : {
                            "Content-Security-Policy": "default-src 'none'; img-src 'self'; script-src 'self' https://code.jquery.com https://stackpath.bootstrapcdn.com; style-src 'self' 'unsafe-inline' https://stackpath.bootstrapcdn.com; object-src 'none'; connect-src 'self' https://*.amazonaws.com https://*.amazoncognito.com",
                            "Strict-Transport-Security": "max-age=31536000; includeSubdomains; preload",
                            "Referrer-Policy": "same-origin",
                            "X-XSS-Protection": "1; mode=block",
                            "X-Frame-Options": "DENY",
                            "X-Content-Type-Options": "nosniff"
                        }
                    },
                    "logLevel" : "none",
                    "cookieCompatibility" : "amplify",
                    "additionalCookies" : {
                        "Value" : {}
                    },
                    "userPoolGroupName" : "",
                    "mode" : "staticSiteMode",
                    "redirectPathSignIn" : "/parseauth",
                    "redirectPathSignOut" : "/",
                    "redirectPathAuthRefresh" : "/refreshauth"
                }
            }
        ]

        blueprint={
            "Tiers" : {
                tier : {
                    "Components" : {
                        cdnName : {
                            "cdn" : {
                                "deployment:Unit" : cdnDeploymentUnit,
                                "Instances" : {
                                    instance : {}
                                },
                                "Links" : {
                                    "userpool" : userpoolClientLink
                                },
                                "Routes" : {
                                    "default" : {
                                        "PathPattern" : "_default",
                                        "Origin" : {
                                            "Link" : originLink
                                        },
                                        "EventHandlers" : {
                                            "check"  :
                                                lambdaCDNLinks["check"] + {
                                                    "Action" : "viewer-request"
                                                 },
                                            "headers"  :
                                                lambdaCDNLinks["headers"] + {
                                                    "Action" : "origin-response"
                                                }
                                        }
                                    },
                                    "redirectPath" : {
                                        "PathPattern" : "/parseauth",
                                        "Origin" : {
                                            "Link" : {
                                                "Tier" : tier,
                                                "Component" : fakeOriginName
                                            }
                                        },
                                        "EventHandlers" : {
                                            "parse"  :
                                                lambdaCDNLinks["parse"] + {
                                                    "Action" : "viewer-request"
                                                 }
                                        }
                                    },
                                    "refreshAuth" : {
                                        "PathPattern" : "/refreshauth",
                                        "Origin" : {
                                            "Link" : {
                                                "Tier" : tier,
                                                "Component" : fakeOriginName
                                            }
                                        },
                                        "EventHandlers" : {
                                            "refresh"  : lambdaCDNLinks["refresh"] + {
                                                    "Action" : "viewer-request"
                                                 }
                                        }
                                    },
                                    "signOut" : {
                                        "PathPattern" : "/signout",
                                        "Origin" : {
                                            "Link" : {
                                                "Tier" : tier,
                                                "Component" : fakeOriginName
                                            }
                                        },
                                        "EventHandlers" : {
                                            "signout" : lambdaCDNLinks["signout"] + {
                                                    "Action" : "viewer-request"
                                                }
                                        }
                                    }
                                }
                            }
                        },
                        fakeOriginName : {
                            "externalservice" : {
                                "Instances" : {
                                    instance : {}
                                },
                                "Properties" : {
                                    "url" : {
                                        "Key" : "FQDN",
                                        "Value" : "example.org"
                                    },
                                    "path" : {
                                        "Key" : "PATH",
                                        "Value" : ""
                                    }
                                },
                                "Profiles" : {
                                    "Placement" : "external"
                                }
                            }
                        },
                        cdnAuthName : {
                            "externalservice" : {
                                "Instances" : {
                                    instance : {}
                                },
                                "Profiles" : {
                                    "Placement" : "external"
                                },
                                "Links" : {
                                    "cdn" : {
                                        "Tier" : tier,
                                        "Component" : cdnName,
                                        "Route" : "default"
                                    }
                                },
                                "Extensions" : [ "_cfcog_cdnauth" ],
                                "SettingNamespaces" : {
                                    "base" : {
                                        "Name" : edgeSettingsNamespace,
                                        "Match" : "partial",
                                        "IncludeInNamespace" : {
                                            "Tier" : false,
                                            "Component" : false,
                                            "Type" : false,
                                            "SubComponent" : false,
                                            "Instance" : true,
                                            "Version" : false,
                                            "Name" : true
                                        }
                                    }
                                }
                            }
                        }
                    } +
                    lambdaComponents
                }
            },
            "PlacementProfiles": {
                "global": {
                    "default": {
                        "Provider": "aws",
                        "Region": "us-east-1",
                        "DeploymentFramework": "cf"
                    }
                }
            }
        }
    /]
[/#macro]
