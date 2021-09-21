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
slugify = require("underscore.string/slugify")
titleize = require("underscore.string/titleize")

class TabulatorView extends Backbone.View

  events:
    "click #download": "csv"
    "click #downloadItemCount": "itemCountCSV"
    "change select#columnToCount": "updateColumnCount"
    "click #pivotButton": "loadPivotTable"

  csv: => @tabulator.download "csv", "#{@questionSet.name()}-#{moment().format("YYYY-MM-DD_HHmm")}.csv"

  itemCountCSV: => @itemCountTabulator.download "csv", "#{@questionSet.name()}ItemCount.csv"

  render: =>
    @$el.html "
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
      <h4>Additional Analysis</h4>
      <div>
        To count and graph unique values in a particular column, select the column here: <select id='columnToCount'>
        </select>
        <div id='itemCount'>
          <div style='width: 200px; display:inline-block' id='itemCountTabulator'></div>
          <button style='vertical-align:top' id='downloadItemCount'>CSV ↓</button>
          <div style='width: 600px; display:inline-block; vertical-align:top' id='itemCountChart'>
            <canvas id='itemCountChartCanvas'></canvas>
          </div>
        </div>
      </div>
      <hr/>
      <div id='pivotTableDiv'>
        For more complicated groupings and comparisons you can create a <button id='pivotButton'>Pivot Table</button>. The pivot table can also output CSV data that can be copy and pasted into a spreadsheet.
        <div id='pivotTable'></div>
      </div>
    "

    @getAvailableColumns()
    availableTitles = _(@availableColumns).pluck("title")

    @preselectedTitles or= availableTitles[0..3]

    choicesData = for title in _(@preselectedTitles.concat(_(availableTitles).sort())).uniq() # This preserves order of preselectedTitles and alphabetizes the rest
      value: title
      selected: if _(@preselectedTitles).contains title then true else false

    @selector = new Choices "#availableTitles",
      choices: choicesData
      shouldSort: false
      removeItemButton: true

    @$("#availableTitles")[0].addEventListener 'change', (event) =>
      @renderTabulator()

    @renderTabulator()


  getAvailableColumns: =>
    orderedColumnTitlesAndFields = @questionSet.data.questions.map (question) => 
      title: question.label
      field: slugify(question.label) # Should only do this when slugification happens. It's not happening on Gooseberry data.
      headerFilter: "input"

    columnNamesFromData = {}
    for item in _(@data).sample(10000) # In case we have results from older question sets with different questions we will find it here. Use sample to put an upper limit on how many to check. (If the number of results is less than the sample target it just uses the number of results.
      for key in Object.keys(item)
        columnNamesFromData[key] = true


    fieldsFromCurrentQuestionSet = _(orderedColumnTitlesAndFields).pluck("field")
    for columnName in Object.keys(columnNamesFromData)
      unless fieldsFromCurrentQuestionSet.includes(columnName)
        orderedColumnTitlesAndFields.push
          title: titleize(columnName)
          field: columnName
          headerFilter: "input"

    if @excludeTitles
      orderedColumnTitlesAndFields = orderedColumnTitlesAndFields.filter (column) => 
        not @excludeFields.includes(column.title)

    # Having periods in the column name breaks things, so take them out
    columnsWithPeriodRemoved = []
    @availableColumns = for column in orderedColumnTitlesAndFields
      if column.field.match(/\./)
        columnsWithPeriodRemoved.push column.field
        column.field = column.field.replace(/\./,"")
      column

    # FIX THE DATA TOO TODO Notsure if this works
    if columnsWithPeriodRemoved.length > 0
      for item in @data
        for column in columnsWithPeriodRemoved
          item[column.replace(/\./,"")] = item[column]





  updateColumnCountOptions: =>
    @$("#columnToCount").html "<option></option>" + (for column in @selector.getValue(true)
        "<option>#{column}</option>"
      ).join("")

  updateColumnCount: () =>

    return unless @$("#columnToCount option:selected").text()

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
      counts[rowData[columnFieldName]] or= 0
      counts[rowData[columnFieldName]] += 1

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
    @pivotFields or= @preselectedTitles[0..1]

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
