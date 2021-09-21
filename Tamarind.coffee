Backbone = require 'backbone'
global.$ = require 'jquery'
Backbone.$  = $
global.Cookie = require 'js-cookie'
global.moment = require 'moment'
global._ = require 'underscore'

global.PouchDB = require('pouchdb-core')
PouchDB
  .plugin(require 'pouchdb-adapter-http')
  .plugin(require 'pouchdb-adapter-idb')
  .plugin(require 'pouchdb-mapreduce')
  .plugin(require 'pouchdb-replication')
  .plugin(require 'pouchdb-upsert')

{ CognitoIdentityClient } = require("@aws-sdk/client-cognito-identity")
{ fromCognitoIdentityPool } = require("@aws-sdk/credential-provider-cognito-identity")
{ DynamoDBClient } = require("@aws-sdk/client-dynamodb")
{ PutItemCommand, GetItemCommand, ScanCommand } = require("@aws-sdk/client-dynamodb")
{ marshall, unmarshall } = require("@aws-sdk/util-dynamodb")

Router = require './Router'


global.Tamarind =
  knownDatabaseServers:
    Zanzibar: "https://zanzibar.cococloud.co"
    Kigelia: "https://kigelia.cococloud.co"
    Ceshhar: "https://ceshhar.cococloud.co"
    Keep: "https://keep.cococloud.co"
    Local: "http://localhost:5984"
    MikeAWS:
      region: "us-east-1"
      IdentityPoolId: 'us-east-1:fda4bdc9-5adc-41a0-a34e-3156f7aa6691'
  gooseberryEndpoint: "https://f9l1259lmb.execute-api.us-east-1.amazonaws.com/gooseberry"

Tamarind.serverCredentials = {}
for name, url of Tamarind.knownDatabaseServers
  credentials = Cookie.get("#{name}-credentials")
  Tamarind.serverCredentials[name] = credentials if credentials



## GLOBAL FUNCTIONS ##
#
Tamarind.canCreateDesignDoc = =>
  Tamarind.database.put {_id:"_design/test"}
  .then (result) =>
    Tamarind.database.remove 
      _id: result.id
      _rev: result.rev
    Promise.resolve(true)
  .catch (error) => 
    if error.status is 403
      Promise.resolve(false)


Tamarind.setupDatabase = (serverName, databaseOrGatewayName) =>
  Tamarind.serverName = serverName

  if Tamarind.knownDatabaseServers[Tamarind.serverName].IdentityPoolId # DynamoDB
    Tamarind.database = null

    unless Tamarind.dynamoDBClient?
      if Cookie.get("password") is "hungry for fruit" or prompt("Password:").toLowerCase() is "hungry for fruit"
        Cookie.set("password","hungry for fruit")


        region = Tamarind.knownDatabaseServers[Tamarind.serverName].region
        Tamarind.dynamoDBClient = new DynamoDBClient(
          region: region
          credentials: fromCognitoIdentityPool(
            client: new CognitoIdentityClient({region})
            identityPoolId: Tamarind.knownDatabaseServers[Tamarind.serverName].IdentityPoolId
          )
        )

    Tamarind.updateGateway(databaseOrGatewayName)

  else
    Tamarind.dynamoDBClient = null
    username = Cookie.get("username")
    password = Cookie.get("password")
    unless username and password
      Tamarind.targetUrl = document.location.hash.replace(/#/,"")
      return router.navigate "server/#{Tamarind.serverName}", trigger:true
    serverUrlWithCredentials = "#{Tamarind.knownDatabaseServers[serverName]}".replace(/:\/\//, "://#{username}:#{password}@")
    Tamarind.database = new PouchDB("#{serverUrlWithCredentials}/#{databaseOrGatewayName}")
    Tamarind.databaseName = databaseOrGatewayName
    Tamarind.databasePlugins = await Tamarind.database.allDocs
      startkey: "_design/plugin-"
      endkey: "_design/plugin-\uf000"
      include_docs: true
    .then (result) =>
      Promise.resolve(_(result?.rows).pluck "doc")

Tamarind.updateCurrentGateway = =>
  Tamarind.updateGateway(Tamarind.gateway.gatewayName)

Tamarind.updateGateway = (gatewayName) =>
  result = await Tamarind.dynamoDBClient.send(
    new GetItemCommand(
      TableName: "Configurations"
      Key: 
        gatewayName:
          "S": gatewayName
    )
  )
  Tamarind.gateway = unmarshall(result.Item)

Tamarind.updateQuestionSetForCurrentGateway = (questionSet, options) =>
  await Tamarind.updateCurrentGateway()
  Tamarind.gateway["Question Sets"][questionSet.label] = questionSet
  if options?.delete is true
    delete Tamarind.gateway["Question Sets"][questionSet.label]

  Tamarind.dynamoDBClient.send(
    new PutItemCommand(
      TableName: "Configurations"
      Item: marshall(Tamarind.gateway)
    )
  )

global.router = new Router()
Backbone.history.start()
