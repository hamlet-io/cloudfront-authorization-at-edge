[#ftl]

[@addModule
    name="cdnlambda"
    description="Creates a CDN with the appropriate lambda extensions for cognito auth"
    provider=CFCOGNITO_PROVIDER
    properties=[
        {
            "Names" : "id",
            "Description" : "The component id of the CDN to create",
            "Type" : STRING_TYPE,
            "Mandatory" : true
        },
        {
            "Names" : "tier",
            "Description" : "The tier id of the CDN to create",
            "Type" : STRING_TYPE,
            "Mandatory" : true
        },
        {
            "Names" : "instance",
            "Description" : "The instance id of the CDB to create",
            "Type" : STRING_TYPE,
            "Default" : "default"
        },
        {
            "Names" : "originLink",
            "Description" : "The link to the origin for the CDN",
            "AttributeSet" : LINK_ATTRIBUTESET_TYPE
        },
        {
            "Names" : "userpoolClientLink",
            "Description" : "A link to a cognito Client for the CDN to use",
            "AttributeSet" : LINK_ATTRIBUTESET_TYPE
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
        },
        {
            "Names" : "enableSPAMode",
            "Description" : "Configure the module to work with SPAs behind the CDN",
            "Type" : BOOLEAN_TYPE,
            "Default" : false
        },
        {
            "Names" : "cookieCompatibility",
            "Description" : "Configure how cookies are provided - elasticsearch is a speical requirement",
            "Type" : STRING_TYPE,
            "Values" : [ "amplify", "elasticsearch" ],
            "Default" : "amplify"
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
        enableSPAMode
        cookieCompatibility
 ]

    [#local product = getActiveLayer(PRODUCT_LAYER_TYPE) ]
    [#local environment = getActiveLayer(ENVIRONMENT_LAYER_TYPE)]
    [#local segment = getActiveLayer(SEGMENT_LAYER_TYPE)]

    [#local namespace = formatName(product["Name"], environment["Name"], segment["Name"])]

    [#local edgeSettingsNamespace = formatName(id, "edgelambda" )]

    [#local cdnName = id ]
    [#local cdnDeploymentUnit = formatName(id, "cdn") ]

    [#local fakeOriginName = concatenate( [ id, "fake", "origin" ], "")]

    [#local fakeOriginLink = {
        "Tier" : tier,
        "Component" : fakeOriginName,
        "Instance" : instance
    }]

    [#local cdnAuthName = concatenate( [id, "auth" ], "")]

    [#local spaMode = enableSPAMode?then("spaMode", "staticSiteMode") ]

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
                "Instance" : instance,
                "Function" : "event"
            }
        }]
    [/#list]

    [#local lambdaComponents = {
        lambdaUpdaterName : {
            "lambda" : {
                "deployment:Unit" : lambdaCDNUnit,
                "Instances" : {
                    instance : {
                        "Functions" : {
                            "update" : {
                                "Links" : lambdaCDNLinks
                            }
                        }
                    }
                },
                "Functions" : {
                    "update" : {
                        "Extensions" : [ "_noenv", "_cfcog_lambdaupdater" ],
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
                        }
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
                        instance : {
                            "Functions" : {
                                "event" : {
                                    "Links" : {
                                        "userpoolClient" : userpoolClientLink
                                    }
                                }
                            }
                        }
                    }
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
                                }
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
                    "cookieCompatibility" : cookieCompatibility,
                    "additionalCookies" : {
                        "Value" : {}
                    },
                    "userPoolGroupName" : "",
                    "mode" : spaMode,
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
                                    instance : {
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
                                                        "Link" : fakeOriginLink
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
                                                        "Link" : fakeOriginLink
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
                                                        "Link" : fakeOriginLink
                                                    },
                                                    "EventHandlers" : {
                                                        "signout" : lambdaCDNLinks["signout"] + {
                                                                "Action" : "viewer-request"
                                                            }
                                                    }
                                                }
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
