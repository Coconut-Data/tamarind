Backbone = require 'backbone'
JsonDiffPatch = require 'jsondiffpatch'

hljs = require 'highlight.js/lib/highlight';
coffeescriptHighlight = require 'highlight.js/lib/languages/coffeescript';
hljs.registerLanguage('coffeescript', coffeescriptHighlight);

class DatabaseView extends Backbone.View
  render: =>
    @$el.html "<h1>Loading question sets...</h1>"
    Tamarind.database.query "questions"
    .catch (error) =>
      if error.name is "not_found"
        @$el.html "<h1>Creating questions design doc, please wait...</h1>>"
        Tamarind.database.put
          _id: '_design/questions',
          language: "coffeescript",
          views:
            questions:
              "map": "(doc) ->\n  if doc.collection and doc.collection is \"question\"\n    emit doc._id\n"
        .catch (error) =>
          return alert error
        .then =>
          @render()
    .then (result) =>
      @$el.html "
        <style>
          li {
            padding-top: 2em;
          }
          li a{
            font-size: 2em;
          }
        </style>
        <h1>#{@databaseName}</h1>
        <h2>Select a question set</h2>
        <div id='questions'/>
        </div>

      "
      @questionSets = []
      @$("#questions").html (for row in result.rows
        @questionSets.push row.id
        "
        <li>
          <a href='#questionSet/#{@serverName}/#{@databaseName}/#{row.id}'>#{row.id}</a> 
        </li>
        "
      ).join("")

      hljs.configure
        languages: ["coffeescript", "json"]
        useBR: false

      @$('pre code').each (i, snippet) =>
        hljs.highlightBlock(snippet);


  events: =>

  fetchDatabaseList: =>
    @username = Cookie.get("username")
    @password = Cookie.get("password")
    new Promise (resolve,reject) =>
      #fetch "#{Tamarind.knownDatabaseServers[Tamarind.serverName]}/_all_dbs",
      fetch "#{Tamarind.knownDatabaseServers[@serverName]}/_all_dbs",
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


module.exports = DatabaseView
