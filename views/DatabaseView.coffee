Backbone = require 'backbone'
JsonDiffPatch = require 'jsondiffpatch'

class DatabaseView extends Backbone.View
  render: =>
    $("#title").html "
      <a href='#server/#{@serverName}'>#{@databaseName}</a> 
    "
    @$el.html "
      <style>
        li {
          padding-top: 1.5em;
        }
        li a{
          font-size: 1.5em;
        }
      </style>
      <div style='display:inline-block; width:45%; vertical-align:top' id='questions'/>
        <h3>Question Sets Loading...</h3>
      </div>
      <div style='display:inline-block; width:45%; vertical-align:top' id='queries'/>
        <h3>Queries Loading...</h3>
      </div>
    "

    Tamarind.localDatabaseMirror.allDocs
      startkey: "tamarind-queries"
      endkey: "tamarind-queries_\uf000"
    .then (result) =>
      @$("#queries").html "<h3>Queries</h3>" + (for row in result.rows
        queryName = row.key.replace(/tamarind-queries-/,"")
        "
        <li>
          <a href='#results/#{@serverName}/#{@databaseName}/query/#{queryName}'>#{queryName}</a> 
        </li>
        "
      ).join("")

    Tamarind.database.query "questions"
    .catch (error) =>
      if error.name is "not_found"
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
      @questionSets = []
      @$("#questions").html "<h3>Question Sets</h3>" +  (for row in result.rows
        @questionSets.push row.id
        "
        <li>
          <a href='#results/#{@serverName}/#{@databaseName}/#{row.id}'>#{row.id}</a> 
        </li>
        "
      ).join("")


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
