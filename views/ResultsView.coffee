$ = require 'jquery'
require 'jquery-ui-browserify'
Backbone = require 'backbone'
Backbone.$  = $
_ = require 'underscore'
dasherize = require("underscore.string/dasherize")
titleize = require("underscore.string/titleize")
humanize = require("underscore.string/humanize")
slugify = require("underscore.string/slugify")
underscored = require("underscore.string/underscored")
Tabulator = require 'tabulator-tables'
global.CSON = require 'cson-parser'
require 'daterangepicker'
moment = require 'moment'

AsyncFunction = Object.getPrototypeOf(`async function(){}`).constructor; # Strange hack to build AsyncFunctions https://davidwalsh.name/async-function-class

hljs = require 'highlight.js/lib/core';
hljs.registerLanguage('coffeescript', require ('highlight.js/lib/languages/coffeescript'))

{QueryCommand,DeleteItemCommand} = require "@aws-sdk/client-dynamodb"
{marshall,unmarshall} = require("@aws-sdk/util-dynamodb")

global.QuestionSet = require '../models/QuestionSet'
global.QueryDoc = require '../models/QueryDoc'

TabulatorView = require './TabulatorView'

class ResultsView extends Backbone.View
  events: =>
    "click #download": "csv"
    "click #pivotButton": "loadPivotTable"
    "click #createCalculatedFieldButton": "createCalculatedField"
    "click #removeCalculatedFieldButton": "removeCalculatedField"
    "click .addPropertyToCalculatedValue": "addPropertyToCalculatedValue"
    "change #calculation": "updateCalculationFromSample"
    "change #query--fields": "updateQueryResultFromSample"
    "change #query--map-function": "updateQueryResultFromSample"
    "click #loadNewSample": "getNewSample"
    "click .toggleNext": "toggleNext"
    "click #refresh": "queryAndLoadTable"
    "click #createQueryButton": "createQuery"
    "click #removeQueryButton": "removeQuery"
    "change .query-filter-date-range": "updateDateRange"
    "click #createNewQueryFromCurrentConfiguration": "createNewQueryFromCurrentConfiguration"

  createNewQueryFromCurrentConfiguration: =>
    # Do a deep clone https://www.samanthaming.com/tidbits/70-3-ways-to-clone-objects/
    newQueryDoc = JSON.parse(JSON.stringify(@queryDoc))


    nameBase = if newQueryDoc.Name.match("-")
      nameBase = newQueryDoc.Name.replace(/-.*/,"-")
    else
      nameBase = newQueryDoc.Name + "-"
    queryName = prompt "Enter name for configuration:", nameBase
    return if queryName is null
    newQueryDoc.Name = queryName
    newQueryDoc._id = "tamarind-query-#{queryName}"

    # Fix CSON sections for saving
    newQueryDoc["Query Field Options"] = CSON.stringify(newQueryDoc["Query Field Options"], null, "  ") if newQueryDoc["Query Field Options"]

    newQueryDoc["Initial Fields"] = @tabulatorView.selector.getValue(true).join(", ")


    # Open/Close Sections
    # Graph/PivotTable/map Config

    if await (Tamarind.localDatabaseMirror.get(newQueryDoc._id).catch => Promise.resolve null)
      return unless confirm "#{queryName} already exists, do you want to replace it?"

    await Tamarind.localDatabaseMirror.upsert newQueryDoc._id, =>
      newQueryDoc

    Tamarind.localDatabaseMirror.replicate.to Tamarind.database,
      doc_ids: [newQueryDoc]
    @render()

  updateDateRange: (event) =>
    dateRangeElement = $(event.target)
    if dateRangeElement.data().daterangepicker
      queryFieldIndex = parseInt(dateRangeElement.attr("data-query-field-index"))
      @queryDoc["Query Field Options"][queryFieldIndex].startValue = dateRangeElement.data().daterangepicker.startDate.format("YYYY-MM-DD")
      @queryDoc["Query Field Options"][queryFieldIndex].endValue = dateRangeElement.data().daterangepicker.endDate.format("YYYY-MM-DD")
      console.log CSON.stringify @queryDoc, null, "  "
      console.log "Date Range changed, queryAndLoadTable"
      @queryAndLoadTable()

  createQuery: =>
    docId = "tamarind-query-#{@$("#query--name").val()}"
    console.log "ZZZ"
    await Tamarind.localDatabaseMirror.upsert docId, (doc) =>
      for property in @queryProperties
        doc[property.name] = @$("#query-#{dasherize(property.name)}").val()
      console.log doc
      doc

    console.log docId

    console.log await Tamarind.localDatabaseMirror.replicate.to Tamarind.database,
      doc_ids: [docId]
    @render()

  removeQuery: =>
    if confirm "Are you sure you want to remove #{@$("#query--name").val()}?"
      docId = "tamarind-query-#{@$("#query--name").val()}"
      await Tamarind.localDatabaseMirror.upsert docId, (doc) =>
        doc._deleted = true
        doc
      Tamarind.localDatabaseMirror.replicate.to Tamarind.database,
        doc_ids: [docId]
      @render()

  toggleNext: (event) =>
    toggler = $(event.target).closest(".toggleNext")
    toggler.children().each (index, span) => 
      $(span).toggle()

    toggler.parent().next("div").toggle() # Get the header then the sibling div

  updateCalculationFromSample: =>
    calculation = @$("#calculation").val()
    return if calculation is ""
    @unsavedCalculation = true
    unless calculation.match(/return/)
      if confirm "No return statement, do you want to add it?"
        calculation = @$("#calculation").val().split(/\n/)
        lastLine = calculation.pop()
        lastLine = "return " + lastLine
        calculation.push lastLine

        @$("#calculation").val calculation.join("\n")
        calculation = @$("#calculation").val()

    try
      calculationFunction = new Function('result', Coffeescript.compile(calculation, bare:true))
    catch error
      alert "Error compiling calculation: #{error}. Create/Update button disabled until this is fixed.\n#"
      @$("#createCalculatedFieldButton")[0].disabled = true
      return

    @$("#createCalculatedFieldButton")[0].disabled = false

    @$("#calculationFromSample").html "
      Calculation with current sample: <span style='font-weight:bold'>
      #{
        await calculationFunction(@currentSample)
      }
      </span>
    "


  updateQueryResultFromSample: =>
    return unless @currentSample
    @$("#queryResultFromSample").html "For the currently loaded query, the above result would return:<br/>
      <span style='font-weight:bold'>
      #{
      if @$("#query--map-function").val()
        evalFunction = """
          returnVal = ""
          emit = (a,b) => 
            if _(a).isArray()
              a = "[\#{a}]"
              b = "" if b is undefined
            returnVal += "\#{a}:\#{b}"
          mapFunction = (#{@$("#query--map-function").val()})
          mapFunction((#{CSON.stringify @currentSample}))
          returnVal
        """
        console.log evalFunction
        eval Coffeescript.compile(evalFunction, bare:true)
      else if @$("#query--fields").val()
        Object.values(_(@currentSample).pick(@$("#query--fields").val().split(/, */))).join(",")
      else "No fields or mapping function"
      }
      </span>
    "

  addPropertyToCalculatedValue: (event) =>
    propertyName = $(event.target).parent().attr("propertyName")
    @$("textarea#calculation").val(
      @$("textarea#calculation").val() + "\nresult[\"#{propertyName}\"]"
    )
    @updateCalculationFromSample()

  createCalculatedField: =>
    await Tamarind.localDatabaseMirror.upsert "tamarind-calculated-field_#{@$("#title").val()}", (doc) =>
      for property in ["title", "initialize", "calculation"]
        doc[property] = @$("##{property}").val()
      doc.enabled = true
      doc
    Tamarind.localDatabaseMirror.replicate.to Tamarind.database,
      doc_ids: ["tamarind-calculated-field_#{@$("#title").val()}"]
    for property in ["title", "initialize", "calculation"]
      @$("##{property}").val("")
    @unsavedCalculation = false
    @render()

  removeCalculatedField: =>
    if confirm "Are you sure you want to remove #{@$("#title").val()}?"
      await Tamarind.localDatabaseMirror.upsert "tamarind-calculated-field_#{@$("#title").val()}", (doc) =>
        doc._deleted = true
        doc
      Tamarind.localDatabaseMirror.replicate.to Tamarind.database,
        doc_ids: ["tamarind-calculated-field_#{@$("#title").val()}"]
      for property in ["title", "initialize", "calculation"]
        @$("##{property}").val("")
      @render()

  getQueryDoc: =>
    queryDoc = new QueryDoc()
    queryDoc.Name = @queryDocName or "#{@questionSet?.name()}-default" or throw "No query configuration"
    await queryDoc.fetch()
    .catch (error) =>
      queryDoc["Fields"] = "question, createdAt"
      queryDoc["Query Field Options"] = [
        {
          field: 'question'
          equals: @questionSet.name()
          userSelectable: false
        }
        {
          field: 'createdAt'
          type: 'Date Range'
          startValue: moment().startOf("year").format("YYYY-MM-DD")
          endValue: 'now'
          userSelectable: true
        }
      ]
      Promise.resolve queryDoc

    queryDoc

  # TODO change this to take a queryDoc as an argument
  # TODO allows multiple query docs
  # TODO some kind of merging when multiple query docs
  getResults: (options = {}) =>

    unless @queryDoc
      # Setup the default queryDoc
      @queryDoc = new QueryDoc()
      @queryDoc.Name = "#{@questionSet}-default"

    @setCurrentlySelectedFields()
    @$("#messages").append "<h2>Using query: #{@queryDoc.Name}</h2>"
    @queryDoc.getResults(options)
    # Consider pruning the object to just the displayed columns - use 

  setCurrentlySelectedFields: =>
    @currentlySelectedFields = if @currentlySelectedFields?
      @currentlySelectedFields
    else if @queryDoc?["Initial Fields"]? and @queryDoc["Initial Fields"] isnt ""
      @queryDoc["Initial Fields"].split(/, */)
    else
      @tabulatorView.availableColumns?[0..3].map (column) => column.field

  getResultsWithCalculatedFields: =>
    @setCurrentlySelectedFields()
    enabledCalculatedFields = @tabulators["calculated-field"].getData().filter (calculatedField) => calculatedField.enabled

    if enabledCalculatedFields?.length > 0
      if @currentlySelectedFields?.length > 0
        enabledCalculatedFieldTitles = _(enabledCalculatedFields).pluck("title")
        currentlySelectedCalculatedFieldTitles = _.intersection(@currentlySelectedFields, enabledCalculatedFieldTitles)

    currentlySelectedCalculatedFields = enabledCalculatedFields.filter (field) =>
      currentlySelectedCalculatedFieldTitles?.includes field.title

    if currentlySelectedCalculatedFields.length > 0
      extraFieldsNeededForCalculatedFields = []
      for calculatedField in currentlySelectedCalculatedFields
        for match in (calculatedField.calculation + calculatedField.initialize).match(/(result\[.+?\])|result.[a-zA-Z-_]+/g)
          fieldName = match.replace(/result\./,"")
          .replace(/result\[['"]/,"")
          .replace(/['"]\]/,"")
          extraFieldsNeededForCalculatedFields.push fieldName

        if calculatedField.initialize
          # https://stackoverflow.com/questions/1271516/executing-anonymous-functions-created-using-javascript-eval
          try
            initializeFunction = new AsyncFunction(Coffeescript.compile(calculatedField.initialize, bare:true))
          catch error then alert "Error compiling #{calculatedField.title}: #{error}\n#{CSON.stringify calculatedField, null, "  "}"
          await initializeFunction()

        # Might be faster to use new Function if there is no need of async here
        calculatedField.calculationFunction = new AsyncFunction('result', 
          try
            Coffeescript.compile(calculatedField.calculation, bare:true)
          catch error then alert "Error compiling #{calculatedField.title}: #{error}\n#{CSON.stringify calculatedField, null, "  "}"
        )

      extraFieldsNeededForCalculatedFields = _(extraFieldsNeededForCalculatedFields).unique()

      results = await @getResults(extraFieldsNeededForCalculatedFields: extraFieldsNeededForCalculatedFields)
      @$("#messages").append "<h2>Adding Calculated Fields</h2>"
      for result in results
        for calculatedField in currentlySelectedCalculatedFields
          result[calculatedField.title] = await calculatedField.calculationFunction(result)
        result
    else

      @getResults()

  toggle: =>
    "
    <span style='cursor:pointer' class='toggleNext'>
      <span style='color:#00bcd4'>►</span>
      <span style='display:none; color:#00bcd4;'>▼</span>
    </span>
    "

  render: =>
    @$el.html "
      <style>#{@css()}</style>
      <div style='float:right; width:50%; background-color:#7f171f29;' id='messages'>
        <div id='dataChangesMessages'></div>
        #{
          if @questionSet
            changes = 0
            Tamarind.localDatabaseMirror.changes
              live: true
              include_docs: false
              since: "now"
            .on "change", (change) =>
              if change.doc?.question is @questionSet.name
                changes += 1
                @$("#dataChangesMessages").html "New data available (#{changes}) <button id='refresh'>Refresh</button>"
            ""
        }
      </div>
      <h2>
        #{
        if @questionSet
          "
          Results for <a href='#questionSet/#{@serverName}/#{@databaseName}/#{@questionSet.name()}'>#{@questionSet.name()}</a> 
          "
        else if @queryDocName
          "
          Results for <a href='#questionSet/#{@serverName}/#{@databaseName}'>#{@queryDocName}</a> 
          "
        }
      </h2>
      <button id='createNewQueryFromCurrentConfiguration'>Save current configuration as new Query</button>
      #{@renderQueriesDiv()}
      #{@renderCalculatedFieldsDiv()}
      <div id='queryFilters'></div>
      <div id='tabulatorView'></div>
      </div>
    "


    hljs.configure
      languages: ["coffeescript", "json"]
      useBR: false

    @$('pre code').each (i, snippet) =>
      hljs.highlightElement(snippet);

    await @loadQueriesAndCalculatedFieldData()

    @tabulatorView = new TabulatorView()
    @tabulatorView.setElement("#tabulatorView")
    @tabulatorView.questionSet = @questionSet
    @tabulatorView.availableCalculatedFields = _(@tabulators["calculated-field"].getData()).pluck("title")
    @queryDoc = await @getQueryDoc()
    console.log @queryDoc
    if @queryDoc?.questionSet # This is used for determining availableFields
      @questionSet = @queryDoc.questionSet
      @tabulatorView.questionSet = @questionSet
    @addQueryFilters()
    @tabulatorView.initialFields = @queryDoc?["Initial Fields"]?.split(/, */)

    if @questionSet?
      @tabulatorView.fieldsFromData = await Tamarind.localDatabaseMirror.get("_local/availableFields")
      .catch (error) => Promise.resolve(null)
      .then (doc) => 
        Promise.resolve(
          _(doc.fieldsAndFrequencyByQuestion[@questionSet.name()])
          .chain()
          .sortBy("frequency")
          .pluck "field"
          .reverse()
          .value()
        )
    @tabulatorView.rowClick = (row) =>
      @getNewSample(row.getData().id or row.getData()._id)

    await @queryAndLoadTable()

    # Listen for columns/fields to be changed
    @$("#availableTitles")[0].addEventListener 'change', (event) =>
      @currentlySelectedFields = @tabulatorView.availableColumns.filter (column) =>
        @tabulatorView.selector.getValue(true).includes column.title
      .map (column) => column.field

  queryAndLoadTable: =>

    @tabulatorView.data = await @getResultsWithCalculatedFields()
    @$("#messages").html ""
    if @tabulatorView.tabulator
      @tabulatorView.renderTabulator()
    else
      await @tabulatorView.render()
    @getNewSample()

  renderQueriesDiv: => 
    @queryProperties = [
        name: "Name"
        description: "Name of the query"
        example: "#{@questionSet?.name() or @databaseName}-default"
      ,
        name: "Fields"
        description: "Fields in the order of the query. For example, first get all of the results for question X, then limit the results to everything created after a certain date."
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
      ,
        name: "Query Field Options"
        description: "Fields to display to user for filtering the query, like date or region. This happens at the query stage not within the table. The array order must match the Fields above. The format here is CSON, it's like JSON but easier to read (no need for commas, double quotes, etc), and you do need to ident it properly."
        type: "coffeescript"
        example: CSON.stringify [
          {field:'question', equals: "#{@questionSet?.name() or "name"}", userSelectable: false}
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

    "
    <h3>Queries <span></span>#{@toggle()}</h3>
    <div style='display:none' id='queries'>
      <span class='description'>
        Queries select the data you want to display. You can save queries so that they can be reused again in the future. The 'default' query for the current question set will be used if no other query is selected. All of the queries available in this database are listed below.
      </span>
      <div id='query-tabulator'></div>
      <div id='createQuery'>
        <div style='width:49%; display:inline-block; vertical-align:top'>
          <h3>Edit Query</h3>
          <div>
          #{
            (for property in @queryProperties
              "
              <div>
                #{property.name}: 
                #{
                  if property.type is "coffeescript"
                    "
                      <div class='description'>#{property.description}</div>
                      #{ 
                      if property.example
                        "
                        <div class='example'>Example:<br/>
                          <pre><code>#{property.example}</code></pre>
                        </div>
                        "
                      else ""
                      }
                      <textarea style='width:100%' id='query-#{dasherize(property.name)}' rows='5' cols='40'>#{property.default or ""}</textarea>
                    "
                  else
                    "
                      <div class='description'>#{property.description}</div>
                      #{ 
                      if property.example
                        "
                        <div class='example'>Example:<br/>
                          <pre><code>#{property.example}</code></pre>
                        </div>
                        "
                      else ""
                      }
                      <input style='width:100%' id='query-#{dasherize(property.name)}' value='#{property.default or ""}'></input>
                    "
                }
              </div>
              "
            ).join("")
          }
          </div>

          <button id='createQueryButton'>Create/Update</button>
          <button id='removeQueryButton'>Remove</button>
        </div>
        <div id='sampleQueryResult' style='width:49%;display:inline-block'>
          <h3>Sample Result</h3>
          Below is a result to help guide creating a query. <button id='loadNewSample'>Load random result</button> (you can also click on any row in the table to load that item here)
          <div style='
            background-color: #282c34;
            color: #98c379;
            font-size: small;
            font-family: monospace;
            '
          >
          </div>
          <span id='queryResultFromSample'></span>
        </div>
      </div>
      <hr/>
    </div>
  "







  renderCalculatedFieldsDiv: => "
    <h3>Calculated Fields <span></span>#{@toggle()}</h3>
    <div style='display:none' id='calculatedFields'>
      <span class='description'>
        Calculated fields are fields that get calculated for each result. This is similar to creating a formula in a spreadsheet. For example, we often ask two questions to get someone's age: their age and whether that age is in years, months or days. However, to compare this data it should all be converted into the same unit, so we create a calculated value called 'Age in Years'. This calculation checks what the type of age it is, then divides the age to return the age in years. This calculated value then appears as a new column in the results table.
      </span>
      <div id='calculated-field-tabulator'></div>
      <div id='createCalculatedField'>
        <div style='width:49%; display:inline-block; vertical-align:top'>
          <h3>Create Calculated Field</h3>
          Title: <input id='title'></input>
          <span class='description'>
            Title is the name of the calculated field.
          </span>
          <br/>
          Calculation: <br/>
          <textarea style='width:100%' id='calculation'></textarea><br/>
          <span class='description'>
            Calculation is the code used to do the calculation. It is coffeescript (like javascript but easier to read and write) code that is run for each result, and receives a variable called 'result' which can be used to do the calculation. It needs to have a return statement to specify what to use as the final calculated result. Example:
            <pre>
              <code>#{ # triple quotes to keep the newlines
              """
  return switch result['age-in-years-months-days'] # Switch based on the age-in-years-months-days result
    when 'Years' then result['age'] # divide as is appropriate
    when 'Months' then result['age']/12.0
    when 'Days' then result['age']/365.0
              """}
              </code>
            </pre>
          </span>
          <br/>
          Initialize:<br/>
          <textarea style='width:100%' id='initialize'></textarea><br/>
          <span class='description'>
          Initialize is used for advanced calculations. It is code that runs before calculating the result. For instance you can query for user data and then setup an object that maps between usernames and their location. The calculation then uses this object instead of doing a query for every single result. Example:
            <pre>
              <code>#{ # triple quotes to keep the newlines
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
              """}
              </code>
            </pre>
          </span>

          <button id='createCalculatedFieldButton'>Create/Update</button>
          <button id='removeCalculatedFieldButton'>Remove</button>
        </div>
        <div id='sampleResult' style='width:49%;display:inline-block'>
          <h3>Sample Result</h3>
          Below is a result to help in creating calculated fields. Click ⊕to add the property to the calculation. <button id='loadNewSample'>Load random result</button> (you can also click on any row in the table to load that item here)
          <div style='
            background-color: #282c34;
            color: #98c379;
            font-size: small;
            font-family: monospace;
            '
          >
          </div>
          <span id='calculationFromSample'></span>
        </div>
      </div>
      <hr/>
    </div>
  "

  loadQueriesAndCalculatedFieldData: =>

    for configurationType in ["calculated-field", "query"]
      configurationDocs = await Tamarind.localDatabaseMirror.allDocs
        startkey: "tamarind-#{configurationType}"
        endkey: "tamarind-#{configurationType}_\uf000"
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

      columns.unshift
        formatter: (cell) =>
          "<a href='#results/#{@serverName}/#{@databaseName}/query/#{cell.getData().Name}'>⇗</a>"

      @tabulators or= {}
      @tabulators[configurationType] = new Tabulator "##{configurationType}-tabulator",
        columns: columns
        height: 200
        initialSort:[
          {column:"enabled", dir:"desc"}
        ]
        data: configurationDocs
      @tabulators[configurationType].on "dataChanged", (changedData) =>
        for change in changedData
          await Tamarind.localDatabaseMirror.upsert change._id, => change
          Tamarind.localDatabaseMirror.replicate.to Tamarind.database,
            doc_ids: [change._id]
        @render()
      @tabulators[configurationType].on "cellClick", (event, cell) =>
        return if cell.getColumn().getField() is "enabled"
        @editItem cell.getData()

  editItem: (data, configurationType) =>
    console.log data
    if data.calculation
      if @unsavedCalculation and (["title", "initialize", "calculation"].find (property) =>
        @$("##{property}").val() isnt ""
      ) and not confirm "You have unsaved changes in the Calculation field, do you want to continue?"
        return

      for property in ["title", "initialize", "calculation"]
        @$("##{property}").val(data[property])
      @updateCalculationFromSample()
      @unsavedCalculation = false
    else if data.Fields or data["Map Function"]
      for property in @queryProperties
        @$("#query-#{dasherize(property.name)}").val(data[property.name])
      @updateQueryResultFromSample()

  getNewSample: (id) =>
    @currentSample = if id? and _(id).isString()
      await Tamarind.localDatabaseMirror.get(id)
    else
      # Choose a random result for helping to build a calculated field
      currentlySelectedData = @tabulatorView?.tabulator?.getData("active")
      randomSample = if currentlySelectedData.length > 0
        _(currentlySelectedData).sample()
      else
        _(@results).sample()

      randomSample

    for sample in ["sampleResult", "sampleQueryResult"]
      @$("##{sample} div").html (for property, value of @currentSample
        "
        <div>
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
    @updateCalculationFromSample()
    @updateQueryResultFromSample()



  addQueryFilters: =>
    if @queryDoc?["Query Field Options"]
      @$("#queryFilters").html "<div style='width=100%;text-align:center;'>Query Field Filters</div>"
      for filterField, queryFieldIndex in @queryDoc["Query Field Options"]

        if filterField.userSelectable is false
          @$("#queryFilters").append if filterField.equals
            "#{filterField.field}: <input readonly=true value='#{filterField.equals}'></input>"
          else
            CSON.stringify filterField
          @$("#queryFilters").append "<br/>"


        else if filterField.userSelectable
          switch filterField.type
            when "Date Range"
              elementId = "dateRange-#{dasherize(filterField.field)}"
              @$("#queryFilters").append "#{filterField.field} Date Range ↔ 
                <input data-query-field-index='#{queryFieldIndex}' class='query-filter-date-range' id='#{elementId}'></input>
              "

              for value in ["startValue", "endValue"]
                if filterField[value] is "now"
                  filterField[value] = moment().format("YYYY-MM-DD")

              @$("##{elementId}").daterangepicker
                "startDate": filterField.startValue
                "endDate": filterField.endValue
                "showWeekNumbers": true
                "ranges":
                  "Last Week (#{moment().subtract(1,'week').format('W')})": [moment().subtract(1,'week').startOf('isoWeek'), moment().subtract(1,'week').endOf('isoWeek')]
                  "Week #{moment().subtract(2,'week').format('W')}": [moment().subtract(2,'week').startOf('isoWeek'), moment().subtract(2,'week').endOf('isoWeek')]
                  'This Month': [moment().startOf('month'), moment().endOf('month')],
                  'Last Month': [moment().subtract(1, 'month').startOf('month'), moment().subtract(1, 'month').endOf('month')],

                  'This Quarter': [moment().startOf('quarter'), moment().endOf('quarter')],
                  'This Quarter Last Year': [moment().subtract(1, 'year').startOf('quarter'), moment().subtract(1, 'year').endOf('quarter')],
                  'Last Quarter': [moment().subtract(1, 'quarter').startOf('quarter'), moment().subtract(1, 'quarter').endOf('quarter')]

                  'This Year': [moment().startOf('year'), moment().endOf('year')],
                  'Last Year': [moment().subtract(1, 'year').startOf('year'), moment().subtract(1, 'year').endOf('year')]
                "locale":
                  "format": "YYYY-MM-DD"
                  "separator": " - "
                  "applyLabel": "Apply"
                  "cancelLabel": "Cancel"
                  "fromLabel": "From"
                  "toLabel": "To"
                  "customRangeLabel": "Custom"
                  "weekLabel": "W"
                  "daysOfWeek": ["Su","Mo","Tu","We","Th","Fr","Sa"]
                  "monthNames": ["January","February","March","April","May","June","July","August","September","October","November","December"]
                  "firstDay": 1
                "alwaysShowCalendars": true

  css: => "
.addPropertyToCalculatedValue{
  cursor: pointer;
}
.description {
  font-size:small;
  color: #00000078;
}
.example {
  font-size:small;
  color: #00000078;
}
#queryFilters{
  background-color: #7F171F;
  color:white;
  padding: 2px;
  

}
  "




module.exports = ResultsView
