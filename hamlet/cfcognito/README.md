# cfcognito plugin

The cfcognito plugin enables cognito based authentication on a cloudfront distribution. More details on how this works can be found in the [README](../../README.md) for this repository

The components in the deployment include:

- A Primary CloudFront Distribution that is used as your public endpoint
- A collection of lambda@Edge functions which handle the authentication process with Cognito
- A cloudformation custom resource based on a lambda function which updates the lambda@Edge function configuration as part of the deployment process

You need to provide a user pool client through the userpoolClientLink which enables the integration between cognito and the CDN

Once the deployment has completed you will have Cloudfront distribution deployed which on any request to the distribution will require authentication via cognito.
Authentication sessions are stored in cookies and if not present the user will be redirected to the Cognito User portal to login.

You can combine this plugin with the [Github IDP module](https://github.com/gs-gs/github-idp/blob/master/hamlet/githubidp/README.md) to enable Github Auth on the distributions

This combination is also covered on the hamlet blog - https://docs.hamlet.io/blog/2021/02/10/static-sites-with-github-authentication-made-easy

## Usage

1. In your segment file install the plugin - Update the Ref based on the version you want to install. The AWS plugin is also required

    ```json
    {
        "Segment" : {
            "Plugins" : {
                "cognitoqs" : {
                    "Enabled" : true,
                    "Name" : "cfcognito",
                    "Priority" : 200,
                    "Required" : true,
                    "Source" : "git",
                    "Source:git" : {
                        "Url" : "https://github.com/hamlet-io/cloudfront-authorization-at-edge",
                        "Ref" : "v0.0.3",
                        "Path" : "hamlet/cognitoqs"
                    }
                },
                "aws" : {
                    "Enabled" : true,
                    "Name" : "aws",
                    "Priority" : 10,
                    "Required" : true,
                    "Source" : "git",
                    "Source:git" : {
                        "Url" : "https://github.com/hamlet-io/engine-plugin-aws",
                        "Ref" : "master",
                        "Path" : "aws/"
                    }
                }
            }
        }
    }
    ```

2. Create an Origin for the Cloudfront distribution. This can be a number of component types include Lb and spa.
    For example here is the configuration of a basic SPA

    ```json
    {
        "Tiers" : {
            "web" : {
                "docs-spa" : {
                    "spa" : {
                        "deployment:Unit" : "docs",
                        "Instances" : {
                            "default" : {}
                        }
                    }
                }
            }
        }
    }
    ```

3. Add an instance of the module ( you can add multiple instances if you need )
    Update the origin and userpool links to align with the origin and User pool client this module will be used with

    ```json
    {
        "Segment" : {
            "Modules" : {
                "docsite" : {
                    "Provider" : "cfcognito",
                    "Name" : "cdnlambda",
                    "Parameters" : {
                        "id" : {
                            "Key" : "id",
                            "Value" : "docsite"
                        },
                        "tier" : {
                            "Key" : "tier",
                            "Value" : "web"
                        },
                        "origin" : {
                            "Key" : "originLink",
                            "Value" : {
                                "Tier" : "web",
                                "Component" : "docs-spa",
                                "Instance" : "",
                                "Version" : ""
                            }
                        },
                        "userpool" : {
                            "Key" : "userpoolClientLink",
                            "Value" : {
                                "Tier" : "mgmt",
                                "Component" : "pool",
                                "Instance" : "",
                                "Version" : "",
                                "Client" : "cfcognito"
                            }
                        }
                    }
                }
            }
        }
    }
    ```

4. Create a user pool with a client specifically for the module. In your solution add the pool. This is a basic pool, feel free to extend it as required
    The link on the client is to an external service added in the module which provides the cognito authorisation allow list Urls

    ```json
    {
        "Tier" : {
            "mgmt" : {
                "Components" : {
                    "pool" : {
                        "userpool" : {
                            "deployment:Unit" : "pool",
                            "Instances" : {
                                "default" : {}
                            },
                            "MFA" : "optional",
                            "UnusedAccountTimeout" : 7,
                            "AdminCreatesUser" : true,
                            "Username" : {
                                "CaseSensitive" : false,
                                "Attributes" : [ "email" ],
                                "Aliases" : []
                            },
                            "HostedUI" : {},
                            "DefaultClient" : false,
                            "Schema" : {
                                "email" : {
                                    "DataType" : "String",
                                    "Mutable" : true,
                                    "Required" : true
                                },
                            },
                            "Clients" : {
                                "cfcognito" : {
                                    "ClientGenerateSecret" : false,
                                    "OAuth" : {
                                        "Scopes" : [
                                            "openid",
                                            "email",
                                            "profile"
                                        ],
                                        "Flows" : [ "code" ]
                                    },
                                    "AuthProviders" : [ "COGNITO" ],
                                    "Links" : {
                                        "docsite" : {
                                            "Tier" : "web",
                                            "Component" : "docsiteauth",
                                            "Instance" : "",
                                            "Version" : ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    ```

5. ( if using an SPA as the origin ) Add a link from the spa to the CDN for cache invalidation
    The id listed in the module is the Component ID of the CDN, the tier is from the tier in the module

    ```json
    {
        "Tiers" : {
            "web" : {
                "docs-spa" : {
                    "spa" : {
                        "Links" : {
                            "cdn" : {
                                "Tier" : "web",
                                "Component" : "docsite",
                                "Route" : "default",
                                "Direction" : "inbound"
                            }
                        }
                    }
                }
            }
        }
    }
    ```

6. With the module installed you should have two new deployments available which start with the module id

    ```bash
    hamlet deploy list-deployments -u docsite-.*
    ```

    ```bash
    | DeploymentGroup   | DeploymentUnit   | DeploymentProvider   | CurrentState   |
    |-------------------|------------------|----------------------|----------------|
    | solution          | docsite-cdn      | aws                  | deployed       |
    | application       | docsite-lmb      | aws                  | deployed       |
    ```

7. Run the deployment of the `docsite-lmb` deployment and then run the docsite-cdn deployment

    ```bash
    hamlet deploy run-deployments -u docsite-lmb && hamlet deploy run-deployments -u docsite-cdn
    ```

8. After this has completed run a deployment of your userpool component to update the authorised client URLs

    ```bash
    hamlet deploy run-deployments -u pool
    ```

9. Visit the CDN url and you should be redirected to the cognito login page to login

### Advanced usage

#### Instance Configuration

If you have a number of CDN based websites to deploy that all use the same configuration you can uses instances on the module components to remove the number of deployments required

To use instances add the following configuration to your solution. The example below uses an instance id of `techdocs` update this value based on your instance requirements
This configuration is based on the configuration in the usage guide and assumes you have that in place, these changes should be added to your existing solution instead of replacing them

```json

{
    "Tiers" : {
        "web" : {
            "Components" : {
                "docsite" : {
                    "cdn" : {
                        "Instances" : {
                            "techdocs" : {}
                        }
                    }
                },
                "docsiteauth" : {
                    "externalservice" : {
                        "Instances" : {
                            "techdocs" : {}
                        }
                    }
                },
                "docs-spa" : {
                    "spa" : {
                        "Instances" : {
                            "techdocs" : {}
                        }
                    }
                }
            }
        },
        "mgmt" : {
            "Components" : {
                "pool" : {
                    "userpool" : {
                        "Links" : {
                            "techdocs" : {
                                "Tier" : "web",
                                "Component" : "docsiteauth",
                                "Instance" : "techdocs",
                                "Version" : ""
                            }
                        }
                    }
                }
            }
        }
    }
}
```

This configuration will create a new CDN using the instance id techdocs and enable authentication using the existing lambda functions that you already deployed
