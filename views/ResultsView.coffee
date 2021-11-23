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

{QueryCommand,DeleteItemCommand} = require "@aws-sdk/client-dynamodb"
{marshall,unmarshall} = require("@aws-sdk/util-dynamodb")

global.QuestionSet = require '../models/QuestionSet'
global.QueryDoc = require '../models/QueryDoc'

TabulatorView = require './TabulatorView'
TabulatorWithFormView = require './TabulatorWithFormView'

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
    "click #loadNewSample": "updateSample"
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
    return if queryName is null or queryName is ""
    newQueryDoc.Name = queryName
    newQueryDoc._id = "tamarind-queries-#{queryName}"

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
      console.log "Date Range changed, queryAndLoadTable"
      @queryAndLoadTable()

  getQueryDoc: =>
    queryDoc = new QueryDoc()
    queryDoc.Name = @queryDocName or "#{@questionSet?.name()}-default" or throw "No query configuration"
    await queryDoc.fetch()
    .catch (error) =>
      console.log "No query doc, creating default one."
      if @questionSet?.name() and await Tamarind.localDatabaseMirror.get("tamarind-indexes-Results By Question And Date").catch( (error) => Promise.resolve null)
        queryDoc.Index = "Results By Question And Date"
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
      else
        queryDoc.Index = "_all_docs"
      Promise.resolve queryDoc

    $("#title").html "
      <a href='#server/#{@serverName}'>#{@databaseName}</a> 
      <span style='color:white'>➔ </span>
      <a href='#database/#{@serverName}/#{@databaseName}'>#{queryDoc.Name}</a> 
    "

    queryDoc

  # TODO change this to take a queryDoc as an argument
  # TODO allows multiple query docs
  # TODO some kind of merging when multiple query docs
  getResults: (options = {}) =>

    ###
    unless @queryDoc
      # Setup the default queryDoc
      @queryDoc = new QueryDoc()
      @queryDoc.Name = "#{@questionSet}-default"
    ###

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

    if @availableCalculatedFieldDocs?.length > 0
      if @currentlySelectedFields?.length > 0
        availableCalculatedFieldTitles = _(@availableCalculatedFieldDocs).pluck("Title")

        currentlySelectedCalculatedFieldTitles = _.intersection(@currentlySelectedFields, availableCalculatedFieldTitles)

    currentlySelectedCalculatedFields = @availableCalculatedFieldDocs.filter (field) =>
      currentlySelectedCalculatedFieldTitles?.includes field.Title

    if currentlySelectedCalculatedFields.length > 0
      extraFieldsNeededForCalculatedFields = []
      for calculatedField in currentlySelectedCalculatedFields
        for match in (calculatedField.Calculation + calculatedField.Initialize).match(/(result\[.+?\])|result.[a-zA-Z-_]+/g)
          fieldName = match.replace(/result\./,"")
          .replace(/result\[['"]/,"")
          .replace(/['"]\]/,"")
          extraFieldsNeededForCalculatedFields.push fieldName

        if calculatedField.Initialize
          # https://stackoverflow.com/questions/1271516/executing-anonymous-functions-created-using-javascript-eval
          try
            initializeFunction = new AsyncFunction(Coffeescript.compile(calculatedField.Initialize, bare:true))
          catch error then alert "Error compiling #{calculatedField.Title}: #{error}\n#{CSON.stringify calculatedField, null, "  "}"
          await initializeFunction()

        # Might be faster to use new Function if there is no need of async here
        calculatedField.calculationFunction = new AsyncFunction('result', 
          try
            Coffeescript.compile(calculatedField.Calculation, bare:true)
          catch error then alert "Error compiling #{calculatedField.Title}: #{error}\n#{CSON.stringify calculatedField, null, "  "}"
        )

      extraFieldsNeededForCalculatedFields = _(extraFieldsNeededForCalculatedFields).unique()

      results = await @getResults(extraFieldsNeededForCalculatedFields: extraFieldsNeededForCalculatedFields)
      @$("#messages").append "<h2>Adding Calculated Fields</h2>"
      for result in results
        for calculatedField in currentlySelectedCalculatedFields
          result[calculatedField.Title] = await calculatedField.calculationFunction(result)
        result
    else

      @getResults()

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
      <button id='createNewQueryFromCurrentConfiguration'>Save current Query</button>
      #{
        (for type in ["indexes","queries","calculated-fields"]
          "<div id='#{type}'></div>"
        ).join("")
      }
      <div id='queryFilters'></div>
      <div id='tabulatorView'></div>
      </div>
    "

    @tabulatorWithFormViews = {}
    for type in ["indexes","queries","calculated-fields"]
      @tabulatorWithFormViews[type] = await TabulatorWithFormView.create(type)
      @tabulatorWithFormViews[type].setElement @$("##{type}")
      await @tabulatorWithFormViews[type].render()

    @tabulatorView = new TabulatorView()
    @tabulatorView.setElement("#tabulatorView")
    @tabulatorView.questionSet = @questionSet
    @availableCalculatedFieldDocs = await Tamarind.localDatabaseMirror.allDocs
      startkey: "tamarind-calculated-fields"
      endkey: "tamarind-calculated-fields\uf000"
      include_docs: true
    .then (result) => Promise.resolve(row.doc for row in result.rows)

    @tabulatorView.availableCalculatedFields = _(@availableCalculatedFieldDocs).pluck "Title"

    @queryDoc = await @getQueryDoc()
    console.log @queryDoc
    if @queryDoc?.questionSet # This is used for determining availableFields
      @questionSet = @queryDoc.questionSet
      @tabulatorView.questionSet = @questionSet
    @addQueryFilters()
    # empty string is falsy
    @tabulatorView.initialFields = if @tabulatorView.initialFields then @queryDoc?["Initial Fields"]?.split(/, */)

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
      @updateSample(row.getData().id or row.getData()._id)

    await @queryAndLoadTable()

    # Listen for columns/fields to be changed
    @$("#availableTitles")[0].addEventListener 'change', (event) =>
      previouslySelectedFields = @currentlySelectedFields or []
      @currentlySelectedFields = _(@tabulatorView.availableColumns).filter (column) =>
        @tabulatorView.selector.getValue(true).includes column.title
      .map (column) => column.title

      changedField = _(@currentlySelectedFields).without(previouslySelectedFields)[0] or null
      if _(_(@availableCalculatedFieldDocs).pluck "Title").includes changedField
        console.log "Selected column is calculated field so need to calculate"
        @queryAndLoadTable()

  queryAndLoadTable: =>
    @tabulatorView.data = await @getResultsWithCalculatedFields()
    @$("#messages").html ""
    if @tabulatorView.tabulator
      @tabulatorView.renderTabulator()
    else
      await @tabulatorView.render()
    @updateSample()

  updateSample: (id) =>
    sample = if id? and _(id).isString()
      await Tamarind.localDatabaseMirror.get(id)
    else
      # Choose a random result
      _(@tabulatorView?.tabulator?.getData("active")).sample()

    for key, tabulatorWithFormView of @tabulatorWithFormViews
      tabulatorWithFormView.renderSample(sample)

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
