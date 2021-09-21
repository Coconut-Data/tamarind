_ = require 'underscore'
cloneDeep = require('lodash/cloneDeep')

class QuestionSet
  constructor: (@idOrName) ->

  save: =>
    if Tamarind.database
      Tamarind.database.put(@data).then (response) =>
        @data._rev = response.rev
        Promise.resolve()
      .catch (error) =>
        alert "Error saving: #{JSON.stringify error}"
    else if Tamarind.gateway?
      currentDate = moment().format("YYYY-MM-DD")
      if @data.version.startsWith(currentDate)
        lastVersionForCurrentDate = parseInt(@data.version.match(/.*_v(.*)/)[1])
        @data.version = "#{currentDate}_v#{lastVersionForCurrentDate+1}"
      else
        @data.version = "#{currentDate}_v1"


      Tamarind.updateQuestionSetForCurrentGateway(@data)
    else
      throw "No place to save#{@idOrName}"

  fetch: =>
    if Tamarind.database
      Tamarind.database.get(@idOrName).then (@data) =>
        Promise.resolve()
    else if Tamarind.gateway?
      @data = Tamarind.gateway["Question Sets"]?[@idOrName]
      # Check to see if we already have it
    else
      throw "Can't fetch #{@idOrName}"


  name: => @idOrName

QuestionSet.fetch = (idOrName) =>
  questionSet = new QuestionSet(idOrName)
  await questionSet.fetch()
  questionSet

QuestionSet.properties =
  {
    "onValidatedComplete": 
      "description":"Coffeescript code that will be executed when the entire question is marked complete and validation is passed. Useful for dictating workflow. e.g. open URL, create new result with values copied over, etc."
      "example": ""
      "data-type": "coffeescript"
    "action_on_questions_loaded":
      "description":"Coffeescript code that will be executed after the questions and their current answers are loaded."
      "data-type": "coffeescript"
    "resultSummaryFields": 
      "description": "This is used to choose which fields are shown on the question set's results page. For instance if you want the table of results to show name and date, but not ID, you could use this."
      "data-type": "object"
      
    "complete_message": 
      "description": "When the questions have been completed, this message will be sent to finish. You can insert calculated values including captured data. For example. 'Thanks for your answers \#{ResultOfQuestion('Name')}'"
      "data-type": "text"
  }

QuestionSet.templateForPropertyType = (type) =>
  properties = QuestionSet.getQuestionProperties()
  cloneDeep(properties.type.options[type]?.template) # cloneDeep makes sure we don't overwrite the original template

QuestionSet.propertyList = =>
  _(QuestionSet.properties()).keys()

QuestionSet.getQuestionProperties = =>

  properties = QuestionSet.questionProperties
  # Add in plugin properties
  # Note that this changes the object, it doesn't create a copy
  if Tamarind.databasePlugins?
    for plugin in Tamarind.databasePlugins
      _(properties.type.options).extend plugin?.jackfruit?.types
  properties


QuestionSet.questionProperties  =
  {
    "calculated_label":
      "description":"This replaces the normal label. It allows calculated values inside the label to enable dynamically generated text. For example: '\#{ResultOfQuestion('First Name')}, What is your middle name?' will start the question with the value previously entered for 'First Name'"
      "data-type": "text"
    "action_on_change":
      "description":"Coffeescript code that will be executed after the answer to this question changes. Helper functions like showMessage() and warn() can be used here to display messages to the user when a value changes."
      "data-type": "coffeescript"
    "action_on_questions_loaded":
      "description":"Coffeescript code that will be executed after the questions and their current answers are loaded."
      "data-type": "coffeescript"
      "limit": "textMessages"
    "type":
      "description": "This is the type of question that will be displayed to the user"
      "data-type": "select"
      "options": {
        "text":
          "description": "Free text"
        "number":
          "description": "Only allows numbers to be entered"
        "date":
          "description": "Allows valid dates"
        "datetime-local":
          "description": "Allows valid datetimes"
        "radio":
          "description": "Allows selection from a list of choices"
          template: [
            type: "radio"
            "radio-options": "Yes,No"
          ]
        "autocomplete from list":
          "description": "Searches for a match with whatever text has been typed to the list of autocomplete options. Also allows non matches to be entered."
        "autocomplete from previous entries":
          "description": "Searches for a match with whatever text has been typed to all results that have been entered for this question before. Also allows new options to be chosen."
        "autocomplete from code":
          "description": "Searches for a match against the list created by running the code. Also allows new options to be chosen."
        "label":
          "description": "No result is recorded for labels. It is a way to provide extra instructions, create sections or titles on the question set interface."
        "image":
          "description": "Displays an image. TODO describe how this works." # TODO describe how this works, paths to the image, etc
          "limit": "coconut"
        "audio":
          "description": "Plays an audio file" # TODO describe how this works, paths to the image, etc
          template: [
            type: "audio"
            "url": "http://example.org/example.mp3"
          ]
        "hidden":
          "description": "Used to set data that doesn't require input from the user."
          "limit": "coconut"
        "location":
          "description": "Will save the GPS coordinates as reported by the device."
          "limit": "coconut"
        "qrcode":
          "description": "Scan a QR code and save the result as text"
          "limit": "coconut"
        "repeatableQuestionSet":
          "description": "Use another question set to insert a section of repeable questions"
      }
    "autocomplete-options":
      "description": "When type is autocomplete, these are the options that will be matched as the user types. Useful for selecting from a long list of options. When autocomplete from code is chosen, this will be code, but it needs to be javascript not coffeescript"
      "requires-type": "autocomplete"
      "data-type": "array"
    "radio-options":
      "description": "When type is radio, these are the options that will appear for the user to choose."
      "requires-type": "radio"
      "data-type": "array"
      # TODO - is there an option to allow multiple selections?
    "validation":
      "description": "Coffeescript code that will be executed when the value changed. The variable 'value' is set to the currently entered value and is available for use by the code. If the result is anything but null, then validation fails, and the result is used as an error message."
      "data-type": "coffeescript"
      "example": "return 'Age must be between 0 and 200' if value < 0 or value > 200 # Makes sure the value is between 0 and 200<br/>if value.match(\" \") then null else \"You must use 2 official names.\" #Checks for a space in the answer, since two names will need a space in between them."
    "completeQuestionSetIf": 
      "description": "Coffeescript code that will be executed when the value is changed. If the code returns true, then the rest of the questions will be skipped (including required fields and validation) and the question set will be marked as complete."
      "data-type": "coffeescript"
      "example": "value is 'No' # This will skip the rest of the questions if the value is 'No'"
    "skip_logic":
      "description": "Coffeescript code that will be executed every time any value in the question set changes. If the result is true, then the question will be hidden, and validation will not be required to pass in order for the answer, and therefore the entire question set to be considered valid. ResultOfQuestion('What is your age') and PreviousQuestionResult() are helpful functions."
      "data-type": "coffeescript"
    "required":
      "description": "Determines whether the question must be answered in order for the answer to be considered valid."
      "data-type": "select"
      "options": [
        true
        false
      ]
    "label": 
      "description": "The text for the question that will be displayed on screen"
      "data-type": "text"
      "required": true
    "repeatableQuestionSetName": 
      "description": "The name of the question set to be inserted as a repeateable section"
      "data-type": "text"
      "required": true
    "url": 
      "description": "Path for the resource"
      "data-type": "text"
    "disable_fuzzy_search": 
      "description": "For radio buttons, disable fuzzy searching if only perfect matches to the options should be accepted. Value should be true or false"
      "data-type": "select"
      "options": [
        true
        false
      ]
  }

QuestionSet.questionPropertyList = =>
  _(QuestionSet.questionPropertyList()).keys()

module.exports = QuestionSet
