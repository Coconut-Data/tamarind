Backbone = require 'backbone'
Passphrase = require 'xkcd-passphrase'

crypto = require('crypto')

{ CognitoIdentityClient } = require("@aws-sdk/client-cognito-identity")
{ fromCognitoIdentityPool } = require("@aws-sdk/credential-provider-cognito-identity")
{DynamoDBClient,ScanCommand,PutItemCommand, CreateTableCommand, DescribeTableCommand} = require("@aws-sdk/client-dynamodb")
{ marshall, unmarshall } = require("@aws-sdk/util-dynamodb")

class ServerView extends Backbone.View

  render: =>
    await @login()
    .catch =>
      @renderLoginForm()
      Promise.resolve()
    .then (databaseList) =>
      @$el.html "
        <style>
          li {
            padding-top: 1em;
          }
          li a{
            font-size: 1em;
          }
        </style>
        <h1>Select a #{if @isDynamoDB then "Gateway" else "database"}:</h1>
        #{
          if @isDynamoDB
            (for gateway in databaseList
              "<li style='height:50px;'><a href='#gateway/#{Tamarind.serverName}/#{gateway}'>#{gateway}</a></li>"
            ).join("")
          else
            (for database in databaseList
              continue unless _(database).isString()
              continue if database.startsWith("_")
              continue if database.match(/backup/)
              continue if database.startsWith("plugin")
              "<li><a href='#database/#{Tamarind.serverName}/#{database}'>#{database}</a></li>"
            ).join("")
        }
        <h1>or select a configured result:</h1>
      "
    $("#title").html "
      <a href='#'>#{Tamarind.serverName}</a> 
    "

  renderLoginForm: =>
    @$el.html "
      <h1>#{Tamarind.serverName}</h1>
      <div style='margin-left:100px; margin-top:100px; id='usernamePassword'>
        <div>
          Server Username: <input id='username'/>
        </div>
        <div>
          Server Password: <input type='password' id='password'/>
        </div>
        <div>
          Application Username: <input id='applicationUsername'/>
        </div>
        <div>
          Application Password: <input type='password' id='applicationPassword'/>
        </div>
        <button id='login'>Login</button>
      </div>
    "

  events: =>
    "click #login": "updateUsernamePassword"
    "click #newDatabase": "newDatabase"
    "click #newGateway": "newGateway"
    "click #daily-button": "updateTasks"
    "click #five-minutes-button": "updateTasks"

  getServerUrlWithCredentials: =>
    username = Cookie.get("username")
    password = Cookie.get("password")
    "#{Tamarind.knownDatabaseServers[Tamarind.serverName]}".replace(/:\/\//, "://#{username}:#{password}@")



  updateUsernamePassword: =>
    Cookie.set "username", @$('#username').val()
    Cookie.set "password", @$('#password').val()

    Cookie.set "applicationUsername", @$('#applicationUsername').val()
    Cookie.set "applicationPassword", @$('#applicationPassword').val()

    if Tamarind.targetUrl
      targetUrl = Tamarind.targetUrl
      Tamarind.targetUrl = null
      return router.navigate targetUrl, trigger:true

    @render()

  login: =>
    @username = Cookie.get("username")
    @password = Cookie.get("password")

    unless @username and @password
      return Promise.reject()

    @fetchDatabaseList()

  fetchDatabaseList: =>
    new Promise (resolve,reject) =>
      if Tamarind.knownDatabaseServers[Tamarind.serverName].IdentityPoolId? # DynamoDB
        @isDynamoDB = true

        region = Tamarind.knownDatabaseServers[Tamarind.serverName].region
        identityPoolId = Tamarind.knownDatabaseServers[Tamarind.serverName].IdentityPoolId

        @dynamoDBClient = new DynamoDBClient(
          region: region
          credentials: fromCognitoIdentityPool(
            client: new CognitoIdentityClient({region})
            identityPoolId: identityPoolId
          )
        )

        gatewayConfigurations = await @dynamoDBClient.send(
          new ScanCommand(
            TableName: "Configurations"
          )
        )

        Tamarind.gateways = {}

        for item in gatewayConfigurations.Items
          unmarshalledItem = unmarshall(item)
          Tamarind.gateways[unmarshalledItem.gatewayName] = unmarshalledItem

        resolve(gatewayName for gatewayName,details of Tamarind.gateways)

      else
        @isDynamoDB = false
        fetch "#{Tamarind.knownDatabaseServers[Tamarind.serverName]}/_all_dbs",
          method: 'GET'
          credentials: 'include'
          headers:
            'content-type': 'application/json'
            authorization: "Basic #{btoa("#{@username}:#{@password}")}"
        .catch (error) =>
          reject(error)
        .then (response) =>
          if response.status is 401
            reject(response.statusText)
          else
            result = await response.json()
            resolve(result)

module.exports = ServerView
