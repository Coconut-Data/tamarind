$ = require 'jquery'
Backbone = require 'backbone'
Backbone.$  = $
_ = require 'underscore'
dasherize = require("underscore.string/dasherize")
titleize = require("underscore.string/titleize")
humanize = require("underscore.string/humanize")
slugify = require("underscore.string/slugify")
get = require 'lodash/get'
set = require 'lodash/set'
unset = require 'lodash/unset'
pullAt = require 'lodash/pullAt'
isJSON = require('is-json');
striptags = require 'striptags'
Sortable = require 'sortablejs'
global.Coffeescript = require 'coffeescript'
JsonDiffPatch = require 'jsondiffpatch'
underscored = require("underscore.string/underscored")

hljs = require 'highlight.js/lib/core';
hljs.registerLanguage('coffeescript', require ('highlight.js/lib/languages/coffeescript'))
hljs.registerLanguage('json', require ('highlight.js/lib/languages/json'))

global.QuestionSet = require '../models/QuestionSet'

class QuestionSetView extends Backbone.View
  events: =>
    "click .toggleNext": "toggleNext"
    "click .hljs-string": "clickParent"

  # Hack because json elements get a class that doesn't bubble events
  clickParent: (event) =>
    $(event.target).parent().click()

  toggleNext: (event) =>
    elementToToggle = $(event.target).next()
    if elementToToggle.hasClass("questionDiv")
      @activeQuestionLabel = elementToToggle.attr("data-question-label")
    elementToToggle.toggle()

  renderSyntaxHighlightedCodeWithTextareaForEditing: (options) =>
    propertyPath = options.propertyPath
    preStyle = options.preStyle or ""
    example = options.example

    code = if propertyPath
      get(@questionSet.data, propertyPath)
    else
      @questionSet.data
    code = JSON.stringify(code, null, 2) if _(code).isObject()

    # https://stackoverflow.com/questions/19913667/javascript-regex-global-match-groups
    regex = /ResultOfQuestion\("(.+?)"\)/g
    matches = []
    questionsReferredTo = []
    while (matches = regex.exec(code))
      questionsReferredTo.push("#{matches[1]}: Test Value")

    questionsReferredTo = _(questionsReferredTo).unique()

    "
      <pre style='#{preStyle}'><code class='toggleToEdit'>#{code}</code></pre>
      <div class='codeEditor' style='display:none'>
        #{
          if example

            "Examples:<br/><code class='example'>#{example}</code><br/>"
          else ""
        }
        <textarea style='display:block' class='code' data-property-path=#{propertyPath}>#{code}</textarea>
        <button class='save'>Save</button>
        <button class='cancel'>Cancel</button>
        <span class='charCount' style='color:grey'></span>
        #{ if propertyPath
          "
            <br/>
            <br/>
            <span style='background-color: black; color: gray; padding: 2px; border: solid 2px;' class='toggleNext'>Test It</span>
            <div style='display:none'>
              Set ResultOfQuestion values (e.g. Name: Mike McKay, Birthdate: 2012-11-27 or put each pair on a new line)
              <br/>
              <textarea style='height:60px' class='testResultOfQuestion'>#{questionsReferredTo.join("""\n""")}</textarea>
              <br/>
              <br/>
              Set the value to use for testing the current value
              <br/>
              <input class='testValue'></input>
              <br/>
              <br/>
              Test Code: 
              <br/>
              <textarea class='testCode'></textarea>
              <br/>
            </div>
          "
        else
          ""
        }
      </div>
    "


  render: =>
    fullQuestionSetAsPrettyPrintedJSON = JSON.stringify(@questionSet.data, null, 2)
    @$el.html "
      <style>
        .description{
          font-size: small;
          color:gray
        }
        .questionSetProperty{
          margin-top:5px;
        }
        textarea{
          width:600px;
          height:200px;
        }
        code, .toggleToEdit:hover, .toggleNext:hover, .clickToEdit:hover{
          cursor: pointer
        }
        .question-label{
          font-weight: bold;
          font-size: large;

        }
        .clickToEdit{
          background-color: black;
          color: gray;
          padding: 2px;
          border: solid 2px;
        }
        .highlight{
          background-color: yellow
        }

      </style>
      #{
        if @isTextMessageQuestionSet()
          "
          <div style='float:right; width:200px; border: 1px solid;'>
            <a href='#messaging/#{@serverName}/#{@databaseOrGatewayName}/#{@questionSet.name()}'>Manage Messaging</a>
            <br/>
            <br/>
            <br/>
            <div style='width:200px; border: 1px solid;' id='interact'/>
          </div>
          <h2>Gateway: <a href='#gateway/#{@serverName}/#{@databaseOrGatewayName}'>#{@databaseOrGatewayName}</a>
          "
        else
          "<h2>Application: <a href='#database/#{@serverName}/#{@databaseOrGatewayName}'>#{@databaseOrGatewayName}</a>"
      }
      </h2>
      <h2>Question Set: #{titleize(@questionSet.name())} <span style='color:gray; font-size:small'>#{@questionSet.data.version or ""}</span></h2>
      <div id='questionSet'>
        <!--
        <div class='description'>
          Click on any <span style='background-color:black; color:gray; padding:2px;'>dark area</span> below to edit.
        </div>
        -->

        <h3><a id='resultsButton' href='#results/#{@serverName}/#{@databaseOrGatewayName}/#{@questionSet.name()}'>Results</a></h3>
        #{
          _.delay => # Delay it so the rest of the page loads quickly
            questionSetResultName = underscored(@questionSet.name().toLowerCase())
            startkey = "result-#{questionSetResultName}"
            endkey = "result-#{questionSetResultName}-\ufff0"
            Tamarind.database.allDocs
              startkey: startkey
              endkey: endkey
            .then (result) =>
              @$("#resultsButton").html "Results (#{result.rows.length})"
          , 1000
          ""
        }

        <div style='display:none'>
          <div class='description'>These options configure the entire question set as opposed to individual questions. For example, this is where you can run code when the page loads or when the question set is marked complete.</div>
          #{
            _(@questionSet.data).map (value, property) =>
              propertyMetadata = QuestionSet.properties[property]
              if propertyMetadata
                switch propertyMetadata["data-type"]
                  when "coffeescript", "object","text"
                    "
                      <div>
                        <div class='questionSetProperty'>
                          <div class='questionSetPropertyName'>
                            #{property} 
                            <div class='description'>
                              #{propertyMetadata.description}
                            </div>
                          </div>
                          #{
                            @renderSyntaxHighlightedCodeWithTextareaForEditing
                              propertyPath: property
                              example: propertyMetadata.example
                          }
                        </div>
                      </div>
                    "
                  else
                    console.error "Unknown type: #{propertyMetadata["data-type"]}: #{value}"
                    alert "Unhandled type"
              else
                return if _(["_id", "label", "_rev", "isApplicationDoc", "collection", "couchapp", "questions", "version"]).contains property
                console.error "Unknown question set property: #{property}: #{value}"
            .join("")
          }

        </div>

        <h2>Questions</h2>
        <div class='description'>Below is a list of all of the questions in this question set.</div>

        <div id='questions'>

        #{
          _(@questionSet.data.questions).map (question, index) =>
            "
            <div class='sortable' id='question-div-#{index}'>
              <div class='toggleNext question-label'>
                <span class='handle'>&#x2195;</span> 
                #{striptags(question.label)}
                <div style='margin-left: 20px; font-weight:normal;font-size:small'>
                  #{if question["radio-options"] then "<div>#{question["radio-options"]}</div>" else ""}
                  #{if question["skip_logic"] then "<div>Skip if: <span style='font-family:monospace'>#{question["skip_logic"]}</span></div>" else ""}
                </div>

              </div>
              <div class='questionDiv' data-question-label='#{question.label}' style='display:none; margin-left: 10px; padding: 5px; background-color:#DCDCDC'>
                <div>Properties Configured:</div>
                #{
                  _(question).map (value, property) =>
                    propertyMetadata = QuestionSet.questionProperties[property]
                    if propertyMetadata 

                      dataType = propertyMetadata["data-type"]
                      if question.type is "autocomplete from code" and question["autocomplete-options"]
                        dataType = "coffeescript"

                      propertyPath = "questions[#{index}][#{property}]"
                      "
                      <hr/>
                      <div class='questionPropertyName'>
                        #{property}
                        
                        <div class='description'>
                          #{propertyMetadata.description}
                        </div>
                      </div>
                      " +  switch dataType
                        when "coffeescript", "text", "json"
                          "
                            <div>
                              <div data-type-of-code='#{property}' class='questionProperty code'>
                                #{
                                  if property is "url" and value.endsWith("mp3")
                                    "<audio controls src='#{value}'></audio>"
                                  else
                                    ""
                                }
                                #{
                                  @renderSyntaxHighlightedCodeWithTextareaForEditing
                                    propertyPath: propertyPath
                                    example: propertyMetadata.example
                                }
                              </div>
                            </div>
                          "
                        when "select"
                          "
                            <div>
                              #{property}: <span style='font-weight:bold'>#{question[property]}</span> 

                              <div style='display:none'>
                                <select style='display:block' data-property-path='#{propertyPath}'>
                                #{
                                  _(propertyMetadata.options).map (optionMetadata, option) =>
                                    if _(optionMetadata).isBoolean()
                                      "<option #{if optionMetadata is question[property] then "selected=true" else ""}>#{optionMetadata}</option>"
                                    else
                                      "<option #{if option is question[property] then "selected=true" else ""}>#{option}</option>"
                                  .join ""
                                }
                                </select>
                                <button class='save'>Save</button>
                                <button class='cancel'>Cancel</button>
                              </div>
                            </div>
                          "
                        when "array"
                          console.log question
                          value = "Example Option 1, Example Option 2" unless value
                          "
                            <div>
                              Items: 
                              <ul>
                                #{
                                  _(value.split(/, */)).map (item) =>
                                    "<li>#{item}</li>"
                                  .join("")
                                }
                              </ul>
                            </div>
                          "

                        else
                          console.error "Unknown type: #{propertyMetadata["data-type"]}: #{value}"
                    else
                      console.error "Unknown property: #{property}: #{value}"
                  .join("")
                  #
                  #

                }

                <br/>
                <br/>
              </div>
            </div>
            "
          .join("")
          
        }
        </div>

        <hr/>
      </div>

    "
    hljs.configure
      languages: ["coffeescript", "json"]
      useBR: false

    @$('pre code').each (i, snippet) =>
      hljs.highlightElement(snippet);

    @sortable = Sortable.create document.getElementById('questions'),
      handle: ".handle"
      onUpdate: (event) =>
        # Reorder the array
        # https://stackoverflow.com/a/2440723/266111
        @sortable.option("disabled", true)
        @questionSet.data.questions.splice(event.newIndex, 0, @questionSet.data.questions.splice(event.oldIndex, 1)[0])
        @changesWatcher.cancel()
        await @questionSet.save()
        @render()
        @sortable.option("disabled", false)

    @openActiveQuestion()

    @resetChangesWatcher()

  resetChangesWatcher: =>
    if Tamarind.database?
      Tamarind.database.changes
        limit:1
        descending:true
      .then (change) =>  
        @changesWatcher = Tamarind.database.changes
          live: true
          doc_ids: [router.questionSetView.questionSet.data._id]
          since: change.last_seq
        .on "change", (change) =>
          console.log change
          @changesWatcher.cancel()
          if confirm("This question set has changed - someone else might be working on it. Would you like to refresh?")
            @questionSet.fetch().then => @render()
    else
      # Create an empty changesWatcher
      @changesWatcher = 
        cancel: ->

  openActiveQuestion: =>
    if @activeQuestionLabel
      questionElement = @$(".toggleNext.question-label:contains(#{@activeQuestionLabel})")
      questionElement.click()
      questionElement[0].scrollIntoView()

  isTextMessageQuestionSet: =>
    Tamarind.dynamoDBClient?

module.exports = QuestionSetView
