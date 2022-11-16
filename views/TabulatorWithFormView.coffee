$ = require 'jquery'
require 'jquery-ui-browserify'
Backbone = require 'backbone'
Backbone.$  = $
_ = require 'underscore'
dasherize = require("underscore.string/dasherize")
global.titleize = require("underscore.string/titleize")
humanize = require("underscore.string/humanize")
slugify = require("underscore.string/slugify")
underscored = require("underscore.string/underscored")
Tabulator = require 'tabulator-tables'
global.CSON = require 'cson-parser'
require 'daterangepicker'
moment = require 'moment'
pluralize = require 'pluralize'
Choices = require 'choices.js'

AsyncFunction = Object.getPrototypeOf(`async function(){}`).constructor; # Strange hack to build AsyncFunctions https://davidwalsh.name/async-function-class

hljs = require 'highlight.js/lib/core';
hljs.registerLanguage('coffeescript', require ('highlight.js/lib/languages/coffeescript'))
hljs.registerLanguage('javascript', require ('highlight.js/lib/languages/coffeescript'))

class TabulatorWithFormView extends Backbone.View

  constructor: (options) ->
    super()
    @type = options.type
    @description = options.description
    @properties = options.properties

  events: 
    "click #createButton": "create"
    "click #removeButton": "remove"
    "keyup input[type=search]": "filterSample"
    "change .updateSampleResultOnChange": "updateResultFromSample"
    "click .toggleNext": "toggleNext"
    "change .actionOnChange": "actionOnChange"
    "change #queries--index": "toggleCombinedQueryOptions"

  toggleCombinedQueryOptions: =>
    for field in ["Combine Queries", "Join Field", "Prefix"]
      if @$("#queries--index").val() is "Combine Queries"
        @$("#section-queries-#{dasherize(field)}").show()
        @$("#section-queries--query-field-options").hide()
      else
        @$("#section-queries-#{dasherize(field)}").hide()
        @$("#section-queries--query-field-options").show()

  # If a field has an actionOnChange property then we look it up and run it when this changes
  actionOnChange: (event) =>
    changeActions[event.target.id]()

  toggleNext: (event) =>
    toggler = $(event.target).closest(".toggleNext")
    # Change the arrow
    toggler.children().each (index, span) => 
      $(span).toggle()
    console.log toggler.parent().next("div")
    toggler.parent().next("div").toggle() # Get the header then the sibling div

  toggle: =>
    "
    <span style='cursor:pointer' class='toggleNext'>
      <span style='color:#00bcd4'>►</span>
      <span style='display:none; color:#00bcd4;'>▼</span>
    </span>
    "


  filterSample: =>
    filterText = @$("input[type=search]").val()
    for div in @$("#sampleData div").toArray()
      unless div.textContent.match(filterText)
        div.style.display = "none"
      else
        div.style.display = ""
      

  create: =>
    @$("#createButton").css("background-color","7F171F").html("Saving")
    docId = "tamarind-#{@type}-#{@$("##{@type}--name").val()}"
    await Tamarind.localDatabaseMirror.upsert docId, (doc) =>
      for property in @properties
        doc[property.name] = @$("##{@type}-#{dasherize(property.name)}").val()
      doc

    await Tamarind.localDatabaseMirror.replicate.to Tamarind.database,
      doc_ids: [docId]
    @render()
    if @type is "indexes"
      # The queries UI needs to update the list of available indexes
      @resultsView.tabulatorWithFormViews["queries"] = await TabulatorWithFormView.create(type)
      @resultsView.tabulatorWithFormViews["queries"].setElement @$("##{type}")
      @resultsView.tabulatorWithFormViews["queries"].render()

  remove: =>
    if confirm "Are you sure you want to remove #{@$("##{@type}--name").val()}?"
      docId = "tamarind-#{@type}-#{@$("##{@type}--name").val()}"
      await Tamarind.localDatabaseMirror.upsert docId, (doc) =>
        doc._deleted = true
        doc
      Tamarind.localDatabaseMirror.replicate.to Tamarind.database,
        doc_ids: [docId]
      @render()

  render: =>
    @$el.html "
      <h3>#{titleize @type} <span></span>#{@toggle()}</h3>
      <div style='display:none' id='#{@type}'>
        <span class='description'>#{@description}</span>
        <div id='#{@type}-tabulator'></div>
        <div id='form'>
          <div style='width:49%; display:inline-block; vertical-align:top'>
            <h3>Edit #{pluralize.singular(@type)}</h3>
            <div>
            #{
            (for property in @properties
              id = "#{@type}-#{dasherize(property.name)}"
              "
              <div id='section-#{id}' style='#{if property.hide is true then 'display:none' else ''}'>
                <span>#{property.name}: #{ if property.hide is "toggle" then @toggle() else ""}</span>
                  <div style='#{if property.hide is "toggle" then "display:none" else ""}'>
                  <div class='description'>#{property.description}</div>
                  #{ 
                  if property.example
                    "
                    <div class='example'>Example:<br/>
                    #{
                      if property.type is "coffeescript"
                        "<pre><code>#{property.example}</code></pre>"
                      else
                        "<div style='background-color:#282c34; color: #abb2bf; padding:0.5em; font-family:monospace; margin-bottom:0.5em'>#{property.example}</div>"
                    }
                    </div>
                    "
                  else ""
                  }
                #{
                  classes = "updateSampleResultOnChange"
                  if property.actionOnChange
                    classes += " actionOnChange"
                    global.changeActions or= {}
                    changeActions[id] = property.actionOnChange
                  classes += " sortableChoices" if property.type is "choices"

                  switch property.type
                    when "coffeescript"
                      "<textarea style='width:100%' class='#{classes}' id='#{id}' rows='5' cols='40'>#{property.default or ""}</textarea>"
                    when "select", "choices"
                      "
                      <select class='#{classes}' id='#{id}' #{if property.type is "choices" then "multiple" else ""}>
                        #{property.options}
                      </select>
                      "
                    else
                      "<input class='#{classes}' style='width:100%' id='#{id}' value='#{property.default or ""}'></input>"
                }
                </div>
              </div>
              "
            ).join("")
            }
            </div>

            <button id='createButton'>Create/Update</button>
            <button id='removeButton'>Remove</button>
          </div>
          <div id='sample' style='width:49%;display:inline-block'>
          </div>
        </div>
        <hr/>
      </div>
    "

    hljs.configure
      languages: ["coffeescript", "json"]
      useBR: false

    @$('pre code').each (i, snippet) =>
      hljs.highlightElement(snippet)

    @load()

    _.delay =>
      @sortableChoices = new Choices @$(".sortableChoices")[0], 
        #choices: choicesData
        shouldSort: true
        removeItemButton: true
      console.log @sortableChoices
    , 2000 # Not sure why this is needed

  load: =>
    configurationDocs = await Tamarind.localDatabaseMirror.allDocs
      startkey: "tamarind-#{@type}"
      endkey: "tamarind-#{@type}_\uf000"
      include_docs: true
    .then (result) => Promise.resolve _(result.rows).pluck "doc"

    columns = (
      properties = {}

      # Get all possible properties
      for field in configurationDocs
        for property in Object.keys(field)
          properties[property] = true
      columns = for property of properties
       # Skip these
        continue if [
          "_rev"
          "_id"
        ].includes property

        column = 
          field: property
          title: property
          width: 200

        if property is "Name"
          column.width = 300

        column
    )

    if @type is "queries"
      columns.unshift
        formatter: (cell) =>
          "<a href='#results/#{Tamarind.serverName}/#{Tamarind.databaseName}/query/#{cell.getData().Name}'>⇗</a>"

    @tabulator = new Tabulator "##{@type}-tabulator",
      columns: columns
      height: 200
      initialSort:[
        {column:"enabled", dir:"desc"}
      ]
      data: configurationDocs

    @tabulator.on "dataChanged", (changedData) =>
      for change in changedData
        await Tamarind.localDatabaseMirror.upsert change._id, => change
        Tamarind.localDatabaseMirror.replicate.to Tamarind.database,
          doc_ids: [change._id]
      @render()
    @tabulator.on "cellClick", (event, cell) =>
      return if cell.getColumn().getField() is "enabled"
      @editItem cell.getData()

  editItem: (data) =>
    for property in @properties
      if property.type is "choices"
        @sortableChoices?.setChoiceByValue data[property.name]
      else
        @$("##{@type}-#{dasherize(property.name)}")[0].value = data[property.name]
    @updateResultFromSample()
    @toggleCombinedQueryOptions()

  renderSample: (sample) =>
    @currentSample = sample

    @$("#sample").html "
    <h3>Sample Result</h3>
    Below is a result based on the current selection. <button id='loadNewSample'>Load random result</button> (you can also click on any row in the table to load that item here)<br/>
    Filter: <input type='search'></input>
    <div id='sampleData' style='
      background-color: #282c34;
      color: #98c379;
      font-size: small;
      font-family: monospace;
      '
    >
      #{
      (for property, value of @currentSample
        "
        <div data-property-name='#{property}'>
          <span class='property' propertyName='#{property}'>
            <span class='addPropertyToCalculatedValue' style='backgroundColor:black; color: yellow'>⊕</span>
            #{property}
          </span>
          <span class='value' style='
            font-size:small;
            color: #d19a66;
          '>#{value}</span>
        </div>
        "
      ).join("")
      }
    </div>
    <span id='resultFromSample'></span>
    <hr>
    Code Used To Fetch Data:
    <div 
      style='
        white-space:pre;
        font-family:monospace;
        font-size:small;'
      id='codeUsed'>
    </div>
    "

    @updateResultFromSample()
    @$("#codeUsed").html @resultsView.queryDoc.queryCodeString
    @$('#codeUsed').each (i, snippet) =>
      hljs.highlightElement(snippet)

  updateResultFromSample: =>
    return unless @currentSample
    switch @type
      when "index"
        @$("#resultFromSample").html "For the current #{pluralize.singular(@type)}, the above result would return:<br/>
          <span style='font-weight:bold'>
          #{
          if @$("#indexes--map-function").val()
            evalFunction = """
              returnVal = ""
              emit = (a,b) => 
                if _(a).isArray()
                  a = "[\#{a}]"
                  b = "" if b is undefined
                returnVal += "\#{a}:\#{b}"
              mapFunction = (#{@$("#indexes--map-function").val()})
              mapFunction((#{CSON.stringify @currentSample}))
              returnVal
            """
            eval Coffeescript.compile(evalFunction, bare:true)
          else if @$("#indexes--fields").val()
            Object.values(_(@currentSample).pick(@$("#indexes--fields").val().split(/, */))).join(",")
          else "No fields or mapping function"
          }
          </span>
        "
      when "queries"
        @$("#resultFromSample").html ""
      when "calculated-fields"
        calculationField = @$("#calculated-fields--calculation")
        calculation = calculationField.val()
        return unless calculation
        @unsavedCalculation = true
        unless calculation.match(/return/)
          if confirm "No return statement, do you want to add it?"
            calculation = calculation.split(/\n/)
            lastLine = calculation.pop()
            lastLine = "return " + lastLine
            calculation.push lastLine
            calculation = calculation.join("\n")
            calculationField.val calculation
        try
          calculationFunction = new Function('result', Coffeescript.compile(calculation, bare:true))
        catch error
          alert "Error compiling calculation: #{error}. Create/Update button disabled until this is fixed.\n#"
          @$("#createButton")[0].disabled = true
          return

        @$("#createButton")[0].disabled = false

        @$("#resultFromSample").html "
          Calculation with current sample: <span style='font-weight:bold'>
          #{
            await calculationFunction(@currentSample)
          }
          </span>
        "

  toggle: =>
    "
    <span style='cursor:pointer' class='toggleNext'>
      <span style='color:#00bcd4'>►</span>
      <span style='display:none; color:#00bcd4;'>▼</span>
    </span>
    "

  currentQuestionSetName: =>
    @resultsView?.questionSet?.name()

  TabulatorWithFormView.create = (type) =>
    currentQuestionSetName = @resultsView?.questionSet?.name()
    new TabulatorWithFormView(
      switch type
        when "indexes"
          type: "indexes"
          description: "An index is a way to organize data in your databases so that it can quickly retrieve the appropriate data."
          properties: [
            name: "Name"
            description: "Name of the index"
            example: "Results By Question And Date"
          ,
            name: "Fields"
            description: "Fields in the order of the index. For example, first get all of the results for question X, then limit the results to everything created after a certain date. This will create a map function, so if you have defined Fields then you can't have a Map Function."
            example: "question, createdAt"
          ,
            name: "Map Function"
            description: "This is an advanced feature. If there is a Map Function then it will override the 'Fields' section. If you need to combine fields or do extra logic before indexing this is how you can do it."
            type: "coffeescript"
            example: """
              (doc) =>
                # Use the name, if not try and combine First and Last to make it
                name = doc.name or \#{doc.FirstName + " " + doc.LastName}
                emit [name,doc.date]
            """
            hide: "toggle"
          ]

        when "queries"
          type: "queries"
          description: "Queries select the data you want to display. You can save queries so that they can be reused again in the future. The 'default' query for the current question set will be used if no other query is selected. All of the queries available in this database are listed below."
          properties: [
            name: "Name"
            description: "Name of the query"
            example: "#{currentQuestionSetName or Tamarind.databaseName}-default"
          ,
            name: "Index"
            description: "Index used by this query to get data from the database"
            example: "Results By Question and Date"
            type: "select"
            options: await Tamarind.localDatabaseMirror.allDocs
                startkey: "tamarind-indexes"
                endkey: "tamarind-indexes\uf000"
              .then (result) =>
                Promise.resolve(
                  "<option></option>" + (for row in result.rows
                    indexName = row.key.replace(/tamarind-indexes-/,"")
                    "<option>#{indexName}</option>"
                  ).join("") + "<option>Combine Queries</option>"
                )
          ,
            name: "Combine Queries"
            hide: true
            description: "You can combine the results of two or more queries into one table by selecting the queries here and then choosing a field to join them with. ORDER MATTERS. The first query determines the number of rows and subsequent queries get added to these rows."
            type: "choices"
            options: await Tamarind.localDatabaseMirror.allDocs
                startkey: "tamarind-queries"
                endkey: "tamarind-queries\uf000"
              .then (result) =>
                Promise.resolve(
                  (for row in result.rows
                    name = row.key.replace(/tamarind-queries-/,"")
                    "<option>#{name}</option>"
                  ).join("")
                )
            actionOnChange: =>
              queries = $("#queries--combine-queries").val()
              if queries.length > 0
                $("section-queries-index").hide()
                $("section-queries-index").val("")
                $("section-queries-query-options").hide()
                $("section-queries-query-options").val("")
              else
                $("section-queries-index").show()
                $("section-queries-query-options").show()

              #$("#queries--join-field").html("<option></option>" + (for query in queries
              #).join())
          ,
            name: "Join Field"
            hide: true
            description: "This is the field that should appear in the results of both queries and will be used to combine them into one row."
            type: "text"
          ,
            name: "Prefix"
            hide: true
            description: "This adds a prefix to the column name, which can be helpful to keep track of the source of the data. If this is blank it will use the field question as the prefix. To disable enter the word 'false'."
            type: "text"
          ,
            name: "Query Field Options"
            description: "Fields to display to user for filtering the query, like date or region. This happens at the query stage not within the table. The array order must match the Fields above. The format here is CSON, it's like JSON but easier to read (no need for commas, double quotes, etc), and you do need to ident it properly."
            type: "coffeescript"
            example: CSON.stringify [
              {field:'question', equals: "#{currentQuestionSetName or "CHANGE TO NAME OF TARGET QUESTION"}", userSelectable: false}
              {field:'createdAt', type: "Date Range", startValue: "#{moment().startOf("year").format("YYYY-MM-DD")}", endValue: 'now', userSelectable: true}
            ]
            , null, "  "
          ,
            name: "Initial Fields"
            description: "Fields that will be displayed in the table when first loaded. If left blank, it gets the first 4 most frequently filled fields."
            default: ""
            example: "createdAt, name"
          ,
            name: "Limit"
            description: "Total number of results to load. A large number of results (> 10000) can slow things down."
            default: "10000"
          , 
            name: "Query Options"
            description: "Options to add to the query. Options available include: startkey, endkey, limit, ascending, include_docs"
            type: "coffeescript"
            default: ""
            example: CSON.stringify
              startkey: "2020-01-01"
              include_docs: false
            , null, "  "
          ]

        when "calculated-fields"
          type: "calculated-fields"
          description: "Calculated fields are fields that get calculated for each result. This is similar to creating a formula in a spreadsheet. For example, we often ask two questions to get someone's age: their age and whether that age is in years, months or days. However, to compare this data it should all be converted into the same unit, so we create a calculated value called 'Age in Years'. This calculation checks what the type of age it is, then divides the age to return the age in years. This calculated value then appears as a new column in the results table."
          properties: [
            name: "Name"
            description: "The name of the calculated field."
          ,
            name: "Calculation"
            description: "Calculation is the code used to do the calculation. It is coffeescript (like javascript but easier to read and write) code that is run for each result, and receives a variable called 'result' which can be used to do the calculation. It needs to have a return statement to specify what to use as the final calculated result."
            type: "coffeescript"
            example:
              """
      return switch result['age-in-years-months-days'] # Switch based on the age-in-years-months-days result
        when 'Years' then result['age'] # divide as is appropriate
        when 'Months' then result['age']/12.0
        when 'Days' then result['age']/365.0
              """
          ,
            name: "Initialize"
            description: "Initialize is used for advanced calculations. It is code that runs before calculating the result. For instance you can query for user data and then setup an object that maps between usernames and their location. The calculation then uses this object instead of doing a query for every single result."
            type: "coffeescript"
            example:
              """
    window.facilityByUser = {} # Create a global (window.) collection object for the mapping
    Tamarind.database.allDocs  # Get all of the user documents from the database
      startkey: 'user'
      endkey: 'user_~'
      include_docs: true
    .then (result) =>
      for row in result.rows # Loop over each user
        username = row.doc._id.replace(/user\./,'') # get just the username
        facilityByUser[username] = row.doc.facility # Fill in the collection
              """
          ]
  )

module.exports = TabulatorWithFormView
