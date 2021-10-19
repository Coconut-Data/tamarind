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
  .plugin(require 'pouchdb-changes-filter')
  .plugin(require 'pouchdb-find')

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
Tamarind.canCreateDesignDoc = (database) =>
  database or= Tamarind.database
  database.put {_id:"_design/test"}
  .then (result) =>
    database.remove 
      _id: result.id
      _rev: result.rev
    Promise.resolve(true)
  .catch (error) => 
    if error.status is 403
      Promise.resolve(false)


Tamarind.setupDatabase = (serverName, databaseOrGatewayName) =>
  Tamarind.serverName = serverName

  if Tamarind.knownDatabaseServers[Tamarind.serverName].IdentityPoolId # DynamoDB
    Tamarind.setupDynamoDBClient(serverName, databaseOrGatewayName)
  else
    Tamarind.setupCouchDBClient(serverName, databaseOrGatewayName)

Tamarind.setupDynamoDBClient = (serverName, databaseOrGatewayName) =>
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

Tamarind.setupCouchDBClient = (serverName, databaseOrGatewayName) =>
  Tamarind.dynamoDBClient = null
  username = Cookie.get("username")
  password = Cookie.get("password")
  unless username and password
    Tamarind.targetUrl = document.location.hash.replace(/#/,"")
    return router.navigate "server/#{Tamarind.serverName}", trigger:true
  serverUrlWithCredentials = "#{Tamarind.knownDatabaseServers[serverName]}".replace(/:\/\//, "://#{username}:#{password}@")

  Tamarind.localDatabaseMirror = await Tamarind.getLocalMirrorForCouchDB(serverUrlWithCredentials, databaseOrGatewayName)
  Tamarind.database = Tamarind.localDatabaseMirror.remoteDatabase
  Tamarind.databaseName = databaseOrGatewayName

Tamarind.getLocalMirrorForCouchDB = (serverUrlWithCredentials, databaseName) =>
  remoteDatabase = new PouchDB("#{serverUrlWithCredentials}/#{databaseName}")
  localDatabaseMirror = new PouchDB("#{serverUrlWithCredentials.replace(/^.*@/,"").replace(/^.*\/\//,"")}/#{databaseName}")
  localDatabaseMirror.remoteDatabase = remoteDatabase
  remoteDatabase.localDatabaseMirror = localDatabaseMirror

  if (await localDatabaseMirror.get("_local/availableFields").catch (error) => Promise.resolve false)
    # Do this in the background 10 seconds later in case there have been updates
    _.delay =>
      Tamarind.updateAvailableFields(remoteDatabase, localDatabaseMirror)
    , 10000
  else
    await Tamarind.updateAvailableFields(remoteDatabase, localDatabaseMirror)

  last_seq = await localDatabaseMirror.get "_local/remote_last_seq"
  .then (doc) => Promise.resolve doc.last_seq
  .catch => Promise.resolve null
  if last_seq
    Tamarind.watchRemoteChangesAndSaveLocally(remoteDatabase, localDatabaseMirror, last_seq)
    return Promise.resolve localDatabaseMirror
  else

    # Get configuration stuff first
    # calculated-fields
    # search query params
    # indexes
    remoteDatabase.allDocs
      startkey: "tamarind-"
      endkey: "tamarind-\uf000"
      include_docs: true
    .then (result) =>
      localDatabaseMirror.bulkDocs (_(result.rows).pluck "doc"),
        new_edits: false


    # Get all the docs in reverse order and put them in the mirror
    # Use the last_seq to start handling changes after the initial grab of data
    startkey = "result-\uf000"
    skip = 0
    last_seq = (await remoteDatabase.changes(limit:0, descending:true)).last_seq

    await new Promise (resolve) =>
      loop
        result = await remoteDatabase.allDocs
          descending: true
          startkey: startkey
          endkey: "result"
          limit: 1000
          skip: skip
          include_docs: true

        if result.rows.length is 0
          Tamarind.watchRemoteChangesAndSaveLocally(remoteDatabase, localDatabaseMirror, last_seq)
          break

        localDatabaseMirror.bulkDocs (_(result.rows).pluck "doc"),
          new_edits: false
        .then (bulkResults) =>
          problemPuts = bulkResults.filter (result) => not result.ok
          if problemPuts.length isnt 0
            alert "Problem saving local data: #{JSON.stringify problemPuts}"

        startkey = result.rows[result.rows.length - 1].id
        skip = 1
        # Resolve after the first iteration so we can start working with data while the rest continues to download
        resolve()

    Promise.resolve(localDatabaseMirror)
    


  ###
  if await Tamarind.canCreateDesignDoc(remoteDatabase)
    await remoteDatabase.createIndex
      index:
        fields: ["collection"]
    .catch (error) =>
      alert JSON.stringify(error)
  ###

  ###
    designDoc = 
      _id: '_design/reportingMirror'
      language: "javascript"
      views:
        reportingMirror: 
          map: ((doc) ->
            if doc._id[0..6] is "result-" or doc.collection is "result" or doc._id[0..16] is "calculated-field_"
              emit doc._id
          ).toString()
    await remoteDatabase.put designDoc
    .catch (error) => 
      if error.reason is "You are not a db or server admin."
        password = prompt "Enter an admin password to setup a local mirror"
        serverUrlWithAdminCredentials = serverUrlWithCredentials.replace(/\/.*@/, "//admin:#{password}@")
        return Tamarind.getLocalMirrorForCouchDB(serverUrlWithAdminCredentials, databaseName)
      console.log designDoc
      alert JSON.stringify error
      alert "Using remote DB as local"
      localDatabaseMirror = remoteDatabase
      localDatabaseMirror.remoteDatabase = remoteDatabase
      Promise.resolve()

  unless localDatabaseMirror is remoteDatabase
    currentNumberOfDocuments = (await localDatabaseMirror.info()).doc_count
    targetNumberOfDocuments = "Unknown"
    # Do this asynchronously
    remoteDatabase.find
      selector:
        collection: "result"
      limit: 500000
      fields: ["notARealField"]
    .then (result) => 
      targetNumberOfDocuments = result.docs.length
      console.log "targetNumberOfDocuments: #{targetNumberOfDocuments}"

      localDatabaseMirror.replication = localDatabaseMirror.replicate.from remoteDatabase,
        live: true
        retry: true
        batch_size: 10000
        selector:
          collection: "result"
      .on "change", (change) => 
        percentComplete = (currentNumberOfDocuments + change.docs_written)/parseFloat(targetNumberOfDocuments)
        localDatabaseMirror.replication.percentComplete = percentComplete
        console.log "Replication update to #{databaseName}: #{JSON.stringify change.docs_written} docs written. Target #{targetNumberOfDocuments}. Started with #{currentNumberOfDocuments}. Currently have #{currentNumberOfDocuments + change.docs_written}. #{Math.floor(100*percentComplete)}% complete"
      .on "paused", (info) => 
        console.log "Replication paused:"
      .on "active", =>  console.log "Replication active"
      .on "denied", (error) =>  console.log error
      .on "error", (error) =>  console.log error

      console.log localDatabaseMirror
      console.log localDatabaseMirror.replication
  ###
  #

Tamarind.updateAvailableFields = (remoteDatabase, localDatabaseMirror) =>
  console.log "Updating available fields"
  remoteDatabase.query "fields",
    reduce: true
    group: true
  .catch (error) =>
    console.error error
    alert "Need to add available fields index"
    if error.reason is "missing"
      password = prompt "Enter an admin password to setup a local mirror"
      adminRemoteDatabase = new PouchDB(remoteDatabase.name.replace(/\/.*@/, "//admin:#{password}@"))
      await adminRemoteDatabase.put
        _id: "_design/fields",
        language: "coffeescript",
        views:
          fields:
            map: """(doc) ->
  if doc.collection is 'result' and doc.question
    for key in Object.keys(doc)
      if key? and key isnt ''
        emit [doc.question, key]
            """
            reduce: "_count"

      _.delay =>
        remoteDatabase.query "fields",
          reduce: true
      , 500

      alert "Fields index added - may take a few minutes before it is ready to be used."

      _.delay =>
        return Tamarind.updateAvailableFields(remoteDatabase, localDatabaseMirror)
      , 1000
  .then (result) =>
    fieldsAndFrequencyByQuestion = {}
    for row in result.rows
      fieldsAndFrequencyByQuestion[row.key[0]] or= []
      fieldsAndFrequencyByQuestion[row.key[0]].push
        field: row.key[1]
        frequency: row.value
    await localDatabaseMirror.upsert "_local/availableFields", =>
      fieldsAndFrequencyByQuestion: fieldsAndFrequencyByQuestion
    console.log "Fields Updated"

Tamarind.watchRemoteChangesAndSaveLocally  = (remoteDatabase, localDatabaseMirror, last_seq) =>
  localDatabaseMirror.upsert "_local/remote_last_seq", (doc) =>
    doc.last_seq = last_seq
    doc

  remoteDatabase.changes
    since: last_seq
    live: true
    include_docs: true
  .on "error", (error) => console.error error
  .on "change", (change) =>
    if change.doc._id.startsWith "result"
      await localDatabaseMirror.put change.doc,
        force: true
      localDatabaseMirror.upsert "_local/remote_last_seq", (doc) =>
        doc.last_seq = last_seq
        doc

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
