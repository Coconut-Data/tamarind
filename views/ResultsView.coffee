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

AsyncFunction = Object.getPrototypeOf(`async function(){}`).constructor; # Strange hack to build AsyncFunctions https://davidwalsh.name/async-function-class

hljs = require 'highlight.js/lib/core';
hljs.registerLanguage('coffeescript', require ('highlight.js/lib/languages/coffeescript'))

{QueryCommand,DeleteItemCommand} = require "@aws-sdk/client-dynamodb"
{marshall,unmarshall} = require("@aws-sdk/util-dynamodb")

global.QuestionSet = require '../models/QuestionSet'

TabulatorView = require './TabulatorView'

class ResultsView extends Backbone.View
  events: =>
    "click #download": "csv"
    "click #pivotButton": "loadPivotTable"
    "click #createCalculatedFieldButton": "createCalculatedField"
    "click #removeCalculatedFieldButton": "removeCalculatedField"
    "click .addPropertyToCalculatedValue": "addPropertyToCalculatedValue"
    "change #calculation": "updateCalculationFromSample"
    "click #loadNewSample": "getNewSample"
    "click .toggleNext": "toggleNext"
    "click #refresh": "refresh"

  refresh: =>
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
      if confirm "No return statement, shall I add it?"
        calculation = @$("#calculation").val().split(/\n/)
        lastLine = calculation.pop()
        lastLine = "return " + lastLine
        calculation.push lastLine

        @$("#calculation").val calculation.join("\n")
        calculation = @$("#calculation").val()

    calculationFunction = new Function('result', Coffeescript.compile(calculation, bare:true))
    @$("#calculationFromSample").html "
      Calculation with current sample: <span class='font-weight:bold'>
      #{
        await calculationFunction(@currentSample)
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


  getResults: (options = {}) =>
    @$("#messages").html "<h1>Loading data</h1>"
    questionSetName = @questionSet.name()

    @$("#messages").append "Building index, this takes a while the first time."
    await Tamarind.localDatabaseMirror.createIndex
      index:
        fields: ["question", "createdAt"]
    .then (result) =>
      console.log result

    @$("#messages").html "<h1>Loading data</h1>"

    options.query = """
    console.log options
    db = new PouchDB("https://analytics:usethedata@zanzibar.cococloud.co/zanzibar")
    #return db.allDocs
    return Tamarind.localDatabaseMirror.find
      selector:
        question: options.questionSetName
        #createdAt: 
        #  $gt: "2021"
      fields: options.selectedFields
      include_docs: true
      #limit: 10000
    .then (result) =>
      console.log options.selectedFields
      console.log result
      Promise.resolve result.docs
    """

    if options.query
      global.queryFunction = new AsyncFunction('options', Coffeescript.compile(options.query, bare:true))
      
      options = 
        questionSetName: questionSetName
        selectedFields: options.selectedFields or null
      @results = await queryFunction(options)

    else if Tamarind.localDatabaseMirror

      @startkey = options?.startkey
      @endkey = options?.endkey

      unless @startkey? and @endkey?

        @startkey = "result-#{underscored(questionSetName.toLowerCase())}"
        @endkey = "result-#{underscored(questionSetName.toLowerCase())}-\ufff0"

        #### For entomological surveillance data ####
        if Tamarind.databaseName is "entomology_surveillance"
        #
          acronymForEnto = (idName) =>
            #create acronmym for ID
            acronym = ""
            for word in idName.split(" ")
              acronym += word[0].toUpperCase() unless ["ID","SPECIMEN","COLLECTION","INVESTIGATION"].includes word.toUpperCase()
            acronym

          @startkey = "result-#{acronymForEnto(questionSetName)}"
          @endkey = "result-#{acronymForEnto(questionSetName)}-\ufff0"

      @results = await Tamarind.localDatabaseMirror.allDocs
        startkey: @startkey
        endkey: @endkey
        include_docs: true
      .then (result) => Promise.resolve _(result.rows)?.pluck "doc"
    else if Tamarind.dynamoDBClient
      #TODO store results in local pouchdb and then just get updates

      @results = []

      loop

        result = await Tamarind.dynamoDBClient.send(
          new QueryCommand
            TableName: "Gateway-#{@databaseName}"
            IndexName: "resultsByQuestionSetAndUpdateTime"
            KeyConditionExpression: 'questionSetName = :questionSetName'
            ExpressionAttributeValues:
              ':questionSetName':
                'S': questionSetName
            ScanIndexForward: false
            ExclusiveStartKey: result?.LastEvaluatedKey
        )

        @results.push(...for item in result.Items
          dbItem = unmarshall(item)
          item = dbItem.reporting
          item._startTime = dbItem.startTime # Need this to be able to delete
          item
        )

        break unless result.LastEvaluatedKey #lastEvaluatedKey means there are more

      Promise.resolve(@results)


  getResultsWithCalculatedFields: (selectedFields) =>
    enabledCalculatedFields = @tabulators["calculated-field"].getData().filter (calculatedField) => calculatedField.enabled

    # Wrap in function for awaits and get indents right
    for calculatedField in enabledCalculatedFields
      if calculatedField.initialize

        # https://stackoverflow.com/questions/1271516/executing-anonymous-functions-created-using-javascript-eval
        initializeFunction = new AsyncFunction(Coffeescript.compile(calculatedField.initialize, bare:true))
        await initializeFunction()

      # Might be faster to use new Function if there is no need of async here
      calculatedField.calculationFunction = new AsyncFunction('result', Coffeescript.compile(calculatedField.calculation, bare:true))

    if enabledCalculatedFields?.length > 0
      @$("#messages").html "<h1>Adding Calculated Fields</h1>"
      # TODO add the fields required for the calculation
      for result in await @getResults(selectedFields: selectedFields)
        for calculatedField in enabledCalculatedFields
          result[calculatedField.title] = await calculatedField.calculationFunction(result)
        result
    else

      @getResults(selectedFields: selectedFields)

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
      <h2>
        Results for <a href='#questionSet/#{@serverName}/#{@databaseName}/#{@questionSet.name()}'>#{@questionSet.name()}</a> 
      </h2>
      <div id='messages'></div>
      <div id='dataChangesMessages'></div>
      #{
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
      #{@renderQueriesDiv()}
      #{@renderCalculatedFieldsDiv()}
      <div id='tabulatorView'>
      </div>
    "


    hljs.configure
      languages: ["coffeescript", "json"]
      useBR: false

    @$('pre code').each (i, snippet) =>
      hljs.highlightElement(snippet);

    @loadQueriesAndCalculatedFieldData()

    @tabulatorView = new TabulatorView()
    @tabulatorView.setElement("#tabulatorView")
    @tabulatorView.questionSet = @questionSet
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
    # If it's a small database we can wait for it and load everything in memory
    # Otherwise load it empty to get column selector available
    # Then only get columns that are displayed
    #
    if (await Tamarind.localDatabaseMirror.info()).doc_count > 10000
      @tabulatorView.data = []
      @tabulatorView.render()

      defaultFields = @tabulatorView.availableColumns[0..3].map (column) => column.field
      @getResultsWithCalculatedFields(defaultFields)
      .then (result) => 
        console.log "Setting with new data and render"
        @tabulatorView.data = result
        @tabulatorView.renderTabulator()

      # Listen for columns/fields to be changed
      @$("#availableTitles")[0].addEventListener 'change', (event) =>
        selectedFields = @tabulatorView.availableColumns.filter (column) =>
          @tabulatorView.selector.getValue(true).includes column.title
        .map (column) => column.field

        @tabulatorView.data = await @getResultsWithCalculatedFields(selectedFields)
        @tabulatorView.renderTabulator()
    else
      @tabulatorView.data = await getResultsWithCalculatedFields()
      @tabulatorView.render()


    @getNewSample()
    @$("#messages").html ""





  renderQueriesDiv: => 

    @queryProperties = [
        name: "Name"
        description: "Name of the query"
        default: "default"
      ,
        name: "Index"
        description: "Used to make the query fast"
        type: "coffeescript"
        default: """
index:
fields: ["question", "createdAt"]
    """
      ,
        name: "Selector"
        description: "Selects the data using the index"
        type: "coffeescript"
        default: """
selector:
question: options.questionSetName
        """
      ,
        name: "Filter Fields"
        description: "Fields to display to user for filtering the query, like date or region. This happens at the query stage not within the table."
        default: "[{field:'createdAt', startValue: '2021-01-01', endValue: 'now'}]"
        type: "coffeescript"
      ,
        name: "Initial Fields"
        description: "Fields that will be retrieved at the beginning. If left blank, it gets the first 4 most frequently filled fields."
        default: "Name, Birthdate"
    ]

    "
    <h3>Queries <span></span>#{@toggle()}</h3>
    <div style='display:none' id='queries'>
      <span class='description'>
        Queries are what is used to select the data you want to display.
      </span>
      <div id='query-tabulator'></div>
      <div id='createQuery'>
        <div style='width:49%; display:inline-block; vertical-align:top'>
          <h3>Create Query</h3>
          <div>
          #{
            (for property in @queryProperties
              "
              <div>
                #{property.name}: 
                #{
                  if property.type is "coffeescript"
                    "
                      <textarea id='query-#{property.name}' rows='2'>#{property.default or ""}</textarea>
                      <div class='description'></div>
                    "
                  else
                    "
                      <input id='query-#{property.name}' value='#{property.default or ""}'></input>
                      <div class='description'></div>
                    "
                }
              </div>
              "
            ).join("")
          }
          </div>

          <button id='createQueryButton'>Create</button>
          <button id='removeQueryButton'>Remove</button>
          <span id='calculationFromSample'></span>
        </div>
        <div id='sampleResult' style='width:49%;display:inline-block'>
          <h3>Sample Query Result</h3>
          Below is the current query limited to 10 items.
          <div style='
            background-color: #282c34;
            color: #98c379;
            font-size: small;
            font-family: monospace;
            '
          >
          </div>
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

          <button id='createCalculatedFieldButton'>Create</button>
          <button id='removeCalculatedFieldButton'>Remove</button>
          <span id='calculationFromSample'></span>
        </div>
        <div id='sampleResult' style='width:49%;display:inline-block'>
          <h3>Sample Result</h3>
          Below is a randomly selected result to help in creating calculated fields. Click ⊕to add the property to the calculation. <button id='loadNewSample'>Load new result</button>
          <div style='
            background-color: #282c34;
            color: #98c379;
            font-size: small;
            font-family: monospace;
            '
          >
          </div>
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

      @tabulators or= {}
      @tabulators[configurationType] = new Tabulator "##{configurationType}-tabulator",
        height: 200
        columns: (
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

            if property is "enabled"
              column.title = ""
              column.editor = "tickCross"
              column.width = 30
              column.formatter = "tickCross"

            column
          _(columns).sortBy (column) -> column.field isnt "enabled" # Get enabled at the beginning
        )
        initialSort:[
          {column:"enabled", dir:"desc"}
        ]
        data: configurationDocs
        dataChanged: (changedData) =>
          for change in changedData
            await Tamarind.localDatabaseMirror.upsert change._id, => change
            Tamarind.localDatabaseMirror.replicate.to Tamarind.database,
              doc_ids: [change._id]
          @render()
        cellClick: (event, cell) =>
          return if cell.getColumn().getField() is "enabled"
          switch configurationType
            when "calculated-field"
              @editCalculatedField(cell.getData())
            when "query"
              @editQuery(cell.getData())



  editQuery: (data) =>
    for property in @queryProperties
      @$("##{property}").val(data[property])


  editCalculatedField: (data) =>
    if @unsavedCalculation and (["title", "initialize", "calculation"].find (property) =>
      @$("##{property}").val() isnt ""
    ) and not confirm "You have unsaved changes in the Calculation field, do you want to continue?"
      return

    for property in ["title", "initialize", "calculation"]
      @$("##{property}").val(data[property])
    @updateCalculationFromSample()
    @unsavedCalculation = false

  getNewSample: =>
    # Choose a random result for helping to build a calculated field
    currentlySelectedData = @tabulatorView?.tabulator?.getData("active")
    @currentSample = if currentlySelectedData.length > 0
      _(currentlySelectedData).sample()
    else
      _(@results).sample()
    @$("#sampleResult div").html (for property, value of @currentSample
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

  css: => "
.addPropertyToCalculatedValue{
  cursor: pointer;
}
.description {
  font-size:small;
  color: #00000078;
}
  "

module.exports = ResultsView
