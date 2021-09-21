Backbone = require 'backbone'

class GatewayView extends Backbone.View
  render: =>

    @$el.html "
      <style>
        li {
          padding-top: 2em;
        }
        li a{
          font-size: 2em;
        }
      </style>
      <h1>#{@gatewayName}</h1>
      <h2>Select a question set</h2>
      <div id='questions'/>
      <br/>
      <h2>Create a new question set</h2>
      <div>
        <input id='newQuestionSet'/>
        <button id='create'>Create</button>
      </div>

    "

    @questionSets = []
    @$("#questions").html (for questionSetName, questionSet of Tamarind.gateway["Question Sets"]
      "
      <li>
        <a href='#questionSet/#{@serverName}/#{@gatewayName}/#{questionSetName}'>#{questionSetName}</a> 
        <button class='copy' data-question='#{questionSetName}'>Copy</button> 
        <button class='rename' data-question='#{questionSetName}'>Rename</button> 
        <button class='remove' data-question='#{questionSetName}'>Remove</button> 
      </li>
      "
    ).join("")


  events: =>
    "click #create": "newQuestionSet"
    "click .copy": "copy"
    "click .rename": "rename"
    "click .remove": "remove"


  copy: (event, renderOnDone = true) =>
    question = event.target.getAttribute("data-question")
    questionDoc = Tamarind.gateway["Question Sets"][question]
    newName = prompt("Name: ")
    if newName is question or newName is ""
      alert "Name must be different and not empty"
      return null
    questionDoc.label = newName
    await Tamarind.updateQuestionSetForCurrentGateway(questionDoc)
    @render() if renderOnDone

  rename: (event) =>
    unless await(@copy(event, false)) is false #only remove if copy succeeds!
      await @remove(event, false)
      @render()

  remove: (event, promptToDelete = true, renderOnDone = true) =>
    console.log event
    question = event.target.getAttribute("data-question")
    if not promptToDelete or confirm "Are you sure you want to remove #{question}?"
      if not promptToDelete or prompt("Confirm the name of question that you want to remove:") is question
        await Tamarind.updateQuestionSetForCurrentGateway({label: question}, {delete: true})
        @render() if renderOnDone


  newQuestionSet: =>
    newQuestionSetName = @$("#newQuestionSet").val()
    await Tamarind.updateQuestionSetForCurrentGateway(
      label: newQuestionSetName
      version: "#{moment().format("YYYY-MM-DD")}_v1"
      questions: []
    )
    @render()

module.exports = GatewayView
