global.Backbone = require 'backbone'
Backbone.$  = $
_ = require 'underscore'

humanize = require 'underscore.string/humanize'

QuestionSetView = require './views/QuestionSetView'
ResultsView = require './views/ResultsView'
SelectServerView = require './views/SelectServerView'
ServerView = require './views/ServerView'
DatabaseView = require './views/DatabaseView'
GatewayView = require './views/GatewayView'

class Router extends Backbone.Router

  applications:
    "Ceshhar": "https://ceshhar.cococloud.co/ceshhar"
    "Coconut Surveillance Development": "https://zanzibar.cococloud.co/zanzibar-development"
    "Shokishoki": "https://zanzibar.cococloud.co/shokishoki"
    "Local Shokishoki": "http://localhost:5984/shokishoki"
    "Local Kigelia": "http://localhost:5984/kigelia"
    "Entomological Surveillance": "https://zanzibar.cococloud.co/entomological-surveillance"

  routes:
    "select/server": "selectServer"
    "server/:serverName": "showServer"
    "database/:serverName/:databaseName": "showDatabase"
    "gateway/:serverName/:gatewayName": "showGateway"
    "results/:serverName/:databaseName/query/:queryDocName": "resultsFromQuery"
    "results/:serverName/:databaseName/:questionSetDocId": "results"
    #"questionSet/:serverName/:databaseOrGatewayName/:questionSetDocId": "questionSet"
    #"questionSet/:serverName/:databaseOrGatewayName/:questionSetDocId/:question": "questionSet"
    "reset": "reset"
    "logout": "logout"
    "": "default"

  reset: =>
    if Tamarind.localDatabaseMirror?
      databaseName = Tamarind.localDatabaseMirror.name.replace(/.*\//,"")
      if confirm "Are you sure you want to reset the data in your browser for database: #{databaseName}? It can take a long time to download data and index it?"
        await Tamarind.localDatabaseMirror.destroy()
        $("#content").html  "<h1>#{databaseName} reset<h1>... Returning to reset database: #{databaseName}."
        _.delay =>
          router.navigate "database/#{Tamarind.serverName}/#{databaseName}", trigger:true
        , 2000

  selectServer: =>
    @selectServerView ?= new SelectServerView()
    @selectServerView.setElement $("#content")
    @selectServerView.render()

  showServer: (serverName) =>
    Tamarind.serverName = serverName
    @serverView ?= new ServerView()
    @serverView.setElement $("#content")
    @serverView.render()

  showDatabase: (serverName, databaseName) =>
    $("#content").html "<h1>Loading #{databaseName}</h1>"
    await Tamarind.setupDatabase(serverName, databaseName)
    @databaseView ?= new DatabaseView()
    @databaseView.serverName = serverName
    @databaseView.databaseName = databaseName
    @databaseView.setElement $("#content")
    @databaseView.render()

  showGateway: (serverName, gatewayName) =>
    await Tamarind.setupDatabase(serverName, gatewayName)
    @gatewayView ?= new GatewayView()
    @gatewayView.serverName = serverName
    @gatewayView.gatewayName = gatewayName
    @gatewayView.setElement $("#content")
    @gatewayView.render()

  questionSet: (serverName, databaseOrGatewayName, questionSetDocId, question) =>
    await Tamarind.setupDatabase(serverName, databaseOrGatewayName)
    @questionSetView ?= new QuestionSetView()
    @questionSetView.serverName = serverName
    @questionSetView.databaseOrGatewayName = databaseOrGatewayName
    @questionSetView.setElement $("#content")
    @questionSetView.questionSet = await QuestionSet.fetch(questionSetDocId)
    @questionSetView.activeQuestionLabel = question
    @questionSetView.render()

  resultsFromQuery: (serverName, databaseName, queryDocName) =>
    await Tamarind.setupDatabase(serverName, databaseName)
    @resultsView ?= new ResultsView()
    @resultsView.serverName = serverName
    @resultsView.databaseName = databaseName
    @resultsView.setElement $("#content")
    @resultsView.queryDocName = queryDocName
    @resultsView.render()


  results: (serverName, databaseName, questionSetDocId, question) =>
    await Tamarind.setupDatabase(serverName, databaseName)
    @resultsView ?= new ResultsView()
    @resultsView.serverName = serverName
    @resultsView.databaseName = databaseName
    @resultsView.setElement $("#content")
    @resultsView.questionSet = await QuestionSet.fetch(questionSetDocId)
    @resultsView.activeQuestionLabel = question
    @resultsView.render()


  logout: =>
    Tamarind.database = null
    Cookie.remove("username")
    Cookie.remove("password")
    @navigate("#", {trigger:true})

  default: () =>
    @selectServer()

module.exports = Router
