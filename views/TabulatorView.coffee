$ = require 'jquery'
require 'jquery-ui-browserify'

Backbone = require 'backbone'
Backbone.$  = $

Tabulator = require 'tabulator-tables'
Choices = require 'choices.js'

distinctColors = (require 'distinct-colors').default
Chart = require 'chart.js'
ChartDataLabels = require 'chartjs-plugin-datalabels'

PivotTable = require 'pivottable'
global.slugify = require("underscore.string/slugify")
titleize = require("underscore.string/titleize")
global.camelize = require("underscore.string/camelize")
global.capitalize = require("underscore.string/capitalize")

class TabulatorView extends Backbone.View

  events:
    "click #download": "csv"
    "click #downloadItemCount": "itemCountCSV"
    "change select#columnToCount": "updateColumnCount"
    "click #pivotButton": "loadPivotTable"
    "change #includeEmpties": "updateIncludeEmpties"
    "click .toggleNext": "toggleNext"

  updateIncludeEmpties: =>
    @includeEmptiesInCount = @$("#includeEmpties").is(":checked")
    @updateColumnCount()

  csv: => @tabulator.download "csv", "#{@questionSet.name()}-#{moment().format("YYYY-MM-DD_HHmm")}.csv"

  itemCountCSV: => @itemCountTabulator.download "csv", "#{@questionSet.name()}ItemCount.csv"

  toggleNext: (event) =>
    toggler = $(event.target).closest(".toggleNext")
    toggler.children().each (index, span) => 
      $(span).toggle()

    #TODO
    toggler.parent().next("div").toggle() # Get the header then the sibling div

  toggle: =>
    "
    <span style='cursor:pointer' class='toggleNext'>
      <span style='color:#00bcd4'>►</span>
      <span style='display:none; color:#00bcd4;'>▼</span>
    </span>
    "

  render: =>
    @$el.html "
      <style>
        #content .tabulator-row.tabulator-row-even {
          background-color: #7f171f1a;
        }

        #content .tabulator-col {
          background-color: #7f171f29
        }
      </style>
      <button id='download'>CSV ↓</button> <small>Add more fields by clicking the box below</small>
      <div id='tabulatorSelector'>
        <select id='availableTitles' multiple></select>
      </div>
      <div id='selector'>
      </div>
      <div id='tabulatorForTabulatorView'></div>
      <div>
        Number of Rows: 
        <span id='numberRows'></span>
      </div>
      <br/>
      <h3>Additional Analysis <span></span>#{@toggle()}</h3>
      <div>
        <h4>Charts<span></span>#{@toggle()}</h4>
        <div>
          <li>TODO: Bar and line option
          <li>TODO: Time series
          To count and graph unique values in a particular column, select the column here: <select id='columnToCount'>
          </select>
          <div id='itemCount'>
            <div style='width: 200px; display:inline-block' id='itemCountTabulator'></div>
            <span id='columnCountOptions' style='display:none; vertical-align:top'>
              <button id='downloadItemCount'>CSV ↓</button>
              <input type='checkbox' id='includeEmpties'>Include undefined, null and empty</input>
            </span>
            <div style='width: 600px; display:inline-block; vertical-align:top' id='itemCountChart'>
              <canvas id='itemCountChartCanvas'></canvas>
            </div>
          </div>
        </div>
        <hr/>

        <h4>Pivot Tables<span></span>#{@toggle()}</h4>
        <div id='pivotTableDiv'>
          For more complicated groupings and comparisons you can create a <button id='pivotButton'>Pivot Table</button>. The pivot table can also output CSV data that can be copy and pasted into a spreadsheet.
          <div id='pivotTable'></div>
        </div>
        <hr/>

        <h4>Maps<span></span>#{@toggle()}</h4>
        <div id='mappingDiv'>
          If the data includes a longitude and latitude field it will be mapped here.
          <li>TODO: Animated Time series
          <li>TODO: Group by count and adjust dot size/heat map
          <div id='map'></div>
        </div>
      </div>
    "

    @availableTitles or= @getAvailableColumns()
    availableTitles = _(@availableColumns).pluck("title")

    @initialTitles = if @initialFields? and @initialFields.length > 0
      for field in @initialFields
        _(@availableColumns).findWhere(field: field)?.title
    else
      availableTitles[0..3]

    choicesData = for title in _(@initialTitles.concat(_(availableTitles).sort())).uniq() # This preserves order of initialTitles and alphabetizes the rest
      value: title
      selected: if _(@initialTitles).contains title then true else false

    @selector = new Choices "#availableTitles",
      choices: choicesData
      shouldSort: false
      removeItemButton: true
      searchResultLimit: 10

    @$("#availableTitles")[0].addEventListener 'change', (event) =>
      @renderTabulator()

    @renderTabulator()


  getAvailableColumns: () =>
    questionLabels = _(@questionSet.data.questions).pluck "label"

    @fieldsFromData or= {}

    if _(@fieldsFromData).isEmpty()
      for item in _(@data).sample(10000) # In case we have results from older question sets with different questions we will find it here. Use sample to put an upper limit on how many to check. (If the number of results is less than the sample target it just uses the number of results.
        for key in Object.keys(item)
          @fieldsFromData[key] = true
      @fieldsFromData = Object.keys(@fieldsFromData)

    mappingsForLabelsToDataFields = {}
    unmappedLabels = []
    mappedFields = []
    for label in questionLabels
      if @fieldsFromData.includes label
        mappingsForLabelsToDataFields[label] = label
        mappedFields.push label
      else if @fieldsFromData.includes (mappedLabel = slugify(label))
        mappingsForLabelsToDataFields[label] = mappedLabel
        mappedFields.push mappedLabel
      else if @fieldsFromData.includes mappedLabel = capitalize(camelize(slugify(label)))
        mappingsForLabelsToDataFields[label] = mappedLabel
        mappedFields.push mappedLabel
      else if label is "Malaria Case ID"
        mappingsForLabelsToDataFields[label] = "MalariaCaseID"
        mappedFields.push "MalariaCaseID"
      else
        unmappedLabels.push label

    unmappedFields = _(@fieldsFromData).difference mappedFields

    for label in unmappedLabels
      mappingsForLabelsToDataFields[label] = label

    for field in unmappedFields
      continue if [
        "_id"
        "_rev"
        "collection"
      ].includes field
      mappingsForLabelsToDataFields[field] = field

    orderedColumnTitlesAndFields = for label, field of mappingsForLabelsToDataFields
      title: label
      field: field
      headerFilter: "input"

    
    fields = _(orderedColumnTitlesAndFields).pluck("field") #Used to stop duplicate calculated fields configured in Initial Fields
    # Include the calculated fields at the front
    for calculatedField in @availableCalculatedFields
      unless _(fields).includes calculatedField
        orderedColumnTitlesAndFields.unshift # to the front
          title: calculatedField
          field: calculatedField
          headerFilter: "input"

    if @excludeTitles? and @excludeTitles.length > 0
      orderedColumnTitlesAndFields = orderedColumnTitlesAndFields.filter (column) => 
        not @excludeFields.includes(column.title)

    # Having periods in the column name breaks things, so take them out
    @fieldsWithPeriodRemoved = []
    @availableColumns = for column in orderedColumnTitlesAndFields
      if column.field.match(/\./)
        @fieldsWithPeriodRemoved.push column.field
        column.field = column.field.replace(/\./,"")
      column


  updateColumnCountOptions: =>
    @$("#columnToCount").html "<option></option>" + (for column in @selector.getValue(true)
        "<option>#{column}</option>"
      ).join("")

  updateColumnCount: =>

    return unless @$("#columnToCount option:selected").text()

    @$("#columnCountOptions").show()

    columnFieldName = @availableColumns.find( (column) =>
      column.title is @$("#columnToCount option:selected").text()
    ).field

    counts = {}

    if columnFieldName is ""
      @$("#itemCount").hide()
      return

    return unless @tabulator?

    @$("#itemCount").show()

    for rowData in @tabulator.getData("active")
      unless @includeEmptiesInCount
        if [undefined, "", null].includes rowData[columnFieldName]
          continue

      counts[rowData[columnFieldName]] or= 0
      counts[rowData[columnFieldName]] += 1
      console.log rowData[columnFieldName]

    countData = for fieldName, amount of counts
      {
        "#{columnFieldName}": fieldName
        Count: amount
      }

    countData = _(countData).sortBy("Count").reverse()

    return unless countData.length > 0

    @itemCountTabulator = new Tabulator "#itemCountTabulator",
      height: 400
      columns: [
        {field: columnFieldName, name: columnFieldName}
        {field: "Count", name: "Count"}
      ]
      initialSort:[
        {column:"Count", dir:"desc"}
      ]
      data: countData

    colors = distinctColors(
      count: Object.values(counts).length
      hueMin: 0
      hueMax: 360
      chromaMin: 40
      chromaMax: 70
      lightMin: 15
      lightMax: 85
    )

    ctx = @$("#itemCountChartCanvas")

    data = []
    labels = []


    if @chart?
      @chart.destroy()
    @chart = new Chart(ctx, {
      type: 'doughnut',
      data: 
        datasets: [
          {
            data: _(countData).pluck "Count"
            backgroundColor:  for distinctColor in colors
              color = distinctColor.rgb()
              "rgba(#{color.join(",")},0.5)"
          }
        ]
        labels: _(countData).pluck columnFieldName
      options:
        legend:
          position: 'right'

    })

  renderTabulator: =>

    selectedColumns = @availableColumns.filter (column) =>
      @selector.getValue(true).includes column.title

    if @tabulator
      @tabulator.setColumns(selectedColumns)
      @tabulator.setData @data
    else

      if @fieldsWithPeriodRemoved.length > 0
        @data = for item in @data
          for column in @fieldsWithPeriodRemoved
            item[column.replace(/\./,"")] = item[column]
          item

      @tabulator = new Tabulator "#tabulatorForTabulatorView",
        height: 500
        columns: selectedColumns
        data: @data
        dataFiltered: (filters, rows) =>
          @$("#numberRows").html(rows.length)
          _.delay =>
            @updateColumnCount()
          , 500
        dataLoaded: (data) =>
          @$("#numberRows").html(data.length)
          _.delay =>
            @updateColumnCount()
          , 500
        rowClick: (event, row) =>
          @rowClick?(row) # If a rowClick function exists call it - lets others views hook into this

    @updateColumnCountOptions()




  loadPivotTable: =>

    fieldNames = @availableColumns.filter( (column) =>
      @selector.getValue(true).includes column.title
    ).map (column) => column.field

    data = for rowData in @tabulator.getData("active")
      _(rowData).pick fieldNames

    #@$("#pivotTable").pivot data,
    #  rows: ["Classification"]
    #  cols: ["Household District"]
    @pivotFields or= @initialTitles[0..1]

    @$("#pivotTable").pivotUI data,
      rows: [@pivotFields[0]]
      cols: [@pivotFields[1]]
      rendererName: "Heatmap"
      renderers: _($.pivotUtilities.renderers).extend "CSV Export": (pivotData, opts) ->
        defaults = localeStrings: {}

        opts = $.extend(true, {}, defaults, opts)

        rowKeys = pivotData.getRowKeys()
        rowKeys.push [] if rowKeys.length == 0
        colKeys = pivotData.getColKeys()
        colKeys.push [] if colKeys.length == 0
        rowAttrs = pivotData.rowAttrs
        colAttrs = pivotData.colAttrs

        result = []

        row = []
        for rowAttr in rowAttrs
            row.push rowAttr
        if colKeys.length == 1 and colKeys[0].length == 0
            row.push pivotData.aggregatorName
        else
            for colKey in colKeys
                row.push colKey.join("-")

        result.push row

        for rowKey in rowKeys
            row = []
            for r in rowKey
                row.push r

            for colKey in colKeys
                agg = pivotData.getAggregator(rowKey, colKey)
                if agg.value()?
                    row.push agg.value()
                else
                    row.push ""
            result.push row
        text = ""
        for r in result
            text += r.join(",")+"\n"

        return $("<textarea>").text(text).css(
                width: ($(window).width() / 2) + "px",
                height: ($(window).height() / 2) + "px")

module.exports = TabulatorView
