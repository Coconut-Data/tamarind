_ = require 'underscore'
AsyncFunction = Object.getPrototypeOf(`async function(){}`).constructor; # Strange hack to build AsyncFunctions https://davidwalsh.name/async-function-class

class QueryDoc

  docId: => "tamarind-queries-#{@Name}"

  fetch: =>
    console.log @
    @set(await Tamarind.localDatabaseMirror.get(@docId()))

  set: (object) =>
    _(@).extend object
    if object["Query Field Options"]
      @["Query Field Options"] = CSON.parse(@["Query Field Options"])

  getResults: (options = {}) =>
    console.log options

    #console.info "getResults for: #{CSON.stringify @, null, " "}"

    if @["Combine Queries"]?.length > 0
      console.log "Combine Queries"
      results = []
      joinMap = {}
      for query,queryIndex in @["Combine Queries"]
        queryDoc = new QueryDoc()
        queryDoc.Name = query
        console.log "************ #{queryDoc.Name} ************"
        await queryDoc.fetch()
        prefix = if @["Prefix"] is "false"
          ""
        else
          queryDoc["Prefix"] or "_question"
        options.rawResult = true

        # If the join field is a calculated field then add it as a selectedCalculatedField
        joinCalculatedField = await Tamarind.localDatabaseMirror.get("tamarind-calculated-fields-#{@["Join Field"]}")
        .catch => Promise.resolve null
        options.selectedCalculatedFields or= []
        options.selectedCalculatedFields.push(joinCalculatedField) if joinCalculatedField

        # recurse!
        for result in await queryDoc.getResults(options)
          doc = result.doc
          newDataToAdd = {}

          if prefix # empty string returns false
            if prefix is "_question"
              for property, value of doc
                newDataToAdd["#{doc.question}-#{property}"] = value
            else
              for property, value of doc
                newDataToAdd["#{prefix}-#{property}"] = value
          else
            newDataToAdd = doc

          joinFieldValue = doc[@["Join Field"]]

          # By default keep overwriting data
          # joinmap groups all rows returned by the first query that have the same joinFieldValue
          # as results from other queries come in this is used to merge them together
          if queryIndex is 0
            results.push newDataToAdd
            joinMap[joinFieldValue] or= []
            joinMap[joinFieldValue].push(results.length-1)
          else
            if joinMap[joinFieldValue]
              for indexInResultsWithJoinFieldValue in joinMap[joinFieldValue]
                results[indexInResultsWithJoinFieldValue] = _(results[indexInResultsWithJoinFieldValue]).extend(newDataToAdd)
            else
              # IGNORE SUBSEQUENT QUERIES THAT DON'T HAVE AN EXISTING joinFieldValue
        console.log results
        console.log joinMap

        alert "Undefined joinfield #{@["Join Field"]} when querying #{@Name}. Each row was undefined for the joinfield." if joinMap[undefined]? and Object.keys(joinMap).length is 1


      console.log results

      return Promise.resolve(results)
    else

      await @createOrUpdateDesignDocIfNeeded()

      queryOptions =
        descending: true
        include_docs: true
        limit: @Limit or 10000

      # Build up the query options based on queryFieldOptions
      for field, index in (@["Query Field Options"] or [])
        if index is 0 and (field.equals? or field.startValue? or field.endValue?)
          queryOptions.startkey = []
          queryOptions.endkey = []
        if field.equals?
          queryOptions.startkey.push field.equals
          queryOptions.endkey.push field.equals
        else
          #start/end are reversed since we use descending mode by default
          if field.startValue?
            field.startValue = moment().format("YYYY-MM-DD") if field.startValue is "now"
            queryOptions.endkey.push field.startValue 
          if field.endValue?
            field.endValue = moment().format("YYYY-MM-DD") if field.endValue is "now"
            queryOptions.startkey.push field.endValue

      _(queryOptions).extend @["Query Options"]

      console.log "Querying localDatabaseMirror #{@indexDoc?.Name or "_all_docs"} with:"
      console.log CSON.stringify queryOptions, null, "  "

      await( if @Index is "_all_docs"
        Tamarind.localDatabaseMirror.allDocs(queryOptions)
      else if @Index is "Combine Queries"
        alert "Invalid combine queries - no queries selected"
        throw "Invalid combine queries - no queries selected"
      else
        Tamarind.localDatabaseMirror.query(@indexDoc.Name, queryOptions)
      ).catch (error) => 
        if error.reason is "missing"
          alert "Index '#{@indexDoc.Name}' does not exist"
          return
        else
          console.error @
          console.error @indexDoc.Name
          console.error queryOptions
          console.error error
          alert "Error #{JSON.stringify error} + when querying #{@indexDoc.Name} with options:\n#{CSON.stringify queryOptions, null, "  "}"
      .then (result) => 
        alert "Result limit of #{queryOptions.limit} reached. There are probably more results for this query than are shown. You can change the limit by editing the query." if result.rows.length is queryOptions.limit


        console.log options

        if options.selectedCalculatedFields?.length > 0
          console.log "Query includes calculated fields"
          for calculatedField in options.selectedCalculatedFields

            if calculatedField.Initialize
              # https://stackoverflow.com/questions/1271516/executing-anonymous-functions-created-using-javascript-eval
              try
                initializeFunction = new AsyncFunction(Coffeescript.compile(calculatedField.Initialize, bare:true))
              catch error then alert "Error compiling #{calculatedField.Name}: #{error}\n#{CSON.stringify calculatedField, null, "  "}"
              await initializeFunction()

            # Might be faster to use new Function if there is no need of async here
            calculatedField.calculationFunction = new AsyncFunction('result', 
              try
                Coffeescript.compile(calculatedField.Calculation, bare:true)
              catch error then alert "Error compiling #{calculatedField.Name}: #{error}\n#{CSON.stringify calculatedField, null, "  "}"
            )

          # TODO check if calculated field depends on other calculated fields and check for circular dependencies
          # Note that the order selected is preserved so dependencies can be forced by including them manually at the beginning of the fields list

          message = "Adding Calculated Fields: #{options.selectedCalculatedFields.map( (field) => field.Name).join(", ")}"
          $("#messages").append "<h2>#{message}</h2>"
          console.log message
          result.rows.forEach (row) ->
            options.selectedCalculatedFields.forEach (calculatedField) ->
              row.doc[calculatedField.Name] = await calculatedField.calculationFunction(row.doc)

        console.log result

        if options.rawResult
          Promise.resolve(result.rows)
        else
          Promise.resolve(_(result.rows).pluck "doc")

  createOrUpdateDesignDocIfNeeded: () =>
    return if @Index is "_all_docs"
    unless @Index
      console.log @
      alert "Query doc has no index"
    indexDocId = "tamarind-indexes-#{@Index}"
    @indexDoc = await Tamarind.localDatabaseMirror.get(indexDocId).catch (error) => 
      if @Index is "Results By Question And Date" and confirm "'Results By Question and Date' doesn't exist. Do you want to create it?"
        newIndexDoc =
          _id: "tamarind-indexes-Results By Question And Date"
          Name: "Results By Question And Date"
          Fields: "question, createdAt"
        await Tamarind.localDatabaseMirror.put newIndexDoc
        .then => Promise.resolve newIndexDoc
      else
        Promise.resolve null

    alert "Index doc: #{indexDocId} can't be loaded." unless @indexDoc

    mapFunction = if @indexDoc["Map Function"]
      @indexDoc["Map Function"]
    else if @indexDoc["Fields"]
      fields = @indexDoc["Fields"].split(/, */)
      # concatenate the fields in order for emission
      if fields.length > 1
        """
        (doc) =>
          #{
          if fields[0] is "question"
            "return unless doc.question"
          else
            ""
          }
          emit [
            #{fields.map( (field) => 
              "doc['#{field}']")
            .join(", ")}
          ]
        """
      else if fields.length is 1
        """
        (doc) =>
          emit doc[#{fields[0]}}
        """
      else
        throw "Invalid fields property"

    else
      alert "Query Doc has no indexing information: need to set either 'Fields' or have a 'Map Function'"

    name = @indexDoc.Name

    viewDoc = 
      _id: "_design/#{name}"
      views:
        "#{name}":
          map: try Coffeescript.compile(mapFunction, bare:true) catch error then alert error

    await Tamarind.localDatabaseMirror.get("_design/#{name}")
    .then (doc) =>
      if doc?.views?[name]?.map is viewDoc.views[name].map
        console.log "Design doc: #{name}, already exists with current mapping function, not updating."
        return Promise.resolve()
      console.log "Updating design doc: #{name}"
      viewDoc._rev = doc._rev
      Tamarind.localDatabaseMirror.put viewDoc

    .catch (error) =>
      console.log "Could not get '_design/#{name}', adding it"
      console.log "Updating design doc: #{name} with:"
      console.log viewDoc
      Tamarind.localDatabaseMirror.put viewDoc


    console.log "Building index |#{name}|, this takes a while the first time."
    $("#messages").append "Building index |#{name}|, this takes a while the first time."


    # Get the index building
    console.log "Querying to build index: #{name}"
    await Tamarind.localDatabaseMirror.query(name, {limit:1})
    .then => console.log "Index built!"
    .catch (error) => console.error error


module.exports = QueryDoc
