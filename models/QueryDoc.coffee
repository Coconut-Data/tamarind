_ = require 'underscore'

class QueryDoc

  docId: => "tamarind-query-#{@Name}"

  fetch: =>
    console.log @
    @set(await Tamarind.localDatabaseMirror.get(@docId()))

  set: (object) =>
    _(@).extend object
    if object["Query Field Options"]
      @["Query Field Options"] = CSON.parse(@["Query Field Options"])

  getResults: (options = {}) =>

    console.log "getResults"

    if @["Combine Queries"]
      results = {}
      for query in @["Combine Queries"].Queries
        joinFieldValue = doc[@["Combine Queries"]["Join Field"]]
        queryDoc = new QueryDoc()
        queryDoc.set(query)
        prefix = if @["Combine Queries"]["Prefix"] is false
          ""
        else
          queryDoc["Prefix"] or queryDoc["Query Field Options"]?[0]?.field or ""
        options.rawResult = true

        # recurse!
        for result in (await queryDoc.getResults(options)).rows
          doc = result.doc
          newDataToAdd = {}
          if prefix # empty string returns false
            for property, value of doc
              newDataToAdd["#{prefix}-#{property}"] = value
          else
            newDataToAdd = doc

          # By default keep overwriting data
          results[joinFieldValue] = _(results[joinFieldValue]).extend(newDataToAdd)

      return Promise.resolve(results)
    else

      await @createOrUpdateDesignDocIfNeeded
        name: @Name
        fields: @Fields
        mapFunction: @["Map Function"]

      console.log @

      queryOptions =
        descending: true
        include_docs: true
        limit: @Limit or 10000

      # Build up the query options based on queryFieldOptions
      for field, index in @["Query Field Options"]
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

      console.log "Querying localDatabaseMirror #{@Name} with:"
      console.log CSON.stringify queryOptions, null, "  "

      Tamarind.localDatabaseMirror.query @Name, queryOptions
      .catch (error) => 
        if error.reason is "missing"
          alert "Query '#{@Name}' does not exist"
          return
        else
          console.error @
          console.error @Name
          console.error queryOptions
          console.error error
          alert "Error #{JSON.stringify error} + when querying #{@Name} with options:\n#{CSON.stringify queryOptions, null, "  "}"
      .then (result) => 
        console.log result
        alert "Result limit of #{queryOptions.limit} reached. There are probably more results for this query than are shown. You can change the limit by editing the query." if result.rows.length is queryOptions.limit

        if options.rawResult
          Promise.resolve(result.rows)
        else
          Promise.resolve(_(result.rows).pluck "doc")

  createOrUpdateDesignDocIfNeeded: (options = {}) =>
    name = options.name
    unless name
      console.error "createOrUpdateDesignDocIfNeeded is missing name"
      return
    console.log "Building index |#{name}|, this takes a while the first time."
    $("#messages").append "Building index |#{name}|, this takes a while the first time."

    mapFunction = if options.mapFunction
      options.mapFunction
    else if options.fields
      fields = options.fields.split(/, */)
      # concatenate the fields in order for emission
      """
      (doc) =>
        emit [
          #{fields.map( (field) => 
            "doc['#{field}']")
          .join(", ")}
        ]
      """
    else
      alert "Query Doc has no indexing information: need to set either 'Fields' or have a 'Map Function'"

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
    # Get the index building
    console.log "Querying to build index: #{name}"
    await Tamarind.localDatabaseMirror.query(name, {limit:1})
    .then => console.log "Index built!"
    .catch (error) => console.error error


module.exports = QueryDoc
