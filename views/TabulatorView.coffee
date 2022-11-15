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
Leaflet = require 'leaflet'

global.slugify = require("underscore.string/slugify")
titleize = require("underscore.string/titleize")
global.camelize = require("underscore.string/camelize")
global.capitalize = require("underscore.string/capitalize")
hljs = require 'highlight.js/lib/core';
hljs.registerLanguage('coffeescript', require ('highlight.js/lib/languages/coffeescript'))
hljs.configure
  languages: ["coffeescript", "json"]
  useBR: false

class TabulatorView extends Backbone.View

  events:
    "click #download": "csv"
    "click #downloadItemCount": "itemCountCSV"
    "change select#columnToCount": "updateColumnCount"
    "click #pivotButton": "loadPivotTable"
    "change #includeEmpties": "updateIncludeEmpties"
    "click .toggleNextSection": "toggleNext"
    "click #applyAdvancedFilter": "applyAdvancedFilter"
    "click .close": "closeModal"
    "click #drawMap": "drawMap"
    "click .showImage": "showImage"
    "change #allowEdits": "toggleAllowEdits"
    "click #saveEdits": "saveEdits"
    "click #undoEdits": "undoEdits"

  saveEdits: =>
    confirmedChanges = {}
    for cell in @tabulator.getEditedCells()
      field = cell.getColumn().getField()
      docId = cell.getData()?._id

      if confirm("Are you sure you want to change: #{docId} field: #{field} from #{cell.getInitialValue()} to #{cell.getValue()}")
        confirmedChanges[docId] or= {}
        confirmedChanges[docId][field] = cell.getValue()

    updatedDocs = for docId, fieldWithNewValue of confirmedChanges
      updatedDoc = await Tamarind.localDatabaseMirror.get(docId)
      for field, newValue of fieldWithNewValue
        if updatedDoc[field]?
          updatedDoc[field] = newValue
        else
          if confirm "Current doc does not have the field #{field}, are you sure you want to add this?"
            updatedDoc[field] = newValue
      updatedDoc

    await Tamarind.localDatabaseMirror.bulkDocs updatedDocs

    if confirm "Local database updated (you can use the RESET button to undo this and reset your local database to match the server). Do you also want to make these changes on the server: #{Tamarind.localDatabaseMirror.remoteDatabase.name.replace(/\/\/.*@/,"//")} (this will NOT be undo-able!)?"
      Tamarind.localDatabaseMirror.replicate.to Tamarind.localDatabaseMirror.remoteDatabase,  
        doc_ids: _(updatedDocs).pluck("_id")
      .on "complete", =>
        alert "Remote server updated"

    console.log updatedDocs
    @tabulator.clearCellEdited()
    @$("#saveEdits").hide()
    @$("#undoEdits").hide()




  toggleAllowEdits: =>
    @editsEnabled = @$("#allowEdits").is(":checked")
    @renderTabulator()

  showImage: (event) =>
    @$("#dataForCurrentRow").html "<img src='#{$(event.target).attr("data-image")}'>"
    @$("#modal").show()

  drawMap: =>
    @map or= Leaflet.map @$('#map')[0],
      zoomSnap: 0.2
    .fitBounds [
      # Zanzibar by default
      [-4.8587000, 39.8772333],
      [-6.4917667, 39.0945000]
    ]
    Leaflet.tileLayer('http://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
      maxZoom: 19,
      attribution: '&copy; OSM Mapnik <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    ).addTo(@map).bringToBack()

    longitudeProperty = @$("#longitudeColumn").val()
    latitudeProperty = @$("#latitudeColumn").val()

    markers = for rowData in @tabulator.getData("active")
      latitude = rowData[latitudeProperty]
      longitude = rowData[longitudeProperty]
      Leaflet.marker([latitude,longitude]).bindPopup(rowData)

    group = Leaflet.featureGroup(markers).addTo(@map)
    @map.fitBounds(group.getBounds())


  closeModal: =>
    @$("#modal").hide()


  applyAdvancedFilter: =>
    filter = @$("#advancedFilter").val()
    if filter is null or filter is ""
      @advancedFilterFunction = null
      return
    unless filter.match(/return/)
      if confirm "No return statement, do you want to add it?"
        filter = @$("#advancedFilter").val().split(/\n/)
        lastLine = "return " + filter.pop()
        filter.push lastLine
        @$("#advancedFilter").val filter.join("\n")
        filter = @$("#advancedFilter").val()

    @advancedFilterFunction = new Function('row', Coffeescript.compile(filter, bare:true))
    console.log @advancedFilterFunction
    @renderTabulator()

  updateIncludeEmpties: =>
    @includeEmptiesInCount = @$("#includeEmpties").is(":checked")
    @updateColumnCount()

  csv: => 
    if Tamarind.user.has "Tamarind CSV"
      @tabulator.download "csv", "#{@questionSet?.name()}-#{moment().format("YYYY-MM-DD_HHmm")}.csv"
    else
      alert "You don't have permission to download CSV data. You can request that the administrator adds CSV permission to your user account."

  itemCountCSV: =>
    if Tamarind.user.has "Tamarind CSV"
      @itemCountTabulator.download "csv", "#{@questionSet?.name()}ItemCount.csv"
    else
      alert "You don't have permission to download CSV data"

  toggleNext: (event) =>
    toggler = $(event.target).closest(".toggleNextSection")

    # Change the icon
    toggler.children().each (index, span) => $(span).toggle()

    toggler.parent().next("div").toggle() # Get the header then the sibling div

  toggle:  (options = {startClosed: true}) =>
    "
    <span style='cursor:pointer' class='toggleNextSection'>
      #{
      if options.startClosed
        "
        <span style='color:#00bcd4'>►</span>
        <span style='display:none; color:#00bcd4;'>▼</span>
        "
      else
        "
        <span style='display:none; color:#00bcd4'>►</span>
        <span style='color:#00bcd4;'>▼</span>
        "
      }
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
      <!-- Element that pops up when row is right clicked to show the full data -->
      <div style='position:fixed; overflow:scroll; z-index:1; width:100%; height:100%; display:none; background-color:rgba(0,0,0,0.4)' id='modal'>
        <div style='margin:auto; padding:20px; border: 1px solid #888; background-color:white'>
          <span class='close'>&times;</span>
          <div id='dataForCurrentRow'></div>
        </div>
      </div>
      <h3>Table #{@toggle(startClosed:false)}</h3>
      <div>
        <div>Advanced Filter #{@toggle()}</div>
        <div style='display:none'>
          <div class='description'>
            Advanced filters allow you to filter the data in the table with more control than just the matching filters at the top of the column. Each row will be passed as a 'row' object to the function. If it returns false then the row will be removed. This can use this to remove rows that have an empty column, or select for something like 'PF' but not 'NPF'.
            <div class='example'>Example:<br/>
              <pre><code>return row.MalariaTestResult is 'PF' and row.TravelLocationName #Must be exactly PF and TravelLocationName must not be empty</code></pre>
            </div>
          </div>


          <textarea style='width:50%; height:5em;'id='advancedFilter'></textarea>
          <button id='applyAdvancedFilter'>Apply</button>
        </div>
        <div>
          <div style='float:right; #{if @allowEdits then "" else "display:none"}'>
            Allow Edits<input style='accent-color:#00bcd4' type='checkbox' id='allowEdits'></input>
            <button style='display:none' type='button' id='saveEdits'>Save Edits</button>
            <button style='display:none' type='button' id='undoEdits'>Undo Edits</button>
          </div>
          <button id='download' style='#{if Tamarind.user.has "Tamarind CSV" then "" else "opacity:0.3"}'>CSV ↓</button> 
          <small>Add more fields by clicking the box below</small>
        </div>
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
      </div>
      <br/>
      <h3>Additional Analysis #{@toggle()}</h3>
      <div style='display:none'>
        <h4>Charts#{@toggle()}</h4>
        <div style='display:none'>
          To count and graph unique values in a particular column, select the column here: <select id='columnToCount'>
          <li>TODO: Bar and line option
          <li>TODO: Time series
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

        <h4>Pivot Tables#{@toggle()}</h4>
        <div style='display:none' id='pivotTableDiv'>
          For more complicated groupings and comparisons you can create a <button id='pivotButton'>Pivot Table</button>. The pivot table can also output CSV data that can be copy and pasted into a spreadsheet.
          <div id='pivotTable'></div>
        </div>
        <hr/>

        <h4>Maps#{@toggle()}</h4>
        <div style='display:none' id='mappingDiv'>
          If the data in the table includes the longitude and latitude field specified below it will be mapped here.
          <li>TODO: Animated Time series
          <li>TODO: Group by count and adjust dot size/heat map
          <br/>
          Longitude Column: <input id='longitudeColumn' value='gps-location-longitude'></input><br/>
          Latitude Column: <input id='latitudeColumn' value='gps-location-latitude'></input><br/>

          <button id='drawMap'>Draw/Update Map</button>
          <div style='width:auto; height:500px' id='map'></div>
        </div>
      </div>
    "
    unless availableTitles
      @getAvailableColumns()

    availableTitles = _(@availableColumns).pluck("title")

    @initialTitles = if @initialFields? and @initialFields.length > 0
      for field in @initialFields
        # Allow this initialFields to refer to either the title or the field name or the title slugified
        _(@availableColumns).find (column) =>
          column.field is field or
          column.title is field or
          column.title is slugify(field)
        ?.title

    else
      availableTitles[0..3]

    choicesData = for title in _(@initialTitles.concat(_(availableTitles).sort())).uniq() # This preserves order of initialTitles and alphabetizes the rest
      value: title
      selected: if _(@initialTitles).contains title then true else false

    @selector = new Choices "#availableTitles",
      choices: choicesData
      shouldSort: false
      removeItemButton: true
      searchResultLimit: 20

    @$("#availableTitles")[0].addEventListener 'change', (event) =>
      @renderTabulator()

    @renderTabulator()

    hljs.configure
      languages: ["coffeescript", "json"]
      useBR: false

    @$('pre code').each (i, snippet) =>
      hljs.highlightElement(snippet);


  getAvailableColumns: () =>
    questionLabels = _(@questionSet?.data.questions).pluck "label"

    @fieldsFromData or= {}

    if _(@fieldsFromData).isEmpty()
      console.log "Sampling data to determine available fields"
      for item in _(@data).sample(10000) # In case we have results from older question sets with different questions we will find it here. Use sample to put an upper limit on how many to check. (If the number of results is less than the sample target it just uses the number of results.
        for key,value of item
          @fieldsFromData[key] = true if value? # Don't get fields if value is empty
      @fieldsFromData = Object.keys(@fieldsFromData)

    console.log @fieldsFromData

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
    console.log orderedColumnTitlesAndFields
    @availableColumns = for column in orderedColumnTitlesAndFields
      if column.field.match(/\./)
        #console.log "Renaming field:#{column.field} due to period: #{column.field.replace(/\./,"")}"
        @fieldsWithPeriodRemoved.push column.field
        column.field = column.field.replace(/\./,"")
      if column.field.match(/photo/i)
        # TODO make this faster by not putting image data here and looking it up only when the image is clicked.
        column.formatter = (cell) =>
          "<button class='showImage' type='button' data-image='#{cell.getValue()}'>Show Image</button>"
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

    # Toggle editing of cells
    selectedColumns = for column in selectedColumns
      column.editor = if @editsEnabled then "input" else undefined
      column



    @renderedData = @data
    if @fieldsWithPeriodRemoved.length > 0 or @advancedFilterFunction
      @renderedData = []
      for item in @data
        for column in @fieldsWithPeriodRemoved
          item[column.replace(/\./,"")] = item[column]
        if @advancedFilterFunction
          if @advancedFilterFunction(item)
            @renderedData.push item
        else
          @renderedData.push item

    if @tabulator
      @tabulator.setColumns(selectedColumns)
      @tabulator.setData @renderedData
    else

      @tabulator = new Tabulator "#tabulatorForTabulatorView",
        height: 500
        columns: selectedColumns
        data: @renderedData
      @tabulator.on "dataFiltered", (filters, rows) =>
        @$("#numberRows").html(rows.length)
        _.delay =>
          @updateColumnCount()
        , 500

      @tabulator.on "dataLoaded", (data) =>
        @$("#numberRows").html(data.length)
        _.delay =>
          @updateColumnCount()
        , 500
      @tabulator.on "rowClick", (event, row) =>
        @rowClick?(row) # If a rowClick function exists call it - lets others views hook into this

      @tabulator.on "rowContext", (event, row) =>
        @$("#dataForCurrentRow").html "
          <pre><code>
            #{CSON.stringify(row.getData(), null, "  ")}
          </code></pre>
        "
        @$("#modal").show()

        @$('pre code').each (i, snippet) =>
          hljs.highlightElement(snippet);
        event.preventDefault()

    if @editsEnabled
      @tabulator.on "cellEdited", =>
        @$("#saveEdits").show()
        @$("#undoEdits").show()

    @$("#tabulatorForTabulatorView").css("border","5px solid #00bcd4")
    _.delay =>
      @$("#tabulatorForTabulatorView").css("border","2px solid #00bcd4")
    , 500
    _.delay =>
      @$("#tabulatorForTabulatorView").css("border","")
    , 1000
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
        unless Tamarind.user.has "Tamarind CSV"
          alert "You don't have permission for CSV Export"
          return
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
